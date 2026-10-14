import ColorsipCore
import CoreMedia
import CoreVideo
import OSLog
import ScreenCaptureKit

/// One captured frame of a display, in `format` and `colorSpace`.
final class ScreenFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let format: CapturePixelFormat
    let colorSpace: CGColorSpace

    init(pixelBuffer: CVPixelBuffer, format: CapturePixelFormat, colorSpace: CGColorSpace) {
        self.pixelBuffer = pixelBuffer
        self.format = format
        self.colorSpace = colorSpace
    }

    /// The grid's pixels and the center pixel as a color.
    func sample(_ grid: PixelGrid) -> (samples: [PixelSample?], center: CSipColor?) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return ([], nil) }
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let samples = PixelSampler.sample(
            grid, bytes: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
            width: CVPixelBufferGetWidth(pixelBuffer), height: height, bytesPerRow: bytesPerRow, format: format)
        let center = samples[grid.centerIndex].flatMap { CaptureColor.color($0, in: colorSpace) }
        return (samples, center)
    }
}

/// Streams the display under the pointer with ScreenCaptureKit (`spec.md` §4.2), at its native
/// pixel size, without Colorsip's own windows. Frames are composited in extended linear Display P3
/// as half floats, not in the display's own profile, which can clip colors; linear half floats
/// round-trip every 8-bit sRGB value. Only one display is captured at a time; `capture(_:)`
/// switches.
@MainActor
final class ScreenSampler {
    private(set) var frame: ScreenFrame?
    private var displayID: UInt32?
    private var stream: SCStream?
    private var output: StreamOutput?
    /// Bumped on every switch, so a late frame or start from the previous display is dropped.
    private var generation = 0
    private let onFrame: @MainActor () -> Void
    private let onError: @MainActor (any Error) -> Void
    private let log = Logger(subsystem: "com.nicolas-bettenburg.colorsip", category: "picker")

    init(onFrame: @escaping @MainActor () -> Void, onError: @escaping @MainActor (any Error) -> Void) {
        self.onFrame = onFrame
        self.onError = onError
    }

    /// The capture space; frames that carry their own profile use that instead.
    private static let captureColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)!

    /// Starts streaming `display`; a no-op if it's already the one.
    func capture(_ display: UInt32) {
        guard display != displayID else { return }
        displayID = display
        frame = nil
        generation += 1
        let generation = generation
        stopStream()
        Task {
            do {
                try await start(display, generation: generation)
            } catch {
                guard generation == self.generation else { return }
                log.error("Picker capture failed: \(error.localizedDescription, privacy: .public)")
                onError(error)
            }
        }
    }

    func stop() {
        generation += 1
        displayID = nil
        frame = nil
        stopStream()
    }

    /// Starts the most precise pixel format the system accepts.
    private func start(_ displayID: UInt32, generation: Int) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard generation == self.generation else { return }
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        var lastError: (any Error)?
        for format in CapturePixelFormat.allCases {
            do {
                try await start(filter, format: format, generation: generation)
                if format != .rgbaHalf {
                    log.notice("Picker capture fell back to \(String(describing: format), privacy: .public)")
                }
                return
            } catch {
                guard generation == self.generation else { return }
                log.error("Picker capture in \(String(describing: format), privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                lastError = error
            }
        }
        if let lastError { throw lastError }
    }

    private func start(_ filter: SCContentFilter, format: CapturePixelFormat, generation: Int) async throws {
        let configuration = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        configuration.width = Int((filter.contentRect.width * scale).rounded())
        configuration.height = Int((filter.contentRect.height * scale).rounded())
        configuration.pixelFormat = format.coreVideoType
        configuration.colorSpaceName = CGColorSpace.extendedLinearDisplayP3
        configuration.showsCursor = false
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 3

        let output = StreamOutput(format: format, fallbackColorSpace: Self.captureColorSpace) { [weak self] frame in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                if self.frame == nil {
                    let space = frame.colorSpace.name.map { $0 as String } ?? "unnamed"
                    self.log.info("Picker capture: \(String(describing: frame.format), privacy: .public) in \(space, privacy: .public)")
                }
                self.frame = frame
                self.onFrame()
            }
        }
        let stream = SCStream(filter: filter, configuration: configuration, delegate: output)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
        output.onStop = { [weak self] error in
            Task { @MainActor in
                guard let self, generation == self.generation else { return }
                self.onError(error)
            }
        }
        try await stream.startCapture()
        guard generation == self.generation else {
            try? await stream.stopCapture()
            return
        }
        self.stream = stream
        self.output = output
    }

    private func stopStream() {
        guard let stream else { return }
        self.stream = nil
        output = nil
        Task { try? await stream.stopCapture() }
    }

    enum CaptureError: Error {
        case displayNotFound
    }
}

/// Receives frames on its own queue and hands complete ones to `onFrame`.
private final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.nicolas-bettenburg.colorsip.picker-capture")
    private let format: CapturePixelFormat
    private let fallbackColorSpace: CGColorSpace
    private let onFrame: @Sendable (ScreenFrame) -> Void
    var onStop: (@Sendable (any Error) -> Void)?

    init(format: CapturePixelFormat, fallbackColorSpace: CGColorSpace, onFrame: @escaping @Sendable (ScreenFrame) -> Void) {
        self.format = format
        self.fallbackColorSpace = fallbackColorSpace
        self.onFrame = onFrame
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Unchanged screens deliver idle frames without an image; the last complete frame stays.
        guard type == .screen, isComplete(sampleBuffer), let pixelBuffer = sampleBuffer.imageBuffer,
            // Decoding another layout than the one asked for would give wrong colors.
            CVPixelBufferGetPixelFormatType(pixelBuffer) == format.coreVideoType
        else { return }
        let attachments = CVBufferCopyAttachments(pixelBuffer, .shouldPropagate)
        let colorSpace = attachments.flatMap { CVImageBufferCreateColorSpaceFromAttachments($0)?.takeRetainedValue() }
        onFrame(ScreenFrame(pixelBuffer: pixelBuffer, format: format, colorSpace: colorSpace ?? fallbackColorSpace))
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onStop?(error)
    }

    private func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
            let raw = attachments.first?[.status] as? Int,
            let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }
}

extension CapturePixelFormat {
    var coreVideoType: OSType {
        switch self {
        case .rgbaHalf: kCVPixelFormatType_64RGBAHalf
        case .argb2101010: kCVPixelFormatType_ARGB2101010LEPacked
        case .bgra8: kCVPixelFormatType_32BGRA
        }
    }
}
