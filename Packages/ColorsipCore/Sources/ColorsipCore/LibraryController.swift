import Observation

/// The app's library: loaded from a ``LibraryStore`` at launch, saved after every change, undo and
/// redo included (`spec.md` §7.6, §11.1). Only what changed is written.
///
/// Files the store couldn't load are listed in `loadIssues`; the store never overwrites them, so
/// the rest of the library is still saved.
@MainActor
@Observable
public final class LibraryController {
    public private(set) var loadIssues: [LibraryLoadIssue]
    /// The last save error, cleared by the next successful save.
    public private(set) var lastError: (any Error)?

    private var undoable: UndoableLibrary
    @ObservationIgnored private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
        let result = store.load()
        undoable = UndoableLibrary(result.library)
        loadIssues = result.issues
    }

    public var library: Library { undoable.library }
    public var canUndo: Bool { undoable.canUndo }
    public var canRedo: Bool { undoable.canRedo }
    public var undoActionName: String? { undoable.undoActionName }
    public var redoActionName: String? { undoable.redoActionName }

    /// Applies `change` as one undoable step and saves it. See ``UndoableLibrary/perform(_:_:)``.
    @discardableResult
    public func perform<T, E: Error>(_ actionName: String, _ change: (inout Library) throws(E) -> T) throws(E) -> T {
        let previous = library
        let result = try undoable.perform(actionName, change)
        save(previous: previous)
        return result
    }

    public func undo() {
        let previous = library
        if undoable.undo() { save(previous: previous) }
    }

    public func redo() {
        let previous = library
        if undoable.redo() { save(previous: previous) }
    }

    private func save(previous: Library) {
        guard library != previous else { return }
        do {
            // After a failed save the disk may lag `previous`, so write everything until a save works.
            try store.save(library, previous: lastError == nil ? previous : nil)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
