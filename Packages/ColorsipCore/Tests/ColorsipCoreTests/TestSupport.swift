import Foundation
import Testing
@testable import ColorsipCore

/// A fresh temporary library folder.
struct TempLibrary {
    let root = FileManager.default.temporaryDirectory.appending(path: "ColorsipTests-\(UUID().uuidString)")
    var store: LibraryStore { LibraryStore(folder: root.appending(path: "Library")) }
    func cleanUp() { try? FileManager.default.removeItem(at: root) }
}

/// Whether two component triples match within `tolerance`. The hue positions of `space` are
/// compared modulo 360.
func componentsMatch(
    _ actual: [Double], _ expected: [Double], tolerance: Double, hueIndex: Int? = nil
) -> Bool {
    guard actual.count == expected.count else { return false }
    for i in actual.indices {
        var diff = abs(actual[i] - expected[i])
        if i == hueIndex {
            diff = diff.truncatingRemainder(dividingBy: 360)
            diff = min(diff, 360 - diff)
        }
        if !(diff <= tolerance) { return false }
    }
    return true
}

/// Expects `color` to be in `space` with `expected` components within `tolerance`.
func expectComponents(
    _ color: CSipColor, _ space: ColorSpace, _ expected: [Double], tolerance: Double = 1e-4,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(color.colorSpace == space, sourceLocation: sourceLocation)
    #expect(
        componentsMatch(color.components, expected, tolerance: tolerance, hueIndex: space.hueIndex),
        "\(color.components) != \(expected)",
        sourceLocation: sourceLocation
    )
}

extension ColorSpace {
    /// Index of the hue component, if the space has one.
    var hueIndex: Int? {
        switch self {
        case .oklch: 2
        case .hsl, .hwb: 0
        default: nil
        }
    }
}
