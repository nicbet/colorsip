import AppKit
import ColorsipCore
import struct ColorsipCore.KeyboardShortcut
import SwiftUI

/// Renders the popover, the picker, the color editor and Settings to PNGs for the README, in light
/// and dark (`Colorsip --snapshot <dir>`, or `make snapshot`). It draws offscreen, so it needs no
/// Screen Recording permission, and it uses a sample library in a temporary folder and throwaway
/// defaults, so the user's library and settings are never touched.
@MainActor
enum Snapshot {
    private static let scale: CGFloat = 2

    /// The output folder when the app was launched with `--snapshot <dir>`.
    static var requestedDirectory: URL? {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    /// Writes the snapshots and quits. Controls draw dimmed unless the app is active, so this runs
    /// once the app has finished launching.
    static func run(to directory: URL) {
        // Launched from a terminal, the cooperative `activate()` is refused.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            do {
                for url in try write(to: directory) { print(url.path) }
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("snapshot failed: \(error)\n".utf8))
                exit(1)
            }
        }
    }

    static func write(to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let sample = try SampleLibrary()
        defer { sample.remove() }

        var urls: [URL] = []
        for dark in [false, true] {
            let suffix = dark ? "dark" : "light"
            func save<V: View>(_ name: String, _ view: V) throws {
                urls.append(try Snapshot.save(view, to: directory.appendingPathComponent("\(name)-\(suffix).png")))
            }

            let model = sample.model()
            let popover = capture(PopoverView(model: model, actions: .none), dark: dark, background: .popover)
            try save("popover", MenuBarScene(popover: popover, dark: dark))

            let editing = sample.model()
            if let edited = sample.editedSwatch(in: editing) {
                editing.editorModel = .oklch
                editing.openEditor(edited.swatch, in: edited.section)
            }
            let editor = capture(PopoverView(model: editing, actions: .none), dark: dark, background: .popover)
            try save("editor", MenuBarScene(popover: editor, dark: dark))

            let settings = sample.model()
            settings.settingsPane = .profiles
            let window = capture(MainWindowView(model: settings), dark: dark, title: "Colorsip",
                                 size: CGSize(width: 560, height: 480))
            try save("settings", WindowScene(window: window, dark: dark))

            try save("picker", pickerScene(dark: dark))
        }
        return urls
    }

    // MARK: Capturing

    private enum Background {
        case window
        /// The popover's own fill (`PopoverBackgroundView`).
        case popover

        func color(dark: Bool) -> NSColor {
            switch self {
            case .window: .windowBackgroundColor
            case .popover: dark ? .windowBackgroundColor : NSColor(srgbRed: 0xE5 / 255.0, green: 0xE7 / 255.0, blue: 0xE9 / 255.0, alpha: 1)
            }
        }
    }

    /// Draws `view` in an offscreen window of `size`, or the view's own size. With a title, the
    /// window's frame (title bar and traffic lights) is drawn too; without one, only the view on
    /// `background`.
    private static func capture<V: View>(
        _ view: V, dark: Bool, title: String? = nil, size: CGSize? = nil, background: Background = .window
    ) -> NSImage {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        let window = KeyWindow(contentRect: CGRect(origin: .zero, size: size ?? host.fittingSize),
                               styleMask: title == nil ? [.borderless] : [.titled, .closable, .miniaturizable],
                               backing: .buffered, defer: false)
        window.appearance = appearance
        window.title = title ?? ""
        window.contentView = host
        // On screen (for key status), but far outside the visible area.
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        window.makeKey()
        // Let SwiftUI finish its first update passes; the palette list measures itself in them.
        for _ in 0..<3 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            window.setContentSize(size ?? host.fittingSize)
            window.layoutIfNeeded()
        }

        let target = title == nil ? host : (host.superview ?? host)
        let bounds = target.bounds
        guard let rep = bitmap(size: bounds.size) else { return NSImage() }
        appearance?.performAsCurrentDrawingAppearance {
            if title == nil, let context = NSGraphicsContext(bitmapImageRep: rep) {
                // A borderless window doesn't draw its background into the cache.
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = context
                background.color(dark: dark).setFill()
                bounds.fill()
                NSGraphicsContext.restoreGraphicsState()
            }
            target.cacheDisplay(in: bounds, to: rep)
        }
        window.orderOut(nil)
        return image(rep)
    }

    private static func bitmap(size: CGSize) -> NSBitmapImageRep? {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        rep?.size = size
        return rep
    }

    private static func image(_ rep: NSBitmapImageRep) -> NSImage {
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }

    private static func render<V: View>(_ view: V) -> CGImage? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        return renderer.cgImage
    }

    private static func save<V: View>(_ view: V, to url: URL) throws -> URL {
        guard let image = render(view),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
        return url
    }

    // MARK: Picker

    /// The loupe and its label over a sample design. The loupe shows the design's own pixels.
    private static func pickerScene(dark: Bool) -> some View {
        let design = DesignScene(dark: dark)
        guard let background = render(design), let pixels = Pixels(background) else {
            return AnyView(design)
        }
        // Where two tiles meet the gap between them, in points from the top left.
        let pointer = DesignScene.pointer
        let gridSize = 11
        let center = (x: Int(pointer.x * scale), y: Int(pointer.y * scale))
        // Rows top to bottom, as `PickerGrid` delivers them to the loupe.
        var samples: [PixelSample?] = []
        for row in 0..<gridSize {
            for column in 0..<gridSize {
                samples.append(pixels.sample(x: center.x + column - gridSize / 2, y: center.y + row - gridSize / 2))
            }
        }
        let picked = samples[samples.count / 2].map { CSipColor(.srgb, $0.red, $0.green, $0.blue) }
        let size = DesignScene.size
        let loupe = LoupeView(frame: CGRect(origin: .zero, size: size))
        let window = NSWindow(contentRect: loupe.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = loupe
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        loupe.content = LoupeView.Content(
            point: CGPoint(x: window.frame.minX + pointer.x, y: window.frame.minY + size.height - pointer.y),
            diameter: 200, gridSize: gridSize, samples: samples,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB),
            label: picked.map { PickerLabel(value: $0.formatted(as: .cssHex), name: $0.friendlyName, profile: .srgb) })
        guard let rep = bitmap(size: size) else { return AnyView(design) }
        loupe.cacheDisplay(in: loupe.bounds, to: rep)
        return AnyView(ZStack {
            Image(decorative: background, scale: scale)
            Image(nsImage: image(rep))
        })
    }

    /// An image's pixels as 8-bit sRGB, for sampling.
    private struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init?(_ image: CGImage) {
            width = image.width
            height = image.height
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                    bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
                return true
            }
            guard drawn else { return nil }
            self.bytes = bytes
        }

        /// The pixel at `x`, `y` from the top left.
        func sample(x: Int, y: Int) -> PixelSample? {
            guard (0..<width).contains(x), (0..<height).contains(y) else { return nil }
            let i = (y * width + x) * 4
            return PixelSample(red: Double(bytes[i]) / 255, green: Double(bytes[i + 1]) / 255,
                               blue: Double(bytes[i + 2]) / 255, alpha: 1)
        }
    }
}

private extension PopoverActions {
    static let none = PopoverActions(picker: {}, repick: {}, newPalette: {}, settings: {}, quit: {})
}

/// Becomes key even when borderless, so its controls draw active.
private final class KeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Sample library

/// A library folder with sample palettes and history, removed when the snapshots are done.
@MainActor
private struct SampleLibrary {
    let folder: URL
    let defaultsSuite = "app.colorsip.snapshot.\(UUID().uuidString)"
    private let editedName = "Coral"

    init() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("colorsip-snapshot-\(UUID().uuidString)")
        let store = LibraryStore(folder: folder)
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        func swatches(_ hexes: [String]) -> [Swatch] {
            hexes.map { let color = CSipColor(hex: $0); return Swatch(color: color, name: color.friendlyName, createdAt: date) }
        }
        func shades(_ name: String, _ hexes: [String]) -> SwatchGroup {
            SwatchGroup(name: name, swatches: swatches(hexes))
        }

        let brand = Palette(
            name: "Brand", icon: .emoji("🍹"), createdAt: date,
            ungrouped: [Swatch(color: CSipColor(hex: "#ff7f6e"), name: editedName, createdAt: date)]
                + swatches(["#3c3cdb", "#1f2937"]),
            groups: [
                shades("Primary", ["#818cf8", "#6366f1", "#4f46e5", "#4338ca"]),
                shades("Accent", ["#2dd4bf", "#fbbf24", "#f43f5e"]),
            ])
        let tailwind = Palette(
            name: "Tailwind", icon: .symbol("wind"), createdAt: date,
            groups: [
                shades("Sky", ["#f0f9ff", "#e0f2fe", "#bae6fd", "#7dd3fc", "#38bdf8", "#0ea5e9", "#0284c7",
                               "#0369a1", "#075985", "#0c4a6e", "#082f49"]),
                shades("Emerald", ["#ecfdf5", "#d1fae5", "#a7f3d0", "#6ee7b7", "#34d399", "#10b981", "#059669",
                                   "#047857", "#065f46", "#064e3b", "#022c22"]),
                shades("Amber", ["#fffbeb", "#fef3c7", "#fde68a", "#fcd34d", "#fbbf24", "#f59e0b", "#d97706",
                                 "#b45309", "#92400e", "#78350f", "#451a03"]),
            ])
        let sunset = Palette(
            name: "Sunset", icon: .emoji("🌅"), isLocked: true, createdAt: date,
            ungrouped: swatches(["#2b1b4d", "#5c2a6b", "#a23e76", "#e0656b", "#f59a5c", "#ffd27a"]))
        try store.save(Library(palettes: [brand, tailwind, sunset], pickTarget: brand.id), previous: nil)

        var history = ColorHistory()
        for hex in ["#ffd27a", "#0ea5e9", "#a23e76", "#34d399", "#f43f5e", "#6366f1", "#fde68a", "#1f2937",
                    "#ff7f6e", "#3c3cdb"] {
            let color = CSipColor(hex: hex)
            history.record(color, name: color.friendlyName, at: date)
        }
        try store.save(history, to: .history)
    }

    /// A fresh model over the sample library, with stub system services.
    func model() -> AppModel {
        AppModel(
            loginItemService: StubLoginItem(), hotKeyRegistrar: StubHotKeys(), permissionChecker: AllGranted(),
            libraryStore: LibraryStore(folder: folder),
            localSettings: LocalSettings(defaults: UserDefaults(suiteName: defaultsSuite) ?? .standard),
            soundPlayer: Silent())
    }

    /// The swatch the editor snapshot opens.
    func editedSwatch(in model: AppModel) -> (swatch: Swatch, section: SectionID)? {
        guard let palette = model.library.library.palettes.first,
              let swatch = palette.ungrouped.first(where: { $0.name == editedName })
        else { return nil }
        return (swatch, .ungrouped(palette.id))
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
    }
}

private final class StubLoginItem: LoginItemService {
    var status: LoginItemStatus { .notRegistered }
    func register() throws {}
    func unregister() throws {}
}

private final class StubHotKeys: HotKeyRegistrar {
    var onPress: ((ShortcutAction) -> Void)?
    func register(_ shortcut: KeyboardShortcut, for action: ShortcutAction) -> Bool { true }
    func unregister(_ action: ShortcutAction) {}
    func isReservedBySystem(_ shortcut: KeyboardShortcut) -> Bool { false }
}

private final class AllGranted: PermissionChecker {
    func isGranted(_ permission: Permission) -> Bool { true }
}

private struct Silent: SoundPlayer {
    func play(_ effect: SoundEffect) {}
}

private extension CSipColor {
    /// An sRGB color from `#rrggbb`.
    init(hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(.srgb, Double(value >> 16 & 0xFF) / 255, Double(value >> 8 & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

// MARK: - Scenes

/// A desktop in Colorsip's colors.
private struct Wallpaper: View {
    let dark: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: dark
                               ? [Color(red: 0.10, green: 0.09, blue: 0.24), Color(red: 0.30, green: 0.12, blue: 0.30)]
                               : [Color(red: 0.80, green: 0.86, blue: 1.00), Color(red: 1.00, green: 0.80, blue: 0.76)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.17, green: 0.83, blue: 0.75).opacity(dark ? 0.3 : 0.35), .clear],
                           center: UnitPoint(x: 0.15, y: 0.9), startRadius: 0, endRadius: 420)
        }
    }
}

/// A menu bar over the wallpaper.
private struct MenuBar<StatusItem: View>: View {
    let app: String
    let dark: Bool
    @ViewBuilder let statusItem: StatusItem

    static var height: CGFloat { 26 }

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "apple.logo").font(.system(size: 14))
            Text(app).fontWeight(.bold)
            ForEach(["File", "Edit", "View", "Window", "Help"], id: \.self) { Text($0) }
            Spacer()
            statusItem
            Image(systemName: "wifi")
            Image(systemName: "battery.75percent")
            Image(systemName: "switch.2")
            Text("Thu 15 Oct  9:41")
        }
        .font(.system(size: 13))
        .foregroundStyle(dark ? .white : .black)
        .padding(.horizontal, 16)
        .frame(height: Self.height)
        .background((dark ? Color.black : Color.white).opacity(dark ? 0.3 : 0.35))
    }
}

/// A window or popover image with its rounded corners, hairline and shadow.
private struct Floating: View {
    let image: NSImage
    let dark: Bool

    var body: some View {
        Image(nsImage: image)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(dark ? 0.2 : 0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(dark ? 0.5 : 0.25), radius: 24, y: 12)
    }
}

/// The popover hanging from its menu bar item.
private struct MenuBarScene: View {
    let popover: NSImage
    let dark: Bool

    private let width: CGFloat = 760
    private var ink: Color { dark ? .white : .black }

    var body: some View {
        ZStack(alignment: .top) {
            Wallpaper(dark: dark)
            MenuBar(app: "Figma", dark: dark) { Color.clear.frame(width: 28) }

            // The popover's column lines up its item with the popover's center.
            VStack(spacing: 5) {
                statusItem
                Floating(image: popover, dark: dark)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 170)
        }
        .frame(width: width, height: MenuBar<EmptyView>.height + 5 + popover.size.height + 56)
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private var statusItem: some View {
        Image(systemName: "eyedropper.halffull")
            .font(.system(size: 13))
            .foregroundStyle(ink)
            .padding(.horizontal, 7)
            .frame(height: MenuBar<EmptyView>.height - 4)
            .background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.18)))
            .frame(height: MenuBar<EmptyView>.height)
    }
}

/// A window on the desktop.
private struct WindowScene: View {
    let window: NSImage
    let dark: Bool

    var body: some View {
        ZStack {
            Wallpaper(dark: dark)
            Floating(image: window, dark: dark)
        }
        .frame(width: window.size.width + 160, height: window.size.height + 120)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// A design canvas of color tiles, for the picker to sample.
private struct DesignScene: View {
    let dark: Bool

    static let size = CGSize(width: 760, height: 460)
    private static let tile = CGSize(width: 124, height: 72)
    private static let spacing: CGFloat = 12
    private static let origin = CGPoint(x: 64, y: 96)
    /// Just inside the bottom right corner of the second row's third tile, so the loupe shows the
    /// tile, its rounded corner and the canvas.
    static let pointer = CGPoint(
        x: origin.x + 2 * (tile.width + spacing) + tile.width - 6,
        y: origin.y + (tile.height + 22 + spacing) + tile.height - 2)

    private static let rows: [[(String, String)]] = [
        [("Sky 300", "#7dd3fc"), ("Sky 500", "#0ea5e9"), ("Sky 700", "#0369a1"), ("Sky 900", "#0c4a6e")],
        [("Indigo 400", "#818cf8"), ("Indigo 600", "#4f46e5"), ("Coral", "#ff7f6e"), ("Rose 500", "#f43f5e")],
        [("Emerald 300", "#6ee7b7"), ("Emerald 500", "#10b981"), ("Amber 300", "#fcd34d"), ("Amber 500", "#f59e0b")],
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Wallpaper(dark: dark)
            MenuBar(app: "Figma", dark: dark) { Image(systemName: "eyedropper.halffull") }
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(dark ? Color(white: 0.14) : Color(white: 0.98))
                .shadow(color: .black.opacity(dark ? 0.5 : 0.2), radius: 20, y: 10)
                .frame(width: 4 * Self.tile.width + 3 * Self.spacing + 64, height: 3 * (Self.tile.height + 22) + 2 * Self.spacing + 72)
                .offset(x: Self.origin.x - 32, y: Self.origin.y - 48)
            Text("Design tokens")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(dark ? .white : .black)
                .offset(x: Self.origin.x, y: Self.origin.y - 32)
            VStack(alignment: .leading, spacing: Self.spacing) {
                ForEach(Self.rows.indices, id: \.self) { row in
                    HStack(spacing: Self.spacing) {
                        ForEach(Self.rows[row], id: \.0) { name, hex in
                            VStack(alignment: .leading, spacing: 4) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: NSColor(srgbHex: hex)))
                                    .frame(width: Self.tile.width, height: Self.tile.height)
                                Text("\(name)  \(hex)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: Self.tile.width, height: 18, alignment: .topLeading)
                            }
                        }
                    }
                }
            }
            .offset(x: Self.origin.x, y: Self.origin.y)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

private extension NSColor {
    convenience init(srgbHex hex: String) {
        let value = Int(hex.dropFirst(), radix: 16) ?? 0
        self.init(srgbRed: Double(value >> 16 & 0xFF) / 255, green: Double(value >> 8 & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255, alpha: 1)
    }
}
