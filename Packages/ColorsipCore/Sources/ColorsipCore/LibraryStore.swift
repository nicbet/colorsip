import Foundation

/// A file in the library folder besides the palettes.
public enum LibraryFile: String, Sendable {
    /// Color History.
    case history = "history.json"
    /// Synced settings.
    case settings = "settings.json"
}

/// A problem found while loading the library. Files with a problem are skipped and never written.
public enum LibraryLoadIssue: Hashable, Sendable {
    /// The file couldn't be read or isn't valid. The path is relative to the library folder.
    case unreadable(file: String)
    /// The file was written by a newer Colorsip.
    case newerFormat(file: String, version: Int)
}

public struct LibraryLoadResult: Sendable {
    public var library: Library
    public var issues: [LibraryLoadIssue]
}

/// The library folder on disk (`spec.md` §11.1):
///
/// ```
/// library.json              palette order, pick target, format version
/// history.json              Color History
/// settings.json             synced settings
/// palettes/<uuid>.colorsip  one file per palette
/// ```
///
/// Every write is atomic. Files the store couldn't load (corrupt or from a newer version) are never
/// overwritten or deleted.
public struct LibraryStore: Sendable {
    public static let formatVersion = 1

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// `~/Library/Application Support/Colorsip/Library/`
    public static var defaultFolder: URL {
        URL.applicationSupportDirectory.appending(path: "Colorsip/Library", directoryHint: .isDirectory)
    }

    private var indexURL: URL { folder.appending(path: "library.json") }
    private var palettesFolder: URL { folder.appending(path: "palettes", directoryHint: .isDirectory) }

    private func paletteURL(_ id: Palette.ID) -> URL {
        palettesFolder.appending(path: "\(id.uuidString).colorsip")
    }

    // MARK: - Library

    /// Loads the library. A missing folder gives an empty library. Palettes missing from
    /// `library.json` are added at the end, oldest first; ids in it without a file are dropped.
    public func load() -> LibraryLoadResult {
        var issues: [LibraryLoadIssue] = []
        var index: LibraryIndex?
        if let data = try? Data(contentsOf: indexURL) {
            switch Self.decodeIndex(data) {
            case .success(let decoded): index = decoded
            case .failure(.newerFormat(let version)): issues.append(.newerFormat(file: "library.json", version: version))
            case .failure: issues.append(.unreadable(file: "library.json"))
            }
        }

        var palettes: [Palette.ID: Palette] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: palettesFolder, includingPropertiesForKeys: nil)) ?? []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where Self.isPaletteFile(url) {
            let file = "palettes/\(url.lastPathComponent)"
            do {
                let palette = try ColorsipPaletteFormat.decode(Data(contentsOf: url))
                if palettes[palette.id] == nil { palettes[palette.id] = palette }
            } catch ColorsipFormatError.newerFormat(let version) {
                issues.append(.newerFormat(file: file, version: version))
            } catch {
                issues.append(.unreadable(file: file))
            }
        }

        var ordered: [Palette] = []
        for id in index?.paletteOrder ?? [] {
            if let palette = palettes.removeValue(forKey: id) { ordered.append(palette) }
        }
        ordered += palettes.values.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
        return LibraryLoadResult(library: Library(palettes: ordered, pickTarget: index?.pickTarget), issues: issues)
    }

    /// Saves `library`, writing only what differs from `previous` (pass `nil` to write everything):
    /// changed palettes, `library.json` if the order or pick target changed, and deleting the files
    /// of palettes that were removed.
    public func save(_ library: Library, previous: Library?) throws {
        try FileManager.default.createDirectory(at: palettesFolder, withIntermediateDirectories: true)
        let old = Dictionary(uniqueKeysWithValues: (previous?.palettes ?? []).map { ($0.id, $0) })
        for palette in library.palettes where old[palette.id] != palette {
            try ColorsipPaletteFormat.encode(palette).write(to: paletteURL(palette.id), options: .atomic)
        }
        for id in old.keys where library.palette(id) == nil {
            let url = paletteURL(id)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        let indexChanged = previous.map {
            $0.palettes.map(\.id) != library.palettes.map(\.id) || $0.pickTarget != library.pickTarget
        } ?? true
        if indexChanged && !indexIsNewer() {
            let index = LibraryIndex(
                formatVersion: Self.formatVersion, paletteOrder: library.palettes.map(\.id),
                pickTarget: library.pickTarget)
            try JSONEncoder.library.encode(index).write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Other files

    /// Decodes `file`, or returns `nil` if it doesn't exist.
    public func load<T: Decodable>(_ type: T.Type, from file: LibraryFile) throws -> T? {
        let url = folder.appending(path: file.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try JSONDecoder.library.decode(type, from: Data(contentsOf: url))
    }

    /// Writes `value` to `file` atomically.
    public func save<T: Encodable>(_ value: T, to file: LibraryFile) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder.library.encode(value).write(to: folder.appending(path: file.rawValue), options: .atomic)
    }

    // MARK: - Helpers

    private struct LibraryIndex: Codable {
        var formatVersion: Int
        var paletteOrder: [UUID]
        var pickTarget: UUID?
    }

    private struct VersionProbe: Decodable {
        var formatVersion: Int
    }

    private static func decodeIndex(_ data: Data) -> Result<LibraryIndex, ColorsipFormatError> {
        let decoder = JSONDecoder.library
        if let probe = try? decoder.decode(VersionProbe.self, from: data), probe.formatVersion > formatVersion {
            return .failure(.newerFormat(probe.formatVersion))
        }
        do {
            return .success(try decoder.decode(LibraryIndex.self, from: data))
        } catch {
            return .failure(.invalid(String(describing: error)))
        }
    }

    /// Whether `library.json` was written by a newer Colorsip, so it must be left alone.
    private func indexIsNewer() -> Bool {
        guard let data = try? Data(contentsOf: indexURL),
            case .failure(.newerFormat) = Self.decodeIndex(data)
        else { return false }
        return true
    }

    /// `<uuid>.colorsip`. Other files, such as sync conflict copies, are ignored.
    private static func isPaletteFile(_ url: URL) -> Bool {
        url.pathExtension == "colorsip" && UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil
    }
}
