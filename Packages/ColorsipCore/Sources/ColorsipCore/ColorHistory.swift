import Foundation
import Observation

/// Color History (`spec.md` §7.4): the last 16 picks, newest first, stored in `history.json`:
///
/// ```json
/// { "formatVersion": 1, "swatches": [ { "id": "…", "color": { … }, "name": "…", … } ] }
/// ```
///
/// It is read-only: ``record(_:name:at:)`` is the only change. Picking a color that is already
/// there (by the equality rule in §5.1) replaces it with the new pick at the front.
///
/// Decoding is lenient: entries that can't be decoded are skipped. Only a newer `formatVersion`
/// makes the whole file unreadable.
public struct ColorHistory: Equatable, Sendable, Codable {
    public static let formatVersion = 1
    public static let capacity = 16

    /// Newest first, no two perceptually equal, at most ``capacity``.
    public private(set) var swatches: [Swatch]

    /// A history of `swatches`, newest first. Later duplicates and entries past ``capacity`` are
    /// dropped.
    public init(swatches: [Swatch] = []) {
        var unique: [Swatch] = []
        for swatch in swatches where unique.count < Self.capacity && unique.duplicate(of: swatch.color) == nil {
            unique.append(swatch)
        }
        self.swatches = unique
    }

    /// Adds a pick at the front, replacing an equal color that is already in history.
    public mutating func record(_ color: CSipColor, name: String, at date: Date = .now) {
        swatches.removeAll { $0.color.isPerceptuallyEqual(to: color) }
        swatches.insert(Swatch(color: color, name: name, createdAt: date), at: 0)
        if swatches.count > Self.capacity { swatches.removeLast(swatches.count - Self.capacity) }
    }

    private enum CodingKeys: String, CodingKey {
        case formatVersion, swatches
    }

    /// Decodes anything, so that one bad entry doesn't fail the whole array.
    private struct Lenient<T: Decodable>: Decodable {
        var value: T?
        init(from decoder: any Decoder) throws { value = try? T(from: decoder) }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let version = try? container.decodeIfPresent(Int.self, forKey: .formatVersion), version > Self.formatVersion {
            throw ColorsipFormatError.newerFormat(version)
        }
        let entries = (try? container.decodeIfPresent([Lenient<Swatch>].self, forKey: .swatches)) ?? []
        self.init(swatches: entries.compactMap(\.value))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.formatVersion, forKey: .formatVersion)
        try container.encode(swatches, forKey: .swatches)
    }
}

/// Loads and saves `history.json`. Every pick is saved at once, atomically. A file that couldn't be
/// loaded (corrupt or from a newer Colorsip) is never overwritten: history starts empty for the
/// session and `loadIssue` reports it.
///
/// History isn't part of the library, so undo and redo never touch it (`spec.md` §7.6).
@MainActor
@Observable
public final class ColorHistoryController {
    public private(set) var history: ColorHistory
    public private(set) var loadIssue: LibraryLoadIssue?
    /// The last save error, cleared by the next successful save.
    public private(set) var lastError: (any Error)?

    private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
        let file = LibraryFile.history.rawValue
        do {
            history = try store.load(ColorHistory.self, from: .history) ?? ColorHistory()
        } catch ColorsipFormatError.newerFormat(let version) {
            history = ColorHistory()
            loadIssue = .newerFormat(file: file, version: version)
        } catch {
            history = ColorHistory()
            loadIssue = .unreadable(file: file)
        }
    }

    public func record(_ color: CSipColor, name: String, at date: Date = .now) {
        history.record(color, name: name, at: date)
        guard loadIssue == nil else { return }
        do {
            try store.save(history, to: .history)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
