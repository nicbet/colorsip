import Foundation

/// Sends one pick where `spec.md` §4.5 says, as soon as it is made: into Color History, to the front
/// of the pick target (one undoable step, see ``LibraryController/addPick(_:name:at:)``), and onto
/// the clipboard in `format`, so the last pick of a session is the one left there. Picks are named
/// after the color (§5.5).
@MainActor
public func routePick(
    _ color: CSipColor, format: OutputFormat, history: ColorHistoryController, library: LibraryController,
    clipboard: some Clipboard, at date: Date = .now
) {
    let name = color.friendlyName
    history.record(color, name: name, at: date)
    library.addPick(color, name: name, at: date)
    copyValue(of: color, as: format, to: clipboard)
}
