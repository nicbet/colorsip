/// A ``Library`` with undo and redo (`spec.md` §7.6).
///
/// Each change made through ``perform(_:_:)`` keeps a snapshot of the library before the change.
/// The library is a value type, so a snapshot shares storage with the current state until one of
/// them changes. Color History isn't part of the library, so undoing a pick leaves it alone.
public struct UndoableLibrary: Sendable {
    public static let defaultLimit = 100

    private struct Step: Sendable {
        let actionName: String
        let library: Library
    }

    public private(set) var library: Library
    /// The number of undo levels kept; older ones are dropped.
    public let limit: Int
    private var undoStack: [Step] = []
    private var redoStack: [Step] = []

    public init(_ library: Library = Library(), limit: Int = defaultLimit) {
        self.library = library
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// The name of the change `undo()` reverts, such as "Rename Palette".
    public var undoActionName: String? { undoStack.last?.actionName }
    public var redoActionName: String? { redoStack.last?.actionName }

    /// Applies `change` as one undoable step named `actionName`. If `change` throws, the library is
    /// left unchanged and nothing is recorded. A change that leaves the library equal isn't recorded.
    @discardableResult
    public mutating func perform<T, E: Error>(
        _ actionName: String, _ change: (inout Library) throws(E) -> T
    ) throws(E) -> T {
        var draft = library
        let result = try change(&draft)
        guard draft != library else { return result }
        undoStack.append(Step(actionName: actionName, library: library))
        if undoStack.count > limit { undoStack.removeFirst(undoStack.count - limit) }
        redoStack.removeAll()
        library = draft
        return result
    }

    /// Reverts the last change. Returns `false` if there is nothing to undo.
    @discardableResult
    public mutating func undo() -> Bool {
        guard let step = undoStack.popLast() else { return false }
        redoStack.append(Step(actionName: step.actionName, library: library))
        library = step.library
        return true
    }

    /// Re-applies the last undone change. Returns `false` if there is nothing to redo.
    @discardableResult
    public mutating func redo() -> Bool {
        guard let step = redoStack.popLast() else { return false }
        undoStack.append(Step(actionName: step.actionName, library: library))
        library = step.library
        return true
    }

    /// Replaces the library, for example after loading it from disk, and clears undo and redo.
    public mutating func replace(with library: Library) {
        self.library = library
        undoStack.removeAll()
        redoStack.removeAll()
    }
}
