import Foundation

public enum ColorsipFormatError: Error, Hashable, Sendable {
    /// The file was written by a newer Colorsip. It must not be changed or overwritten.
    case newerFormat(Int)
    /// The file isn't a valid `.colorsip` palette.
    case invalid(String)
}

/// The `.colorsip` palette file (`spec.md` §11.2): W3C Design Tokens (DTCG) JSON, validated by
/// `schema/colorsip-palette.schema.json`.
///
/// Ungrouped swatches are top-level color tokens and groups are top-level DTCG groups. Keys are
/// derived from the names; the real names, ids, timestamps, icon, lock and the order of the keys
/// sit under `$extensions["app.colorsip"]`, together with the `formatVersion`.
public enum ColorsipPaletteFormat {
    public static let formatVersion = 1
    public static let extensionKey = "app.colorsip"

    /// The palette as pretty-printed JSON with sorted keys, so the same palette always gives the
    /// same bytes.
    public static func encode(_ palette: Palette) -> Data {
        do {
            return try JSONEncoder.library.encode(PaletteDocument(palette: palette))
        } catch {
            preconditionFailure("encoding a palette can't fail: \(error)")
        }
    }

    public static func decode(_ data: Data) throws(ColorsipFormatError) -> Palette {
        let decoder = JSONDecoder.library
        // Check the version before anything else: a newer file may have a different shape.
        if let probe = try? decoder.decode(VersionProbe.self, from: data),
            probe.extensions.meta.formatVersion > formatVersion
        {
            throw .newerFormat(probe.extensions.meta.formatVersion)
        }
        do {
            return try decoder.decode(PaletteDocument.self, from: data).palette
        } catch {
            throw .invalid(String(describing: error))
        }
    }
}

// MARK: - Documents

private struct PaletteMeta: Codable {
    var formatVersion: Int
    var id: UUID
    var name: String
    var icon: PaletteIcon?
    var locked: Bool
    var createdAt: Date
    var modifiedAt: Date
    var order: [String]
}

private struct GroupMeta: Codable {
    var id: UUID
    var name: String
    var order: [String]
}

private struct SwatchMeta: Codable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
}

/// `$extensions` with Colorsip's entry.
private struct Extensions<Meta: Codable>: Codable {
    var meta: Meta

    enum CodingKeys: String, CodingKey {
        case meta = "app.colorsip"
    }
}

private struct VersionProbe: Decodable {
    struct Meta: Codable { var formatVersion: Int }
    var extensions: Extensions<Meta>

    enum CodingKeys: String, CodingKey {
        case extensions = "$extensions"
    }
}

/// A DTCG key: any string.
private struct Key: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { nil }

    static let description = Key("$description")
    static let extensions = Key("$extensions")
    static let value = Key("$value")
}

private struct PaletteDocument: Codable {
    var palette: Palette

    init(palette: Palette) { self.palette = palette }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        var keys = KeyAllocator()
        let swatchKeys = palette.ungrouped.map { keys.next(for: $0.name, fallback: "Color") }
        let groupKeys = palette.groups.map { keys.next(for: $0.name, fallback: "Group") }
        try container.encodeIfPresent(palette.description, forKey: .description)
        let meta = PaletteMeta(
            formatVersion: ColorsipPaletteFormat.formatVersion, id: palette.id, name: palette.name,
            icon: palette.icon, locked: palette.isLocked, createdAt: palette.createdAt,
            modifiedAt: palette.modifiedAt, order: swatchKeys + groupKeys)
        try container.encode(Extensions(meta: meta), forKey: .extensions)
        for (key, swatch) in zip(swatchKeys, palette.ungrouped) {
            try container.encode(SwatchToken(swatch: swatch), forKey: Key(key))
        }
        for (key, group) in zip(groupKeys, palette.groups) {
            try container.encode(GroupDocument(group: group), forKey: Key(key))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let meta = try container.decode(Extensions<PaletteMeta>.self, forKey: .extensions).meta
        var ungrouped: [Swatch] = []
        var groups: [SwatchGroup] = []
        for key in orderedKeys(container, order: meta.order) {
            let entry = try container.nestedContainer(keyedBy: Key.self, forKey: key)
            if entry.contains(.value) {
                ungrouped.append(try container.decode(SwatchToken.self, forKey: key).swatch)
            } else {
                groups.append(try container.decode(GroupDocument.self, forKey: key).group)
            }
        }
        palette = Palette(
            id: meta.id, name: meta.name,
            description: try container.decodeIfPresent(String.self, forKey: .description),
            icon: meta.icon, isLocked: meta.locked, createdAt: meta.createdAt, modifiedAt: meta.modifiedAt,
            ungrouped: ungrouped, groups: groups)
    }
}

private struct GroupDocument: Codable {
    var group: SwatchGroup

    init(group: SwatchGroup) { self.group = group }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        var keys = KeyAllocator()
        let swatchKeys = group.swatches.map { keys.next(for: $0.name, fallback: "Color") }
        let meta = GroupMeta(id: group.id, name: group.name, order: swatchKeys)
        try container.encode(Extensions(meta: meta), forKey: .extensions)
        for (key, swatch) in zip(swatchKeys, group.swatches) {
            try container.encode(SwatchToken(swatch: swatch), forKey: Key(key))
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        let meta = try container.decode(Extensions<GroupMeta>.self, forKey: .extensions).meta
        // Groups don't nest: everything in a group is a color token.
        let swatches = try orderedKeys(container, order: meta.order).map {
            try container.decode(SwatchToken.self, forKey: $0).swatch
        }
        group = SwatchGroup(id: meta.id, name: meta.name, swatches: swatches)
    }
}

private struct SwatchToken: Codable {
    var swatch: Swatch

    init(swatch: Swatch) { self.swatch = swatch }

    enum CodingKeys: String, CodingKey {
        case type = "$type"
        case value = "$value"
        case description = "$description"
        case extensions = "$extensions"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("color", forKey: .type)
        try container.encode(swatch.color, forKey: .value)
        try container.encodeIfPresent(swatch.description, forKey: .description)
        let meta = SwatchMeta(
            id: swatch.id, name: swatch.name, createdAt: swatch.createdAt, modifiedAt: swatch.modifiedAt)
        try container.encode(Extensions(meta: meta), forKey: .extensions)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "color" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "unsupported token type \(type)")
        }
        let meta = try container.decode(Extensions<SwatchMeta>.self, forKey: .extensions).meta
        swatch = Swatch(
            id: meta.id, color: try container.decode(CSipColor.self, forKey: .value), name: meta.name,
            description: try container.decodeIfPresent(String.self, forKey: .description),
            createdAt: meta.createdAt, modifiedAt: meta.modifiedAt)
    }
}

/// The token and group keys of `container` (keys not starting with `$`): first those listed in
/// `order`, then any others in sorted order.
private func orderedKeys(_ container: KeyedDecodingContainer<Key>, order: [String]) -> [Key] {
    let present = Set(container.allKeys.map(\.stringValue).filter { !$0.hasPrefix("$") })
    let listed = order.filter(present.contains)
    let rest = present.subtracting(listed).sorted()
    return (listed + rest).map(Key.init)
}

/// Turns names into unique DTCG keys: `{`, `}` and `.` become `_`, leading `$` are dropped, and
/// repeated keys get " 2", " 3", ….
struct KeyAllocator {
    private var used: Set<String> = []

    mutating func next(for name: String, fallback: String) -> String {
        var base = String(name.drop { $0 == "$" })
        base = String(base.map { "{}.".contains($0) ? "_" : $0 })
        if base.isEmpty { base = fallback }
        var key = base
        var n = 2
        while used.contains(key) {
            key = "\(base) \(n)"
            n += 1
        }
        used.insert(key)
        return key
    }
}

// MARK: - Shared coding

extension PaletteIcon: Codable {
    private enum CodingKeys: String, CodingKey {
        case emoji, symbol
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let emoji = try container.decodeIfPresent(String.self, forKey: .emoji) {
            self = .emoji(emoji)
        } else {
            self = .symbol(try container.decode(String.self, forKey: .symbol))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .emoji(let emoji): try container.encode(emoji, forKey: .emoji)
        case .symbol(let symbol): try container.encode(symbol, forKey: .symbol)
        }
    }
}

/// The DTCG color value (`spec.md` §5.1). `hex` is written as an informative fallback and ignored
/// when reading; a missing `alpha` means opaque.
extension CSipColor: Codable {
    private enum CodingKeys: String, CodingKey {
        case colorSpace, components, alpha, hex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let space = try container.decode(ColorSpace.self, forKey: .colorSpace)
        let c = try container.decode([Double].self, forKey: .components)
        guard c.count == 3 else {
            throw DecodingError.dataCorruptedError(
                forKey: .components, in: container, debugDescription: "expected 3 components, got \(c.count)")
        }
        let alpha = try container.decodeIfPresent(Double.self, forKey: .alpha) ?? 1
        self.init(space, c[0], c[1], c[2], alpha: alpha)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(colorSpace, forKey: .colorSpace)
        try container.encode(components, forKey: .components)
        try container.encode(alpha, forKey: .alpha)
        try container.encode(hex, forKey: .hex)
    }
}

extension JSONEncoder {
    /// The encoder for library files: deterministic output and ISO 8601 timestamps with milliseconds.
    static var library: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(libraryTimestampStyle))
        }
        return encoder
    }
}

extension JSONDecoder {
    static var library: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = try? libraryTimestampStyle.parse(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid timestamp \(string)")
            }
            return date.libraryTimestamp
        }
        return decoder
    }
}

/// `2026-10-14T10:00:00.000Z`
private let libraryTimestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
