import Foundation

/// The swatch being dragged in the popover (`spec.md` §7.5).
public enum SwatchDragSource: Hashable, Sendable {
    /// A Color History swatch. History isn't part of the library, so the swatch itself is carried.
    case history(Swatch)
    case palette(Swatch.ID, in: SectionID)
}

/// What a drop does with the dragged swatch.
public enum SwatchDropOperation: Hashable, Sendable {
    case move, copy
}

/// What a drop did.
public enum SwatchDropResult: Hashable, Sendable {
    case moved(Swatch.ID)
    case copied(Swatch.ID)
    /// The swatch was dropped into its own place.
    case unchanged
    /// The destination section already has the color; the UI highlights `existing` (`spec.md` §7.2).
    case duplicate(existing: Swatch.ID)
    /// A locked destination, or a palette, group or swatch that no longer exists.
    case refused
}

/// The rules of dragging swatches (`spec.md` §7.5).
public enum SwatchDrag {
    /// What dropping `source` onto `destination` does, or `nil` if the drop is refused. A plain drag
    /// moves; Option, Color History and locked palettes copy, since a locked palette can't lose
    /// swatches. Locked or missing destinations, and swatches that no longer exist, are refused.
    public static func operation(
        for source: SwatchDragSource, onto destination: Palette.ID, in library: Library, option: Bool
    ) -> SwatchDropOperation? {
        guard let target = library.palette(destination), !target.isLocked else { return nil }
        switch source {
        case .history:
            return .copy
        case .palette(let id, let section):
            guard let palette = library.palette(section.palette),
                  palette.swatches(in: section.group)?.contains(where: { $0.id == id }) == true
            else { return nil }
            return option || palette.isLocked ? .copy : .move
        }
    }

    /// Whether dropping `source` into `slot` of `destination` would leave it where it is: a move
    /// into its own place in its own section. The popover shows no insertion line for it.
    public static func isUnchanged(
        _ source: SwatchDragSource, onto destination: SectionID, at slot: Int, in library: Library, option: Bool
    ) -> Bool {
        guard case .palette(let id, let section) = source, section == destination,
              operation(for: source, onto: destination.palette, in: library, option: option) == .move,
              let current = library.palette(section.palette)?.swatches(in: section.group)?.firstIndex(where: { $0.id == id })
        else { return false }
        return ListReorder.isNoOp(moving: current, to: slot)
    }

    /// The text a drag gives other apps: the value in the active format.
    public static func payload(for color: CSipColor, format: OutputFormat) -> String {
        format.string(for: color)
    }
}

extension LibraryController {
    /// Drops `source` into `slot` of `destination`, as one undoable step ("Move Swatch" or "Copy
    /// Swatch"). `slot` counts the destination's swatches before the dragged one is taken out.
    /// Drops that change nothing record no undo step.
    @discardableResult
    public func dropSwatch(
        _ source: SwatchDragSource, onto destination: SectionID, at slot: Int, option: Bool, at date: Date = .now
    ) -> SwatchDropResult {
        guard let operation = SwatchDrag.operation(for: source, onto: destination.palette, in: library, option: option)
        else { return .refused }
        do throws(LibraryError) {
            switch (source, operation) {
            case (.history(let swatch), _):
                return .copied(try perform("Copy Swatch") { library throws(LibraryError) in
                    try library.insertSwatch(
                        color: swatch.color, name: swatch.name, description: swatch.description,
                        into: destination, index: slot, at: date)
                })
            case (.palette(let id, let section), .copy):
                return .copied(try perform("Copy Swatch") { library throws(LibraryError) in
                    try library.copySwatch(id, from: section, to: destination, index: slot, at: date)
                })
            case (.palette(let id, let section), .move):
                if SwatchDrag.isUnchanged(source, onto: destination, at: slot, in: library, option: option) {
                    return .unchanged
                }
                // Within a section, the swatch is taken out first, so later slots shift down by one.
                var index = slot
                if section == destination,
                   let current = library.palette(section.palette)?.swatches(in: section.group)?.firstIndex(where: { $0.id == id }),
                   slot > current {
                    index -= 1
                }
                try perform("Move Swatch") { library throws(LibraryError) in
                    try library.moveSwatch(id, from: section, to: destination, index: index, at: date)
                }
                return .moved(id)
            }
        } catch .duplicate(let existing) {
            return .duplicate(existing: existing)
        } catch {
            return .refused
        }
    }
}

/// A place in a palette's strip a swatch can be dropped: before the swatch at `index` of a section.
public struct StripSlot: Hashable, Sendable {
    /// `nil` for the ungrouped section.
    public var group: SwatchGroup.ID?
    public var index: Int

    public init(group: SwatchGroup.ID?, index: Int) {
        self.group = group
        self.index = index
    }
}

extension SwatchStripLayout {
    /// The slot for a drop at `x`, in content coordinates. Each section owns the strip up to the
    /// middle of the gaps around it, and the slot is the nearest boundary between its swatches.
    public func dropSlot(at x: Double) -> StripSlot {
        guard let section = sections.last(where: { $0.x - Self.groupGap / 2 <= x }) ?? sections.first
        else { return StripSlot(group: nil, index: 0) }
        let boundary = segmentWidth > 0 ? ((x - section.x) / segmentWidth).rounded() : 0
        let index = Int(min(max(boundary, 0), Double(section.swatches.count)))
        return StripSlot(group: section.group, index: index)
    }

    /// Where to draw the insertion line for `slot`: on the boundary between swatches, or in the
    /// middle of the gap at the edge of a section next to another one. `nil` if the section isn't
    /// in the strip.
    public func insertionX(for slot: StripSlot) -> Double? {
        guard let i = sections.firstIndex(where: { $0.group == slot.group }) else { return nil }
        let section = sections[i]
        if slot.index <= 0 && i > 0 { return section.x - Self.groupGap / 2 }
        if slot.index >= section.swatches.count && i < sections.count - 1 {
            return section.x + section.width + Self.groupGap / 2
        }
        return section.swatchX(min(max(slot.index, 0), section.swatches.count))
    }
}
