import Testing
@testable import ColorsipCore

@Suite("List reorder")
struct ListReorderTests {
    /// Three rows 40 pt tall, 14 pt apart, starting at y = 100.
    let midpoints = [120.0, 174.0, 228.0]

    @Test func insertionIndexCountsMidpointsAbove() {
        #expect(ListReorder.insertionIndex(at: 0, midpoints: midpoints) == 0)
        #expect(ListReorder.insertionIndex(at: 119, midpoints: midpoints) == 0)
        #expect(ListReorder.insertionIndex(at: 121, midpoints: midpoints) == 1)
        #expect(ListReorder.insertionIndex(at: 200, midpoints: midpoints) == 2)
        #expect(ListReorder.insertionIndex(at: 229, midpoints: midpoints) == 3)
        #expect(ListReorder.insertionIndex(at: 10_000, midpoints: midpoints) == 3)
        #expect(ListReorder.insertionIndex(at: 50, midpoints: []) == 0)
    }

    @Test func ownSlotAndTheNextAreNoOps() {
        #expect(ListReorder.isNoOp(moving: 1, to: 1))
        #expect(ListReorder.isNoOp(moving: 1, to: 2))
        #expect(!ListReorder.isNoOp(moving: 1, to: 0))
        #expect(!ListReorder.isNoOp(moving: 1, to: 3))
    }

    @Test func moveGivesTheIdToInsertBefore() {
        let ids = ["a", "b", "c"]
        #expect(ListReorder.move("c", to: 0, in: ids) == .init(before: "a"))
        #expect(ListReorder.move("a", to: 2, in: ids) == .init(before: "c"))
        #expect(ListReorder.move("a", to: 3, in: ids) == .init(before: nil))
        #expect(ListReorder.move("b", to: 1, in: ids) == nil)
        #expect(ListReorder.move("b", to: 2, in: ids) == nil)
        #expect(ListReorder.move("x", to: 0, in: ids) == nil)
    }
}
