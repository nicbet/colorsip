import Foundation

/// A color in a palette section (`spec.md` §5.2).
public struct Swatch: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public var color: CSipColor
    public var name: String
    public var description: String?
    public var createdAt: Date
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(), color: CSipColor, name: String, description: String? = nil,
        createdAt: Date, modifiedAt: Date? = nil
    ) {
        self.id = id
        self.color = color
        self.name = name
        self.description = description
        self.createdAt = createdAt.libraryTimestamp
        self.modifiedAt = (modifiedAt ?? createdAt).libraryTimestamp
    }
}

/// A named group of swatches in a palette. Groups don't nest (`spec.md` §7.2).
public struct SwatchGroup: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var swatches: [Swatch]

    public init(id: UUID = UUID(), name: String, swatches: [Swatch] = []) {
        self.id = id
        self.name = name
        self.swatches = swatches
    }
}

/// A palette's icon: an emoji or an SF Symbol name.
public enum PaletteIcon: Hashable, Sendable {
    case emoji(String)
    case symbol(String)
}

/// A palette (`spec.md` §7.1): an ungrouped section, shown first, followed by its groups.
public struct Palette: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var description: String?
    public var icon: PaletteIcon?
    public var isLocked: Bool
    public var createdAt: Date
    public var modifiedAt: Date
    public var ungrouped: [Swatch]
    public var groups: [SwatchGroup]

    public init(
        id: UUID = UUID(), name: String, description: String? = nil, icon: PaletteIcon? = nil,
        isLocked: Bool = false, createdAt: Date, modifiedAt: Date? = nil,
        ungrouped: [Swatch] = [], groups: [SwatchGroup] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.icon = icon
        self.isLocked = isLocked
        self.createdAt = createdAt.libraryTimestamp
        self.modifiedAt = (modifiedAt ?? createdAt).libraryTimestamp
        self.ungrouped = ungrouped
        self.groups = groups
    }

    /// An empty, unlocked palette created at `date`.
    public init(name: String, at date: Date) {
        self.init(name: name, createdAt: date)
    }

    /// Every swatch, section by section.
    public var allSwatches: [Swatch] { ungrouped + groups.flatMap(\.swatches) }

    /// The swatches of the ungrouped section (`nil`) or of a group, or `nil` if there is no such group.
    public func swatches(in group: SwatchGroup.ID?) -> [Swatch]? {
        guard let group else { return ungrouped }
        return groups.first { $0.id == group }?.swatches
    }
}

/// A section of a palette: its ungrouped section or one of its groups.
public struct SectionID: Hashable, Sendable {
    public var palette: Palette.ID
    /// `nil` for the ungrouped section.
    public var group: SwatchGroup.ID?

    public init(palette: Palette.ID, group: SwatchGroup.ID?) {
        self.palette = palette
        self.group = group
    }

    public static func ungrouped(_ palette: Palette.ID) -> SectionID {
        SectionID(palette: palette, group: nil)
    }

    public static func group(_ group: SwatchGroup.ID, in palette: Palette.ID) -> SectionID {
        SectionID(palette: palette, group: group)
    }
}

public enum LibraryError: Error, Hashable, Sendable {
    /// The palette is locked and can't be changed (`spec.md` §7.1).
    case locked(Palette.ID)
    /// The section already holds a perceptually equal swatch (`spec.md` §7.2).
    case duplicate(existing: Swatch.ID)
    /// No palette, group or swatch with that id.
    case notFound
}

/// The palettes and the pick target (`spec.md` §7). Every change goes through a method that applies
/// the rules: swatches are unique within a section, locked palettes can't be changed, and at most
/// one unlocked palette is the pick target. A method that throws leaves the library unchanged.
///
/// Methods take the time of the change (`at`), so tests can control timestamps. Timestamps are kept
/// to the millisecond, the precision of the files.
public struct Library: Hashable, Sendable {
    public private(set) var palettes: [Palette]
    /// The palette new picks go into (the radio button), never a locked one.
    public private(set) var pickTarget: Palette.ID?

    /// A library with `palettes`. A `pickTarget` that is missing or locked is dropped.
    public init(palettes: [Palette] = [], pickTarget: Palette.ID? = nil) {
        self.palettes = palettes
        self.pickTarget = palettes.first { $0.id == pickTarget && !$0.isLocked }?.id
    }

    public func palette(_ id: Palette.ID) -> Palette? {
        palettes.first { $0.id == id }
    }

    // MARK: - Palettes

    /// Appends an empty palette and returns its id.
    @discardableResult
    public mutating func createPalette(name: String, at date: Date = .now) -> Palette.ID {
        let palette = Palette(name: name, at: date)
        palettes.append(palette)
        return palette.id
    }

    public mutating func renamePalette(_ id: Palette.ID, to name: String, at date: Date = .now) throws(LibraryError) {
        try editPalette(id, at: date) { $0.name = name }
    }

    public mutating func setDescription(_ description: String?, of id: Palette.ID, at date: Date = .now) throws(LibraryError) {
        try editPalette(id, at: date) { $0.description = description }
    }

    public mutating func setIcon(_ icon: PaletteIcon?, of id: Palette.ID, at date: Date = .now) throws(LibraryError) {
        try editPalette(id, at: date) { $0.icon = icon }
    }

    /// Locks or unlocks a palette. Locking the pick target clears the pick target.
    public mutating func setLocked(_ locked: Bool, palette id: Palette.ID, at date: Date = .now) throws(LibraryError) {
        let i = try index(of: id)
        guard palettes[i].isLocked != locked else { return }
        palettes[i].isLocked = locked
        palettes[i].modifiedAt = date.libraryTimestamp
        if locked && pickTarget == id { pickTarget = nil }
    }

    /// Inserts an unlocked copy, named "<name> copy", right after the palette, and returns its id.
    /// The copy, its groups and its swatches get new ids and timestamps. Allowed on locked palettes.
    @discardableResult
    public mutating func duplicatePalette(_ id: Palette.ID, at date: Date = .now) throws(LibraryError) -> Palette.ID {
        let i = try index(of: id)
        let original = palettes[i]
        func copy(_ swatch: Swatch) -> Swatch {
            Swatch(color: swatch.color, name: swatch.name, description: swatch.description, createdAt: date)
        }
        let duplicate = Palette(
            name: "\(original.name) copy", description: original.description, icon: original.icon,
            createdAt: date, ungrouped: original.ungrouped.map(copy),
            groups: original.groups.map { SwatchGroup(name: $0.name, swatches: $0.swatches.map(copy)) })
        palettes.insert(duplicate, at: i + 1)
        return duplicate.id
    }

    /// Deletes an unlocked palette. Deleting the pick target clears it.
    public mutating func deletePalette(_ id: Palette.ID) throws(LibraryError) {
        let i = try index(of: id)
        guard !palettes[i].isLocked else { throw .locked(id) }
        palettes.remove(at: i)
        if pickTarget == id { pickTarget = nil }
    }

    /// Moves the palettes at `source` so they end up before the palette at `destination` (as in
    /// SwiftUI's `onMove`). Locked palettes can move: their position isn't part of their content.
    public mutating func movePalettes(fromOffsets source: IndexSet, toOffset destination: Int) {
        let moving = source.map { palettes[$0] }
        for i in source.reversed() { palettes.remove(at: i) }
        let insertion = destination - source.count(in: 0..<destination)
        palettes.insert(contentsOf: moving, at: min(max(insertion, 0), palettes.count))
    }

    /// Moves a palette so it ends up right before `target`, or at the end with `nil`. Unknown ids
    /// change nothing.
    public mutating func movePalette(_ id: Palette.ID, before target: Palette.ID?) {
        guard let source = palettes.firstIndex(where: { $0.id == id }), id != target else { return }
        let destination: Int
        if let target {
            guard let i = palettes.firstIndex(where: { $0.id == target }) else { return }
            destination = i
        } else {
            destination = palettes.count
        }
        movePalettes(fromOffsets: [source], toOffset: destination)
    }

    /// `base`, or "base 2", "base 3", …: the first that isn't in `names`, compared case-insensitively.
    static func uniqueName(_ base: String, among names: some Sequence<String>) -> String {
        let taken = Set(names.map { $0.lowercased() })
        var candidate = base
        var n = 1
        while taken.contains(candidate.lowercased()) {
            n += 1
            candidate = "\(base) \(n)"
        }
        return candidate
    }

    /// Sets the pick target, or clears it with `nil`. A locked palette can't be the target.
    public mutating func setPickTarget(_ id: Palette.ID?) throws(LibraryError) {
        guard let id else { pickTarget = nil; return }
        let i = try index(of: id)
        guard !palettes[i].isLocked else { throw .locked(id) }
        pickTarget = id
    }

    // MARK: - Groups

    /// Adds a group at `index` (default: the end) and returns its id.
    @discardableResult
    public mutating func addGroup(
        name: String, to palette: Palette.ID, index: Int? = nil, at date: Date = .now
    ) throws(LibraryError) -> SwatchGroup.ID {
        try editPalette(palette, at: date) { p in
            let group = SwatchGroup(name: name)
            p.groups.insert(group, at: clamp(index ?? p.groups.count, p.groups))
            return group.id
        }
    }

    public mutating func renameGroup(
        _ group: SwatchGroup.ID, in palette: Palette.ID, to name: String, at date: Date = .now
    ) throws(LibraryError) {
        try editPalette(palette, at: date) { p throws(LibraryError) in
            p.groups[try p.groupIndex(group)].name = name
        }
    }

    /// Moves a group so that it ends up at `index`.
    public mutating func moveGroup(
        _ group: SwatchGroup.ID, in palette: Palette.ID, to index: Int, at date: Date = .now
    ) throws(LibraryError) {
        try editPalette(palette, at: date) { p throws(LibraryError) in
            let moved = p.groups.remove(at: try p.groupIndex(group))
            p.groups.insert(moved, at: clamp(index, p.groups))
        }
    }

    /// Deletes a group. With `keepSwatches`, its swatches are appended to the ungrouped section,
    /// except those that would duplicate an ungrouped swatch.
    public mutating func deleteGroup(
        _ group: SwatchGroup.ID, in palette: Palette.ID, keepSwatches: Bool, at date: Date = .now
    ) throws(LibraryError) {
        try editPalette(palette, at: date) { p throws(LibraryError) in
            let removed = p.groups.remove(at: try p.groupIndex(group))
            guard keepSwatches else { return }
            for swatch in removed.swatches where p.ungrouped.duplicate(of: swatch.color) == nil {
                p.ungrouped.append(swatch)
            }
        }
    }

    // MARK: - Swatches

    /// Inserts a new swatch at `index` (default: the front, where picks go) and returns its id.
    /// Throws `.duplicate` if the section already has a perceptually equal swatch.
    @discardableResult
    public mutating func insertSwatch(
        color: CSipColor, name: String, description: String? = nil, into section: SectionID,
        index: Int = 0, at date: Date = .now
    ) throws(LibraryError) -> Swatch.ID {
        let swatch = Swatch(color: color, name: name, description: description, createdAt: date)
        try editPalette(section.palette, at: date) { p throws(LibraryError) in
            try p.modifySection(section.group) { swatches throws(LibraryError) in
                try swatches.insertUnique(swatch, at: index)
            }
        }
        return swatch.id
    }

    public mutating func renameSwatch(
        _ id: Swatch.ID, in section: SectionID, to name: String, at date: Date = .now
    ) throws(LibraryError) {
        try editSwatch(id, in: section, at: date) { $0.name = name }
    }

    public mutating func setSwatchDescription(
        _ description: String?, of id: Swatch.ID, in section: SectionID, at date: Date = .now
    ) throws(LibraryError) {
        try editSwatch(id, in: section, at: date) { $0.description = description }
    }

    /// Changes a swatch's color. Throws `.duplicate` if another swatch in the section has that color.
    public mutating func setSwatchColor(
        _ color: CSipColor, of id: Swatch.ID, in section: SectionID, at date: Date = .now
    ) throws(LibraryError) {
        try editPalette(section.palette, at: date) { p throws(LibraryError) in
            try p.modifySection(section.group) { swatches throws(LibraryError) in
                let i = try swatches.index(of: id)
                if let existing = swatches.duplicate(of: color, excluding: id) {
                    throw .duplicate(existing: existing.id)
                }
                swatches[i].color = color
                swatches[i].modifiedAt = date.libraryTimestamp
            }
        }
    }

    public mutating func deleteSwatch(_ id: Swatch.ID, in section: SectionID, at date: Date = .now) throws(LibraryError) {
        try editPalette(section.palette, at: date) { p throws(LibraryError) in
            try p.modifySection(section.group) { swatches throws(LibraryError) in
                swatches.remove(at: try swatches.index(of: id))
            }
        }
    }

    /// Moves a swatch so it ends up at `index` in `destination`: a reorder within a section, or a
    /// move to another section or palette. The swatch keeps its id. Both palettes must be unlocked.
    public mutating func moveSwatch(
        _ id: Swatch.ID, from source: SectionID, to destination: SectionID, index: Int, at date: Date = .now
    ) throws(LibraryError) {
        if source.palette == destination.palette {
            try editPalette(source.palette, at: date) { p throws(LibraryError) in
                let swatch = try p.modifySection(source.group) { swatches throws(LibraryError) in
                    swatches.remove(at: try swatches.index(of: id))
                }
                try p.modifySection(destination.group) { swatches throws(LibraryError) in
                    try swatches.insertUnique(swatch, at: index)
                }
            }
            return
        }
        var library = self
        let swatch = try library.editPalette(source.palette, at: date) { p throws(LibraryError) in
            try p.modifySection(source.group) { swatches throws(LibraryError) in
                swatches.remove(at: try swatches.index(of: id))
            }
        }
        try library.editPalette(destination.palette, at: date) { p throws(LibraryError) in
            try p.modifySection(destination.group) { swatches throws(LibraryError) in
                try swatches.insertUnique(swatch, at: index)
            }
        }
        self = library
    }

    /// Copies a swatch to `index` in `destination` as a new swatch, and returns the copy's id. The
    /// source may be locked; the destination must not be.
    @discardableResult
    public mutating func copySwatch(
        _ id: Swatch.ID, from source: SectionID, to destination: SectionID, index: Int, at date: Date = .now
    ) throws(LibraryError) -> Swatch.ID {
        let sourcePalette = try palettes[self.index(of: source.palette)]
        guard let swatches = sourcePalette.swatches(in: source.group) else { throw .notFound }
        let original = swatches[try swatches.index(of: id)]
        return try insertSwatch(
            color: original.color, name: original.name, description: original.description,
            into: destination, index: index, at: date)
    }

    // MARK: - Helpers

    private func index(of id: Palette.ID) throws(LibraryError) -> Int {
        guard let i = palettes.firstIndex(where: { $0.id == id }) else { throw .notFound }
        return i
    }

    /// Applies `change` to a copy of an unlocked palette, stamps its `modifiedAt` and stores it.
    /// Nothing is stored if `change` throws or leaves the palette as it was.
    @discardableResult
    private mutating func editPalette<T>(
        _ id: Palette.ID, at date: Date, _ change: (inout Palette) throws(LibraryError) -> T
    ) throws(LibraryError) -> T {
        let i = try index(of: id)
        guard !palettes[i].isLocked else { throw .locked(id) }
        var palette = palettes[i]
        let result = try change(&palette)
        guard palette != palettes[i] else { return result }
        palette.modifiedAt = date.libraryTimestamp
        palettes[i] = palette
        return result
    }

    private mutating func editSwatch(
        _ id: Swatch.ID, in section: SectionID, at date: Date, _ change: (inout Swatch) -> Void
    ) throws(LibraryError) {
        try editPalette(section.palette, at: date) { p throws(LibraryError) in
            try p.modifySection(section.group) { swatches throws(LibraryError) in
                let i = try swatches.index(of: id)
                let original = swatches[i]
                change(&swatches[i])
                if swatches[i] != original { swatches[i].modifiedAt = date.libraryTimestamp }
            }
        }
    }
}

extension Palette {
    fileprivate func groupIndex(_ id: SwatchGroup.ID) throws(LibraryError) -> Int {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { throw .notFound }
        return i
    }

    /// Applies `change` to the ungrouped section (`nil`) or a group's swatches.
    fileprivate mutating func modifySection<T>(
        _ group: SwatchGroup.ID?, _ change: (inout [Swatch]) throws(LibraryError) -> T
    ) throws(LibraryError) -> T {
        guard let group else { return try change(&ungrouped) }
        return try change(&groups[try groupIndex(group)].swatches)
    }
}

extension [Swatch] {
    fileprivate func index(of id: Swatch.ID) throws(LibraryError) -> Int {
        guard let i = firstIndex(where: { $0.id == id }) else { throw .notFound }
        return i
    }

    /// The swatch that is perceptually equal to `color` (`spec.md` §5.1), other than `excluded`.
    func duplicate(of color: CSipColor, excluding excluded: Swatch.ID? = nil) -> Swatch? {
        first { $0.id != excluded && $0.color.isPerceptuallyEqual(to: color) }
    }

    fileprivate mutating func insertUnique(_ swatch: Swatch, at index: Int) throws(LibraryError) {
        if let existing = duplicate(of: swatch.color) { throw .duplicate(existing: existing.id) }
        insert(swatch, at: clamp(index, self))
    }
}

/// `index` clamped to the valid insertion positions of `collection`.
private func clamp<C: Collection>(_ index: Int, _ collection: C) -> Int {
    min(max(index, 0), collection.count)
}

extension Date {
    /// This date rounded to whole milliseconds, the precision of the library's timestamps.
    var libraryTimestamp: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}
