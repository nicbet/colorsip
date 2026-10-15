/// Where a row dragged up or down a vertical list lands. Slots are the gaps between rows: slot 0 is
/// above the first row and slot `count` below the last.
public enum ListReorder {
    /// A move that changes the order: insert the dragged row before `before`, or at the end (`nil`).
    public struct Move<ID: Equatable>: Equatable {
        public var before: ID?

        public init(before: ID?) {
            self.before = before
        }
    }

    /// The slot for a pointer at `y`: the number of rows, in list order, whose midpoint is above it.
    public static func insertionIndex(at y: Double, midpoints: [Double]) -> Int {
        midpoints.prefix { $0 < y }.count
    }

    /// Whether dropping the row at index `moving` into `slot` leaves the order as it is: its own
    /// slot or the one right after it.
    public static func isNoOp(moving: Int, to slot: Int) -> Bool {
        slot == moving || slot == moving + 1
    }

    /// The move that drops `moving` into `slot` of `ids`, or `nil` if it changes nothing or `moving`
    /// isn't in the list.
    public static func move<ID: Equatable>(_ moving: ID, to slot: Int, in ids: [ID]) -> Move<ID>? {
        guard let index = ids.firstIndex(of: moving), !isNoOp(moving: index, to: slot) else { return nil }
        return Move(before: ids.indices.contains(slot) ? ids[slot] : nil)
    }
}
