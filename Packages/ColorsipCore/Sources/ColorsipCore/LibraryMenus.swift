/// The items of a palette's context menu (`spec.md` §3.1), in order.
public enum PaletteMenuItem: Hashable, Sendable {
    case rename, editDescription, setIcon, lock, unlock, newGroup, groups, duplicate, delete

    /// A locked palette only offers Unlock. Groups ▸ is left out when there are no groups.
    public static func items(for palette: Palette) -> [PaletteMenuItem] {
        guard !palette.isLocked else { return [.unlock] }
        return [.rename, .editDescription, .setIcon, .lock, .newGroup]
            + (palette.groups.isEmpty ? [] : [.groups])
            + [.duplicate, .delete]
    }
}

/// The items of a group's submenu (`spec.md` §7.2), in order.
public enum GroupMenuItem: Hashable, Sendable {
    case rename, moveLeft, moveRight, delete

    /// Moves past either end are left out. A locked palette or a missing group has no items.
    public static func items(for group: SwatchGroup.ID, in palette: Palette) -> [GroupMenuItem] {
        guard !palette.isLocked, let index = palette.groups.firstIndex(where: { $0.id == group }) else { return [] }
        return [.rename]
            + (index > 0 ? [.moveLeft] : [])
            + (index < palette.groups.count - 1 ? [.moveRight] : [])
            + [.delete]
    }
}

/// The items of a swatch's context menu (`spec.md` §3.1), in order. Edit… arrives with the color
/// editor (cs-722793).
public enum SwatchMenuItem: Hashable, Sendable {
    case copyAs, rename, delete
    /// The submenu of the swatch's group.
    case group

    /// The items for a swatch in `group` (`nil` for the ungrouped section) of `palette`. Color
    /// History passes `nil` for the palette. Only Copy as is offered there and in locked palettes.
    public static func items(in group: SwatchGroup.ID?, of palette: Palette?) -> [SwatchMenuItem] {
        guard let palette, !palette.isLocked else { return [.copyAs] }
        return [.copyAs, .rename, .delete] + (group == nil ? [] : [.group])
    }
}

extension Palette {
    /// Deleting asks first when the palette holds any colors.
    public var deletionNeedsConfirmation: Bool { !allSwatches.isEmpty }
}

extension SwatchGroup {
    /// Deleting asks whether to delete the colors or move them to the ungrouped section, unless the
    /// group is empty.
    public var deletionNeedsChoice: Bool { !swatches.isEmpty }
}
