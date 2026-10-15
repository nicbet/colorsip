import Foundation

/// The library changes the popover offers (`spec.md` §3.1, §7.1, §7.2), each one named undoable
/// step. The UI hides what isn't allowed, so a command that fails (a locked palette, an id that's
/// gone) changes nothing and records no undo step instead of throwing.
///
/// Names are trimmed, and an empty name is ignored. A trimmed empty description clears it.
extension LibraryController {
    // MARK: - Palettes

    /// Inserts an empty palette named "New Palette" (numbered if the name is taken) at the top.
    @discardableResult
    public func newPalette(at date: Date = .now) -> Palette.ID {
        perform("New Palette") { library in
            let name = Library.uniqueName("New Palette", among: library.palettes.map(\.name))
            let first = library.palettes.first?.id
            let id = library.createPalette(name: name, at: date)
            library.movePalette(id, before: first)
            return id
        }
    }

    @discardableResult
    public func renamePalette(_ id: Palette.ID, to name: String, at date: Date = .now) -> Bool {
        guard let name = name.trimmedNonEmpty else { return false }
        return attempt("Rename Palette") { library throws(LibraryError) in try library.renamePalette(id, to: name, at: date) }
    }

    @discardableResult
    public func setDescription(_ description: String?, of id: Palette.ID, at date: Date = .now) -> Bool {
        let description = description?.trimmedNonEmpty
        return attempt("Edit Description") { library throws(LibraryError) in
            try library.setDescription(description, of: id, at: date)
        }
    }

    @discardableResult
    public func setIcon(_ icon: PaletteIcon?, of id: Palette.ID, at date: Date = .now) -> Bool {
        attempt("Set Icon") { library throws(LibraryError) in try library.setIcon(icon, of: id, at: date) }
    }

    @discardableResult
    public func setLocked(_ locked: Bool, palette id: Palette.ID, at date: Date = .now) -> Bool {
        attempt(locked ? "Lock Palette" : "Unlock Palette") { library throws(LibraryError) in
            try library.setLocked(locked, palette: id, at: date)
        }
    }

    @discardableResult
    public func duplicatePalette(_ id: Palette.ID, at date: Date = .now) -> Palette.ID? {
        try? perform("Duplicate Palette") { library throws(LibraryError) in try library.duplicatePalette(id, at: date) }
    }

    @discardableResult
    public func deletePalette(_ id: Palette.ID) -> Bool {
        attempt("Delete Palette") { library throws(LibraryError) in try library.deletePalette(id) }
    }

    /// Moves a palette right before `target`, or to the end with `nil`.
    @discardableResult
    public func movePalette(_ id: Palette.ID, before target: Palette.ID?) -> Bool {
        attempt("Move Palette") { $0.movePalette(id, before: target) }
    }

    /// Makes the palette the pick target; if it already is, nothing changes.
    @discardableResult
    public func selectPickTarget(_ id: Palette.ID) -> Bool {
        attempt("Set Pick Target") { library throws(LibraryError) in try library.setPickTarget(id) }
    }

    /// Makes the palette the pick target, or clears the target if it already is.
    @discardableResult
    public func togglePickTarget(_ id: Palette.ID) -> Bool {
        attempt("Set Pick Target") { library throws(LibraryError) in
            try library.setPickTarget(library.pickTarget == id ? nil : id)
        }
    }

    // MARK: - Groups

    /// Appends an empty group named "New Group" (numbered if the palette has one).
    @discardableResult
    public func newGroup(in palette: Palette.ID, at date: Date = .now) -> SwatchGroup.ID? {
        try? perform("New Group") { library throws(LibraryError) in
            let names = library.palette(palette)?.groups.map(\.name) ?? []
            return try library.addGroup(name: Library.uniqueName("New Group", among: names), to: palette, at: date)
        }
    }

    @discardableResult
    public func renameGroup(_ group: SwatchGroup.ID, in palette: Palette.ID, to name: String, at date: Date = .now) -> Bool {
        guard let name = name.trimmedNonEmpty else { return false }
        return attempt("Rename Group") { library throws(LibraryError) in
            try library.renameGroup(group, in: palette, to: name, at: date)
        }
    }

    /// Moves a group `offset` places: −1 is left, +1 is right. A move past either end does nothing.
    @discardableResult
    public func moveGroup(_ group: SwatchGroup.ID, in palette: Palette.ID, by offset: Int, at date: Date = .now) -> Bool {
        guard let groups = library.palette(palette)?.groups,
              let index = groups.firstIndex(where: { $0.id == group }),
              groups.indices.contains(index + offset)
        else { return false }
        return attempt("Move Group") { library throws(LibraryError) in
            try library.moveGroup(group, in: palette, to: index + offset, at: date)
        }
    }

    /// Deletes a group. With `keepSwatches`, its swatches move to the ungrouped section.
    @discardableResult
    public func deleteGroup(_ group: SwatchGroup.ID, in palette: Palette.ID, keepSwatches: Bool, at date: Date = .now) -> Bool {
        attempt("Delete Group") { library throws(LibraryError) in
            try library.deleteGroup(group, in: palette, keepSwatches: keepSwatches, at: date)
        }
    }

    // MARK: - Swatches

    @discardableResult
    public func renameSwatch(_ id: Swatch.ID, in section: SectionID, to name: String, at date: Date = .now) -> Bool {
        guard let name = name.trimmedNonEmpty else { return false }
        return attempt("Rename Swatch") { library throws(LibraryError) in
            try library.renameSwatch(id, in: section, to: name, at: date)
        }
    }

    @discardableResult
    public func deleteSwatch(_ id: Swatch.ID, in section: SectionID, at date: Date = .now) -> Bool {
        attempt("Delete Swatch") { library throws(LibraryError) in try library.deleteSwatch(id, in: section, at: date) }
    }

    // MARK: - Helpers

    /// Applies `change` as one undoable step and returns whether the library changed.
    private func attempt(_ actionName: String, _ change: (inout Library) throws(LibraryError) -> Void) -> Bool {
        let before = library
        do { try perform(actionName, change) } catch { return false }
        return library != before
    }
}

extension String {
    /// The string without surrounding whitespace, or `nil` if nothing is left.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
