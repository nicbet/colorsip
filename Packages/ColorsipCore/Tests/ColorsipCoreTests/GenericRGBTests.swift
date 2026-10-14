#if canImport(CoreGraphics)
import CoreGraphics
import Foundation
import Testing
@testable import ColorsipCore

/// Checks the pure-math Generic RGB conversion against ColorSync, which reads Apple's
/// "Generic RGB Profile" directly.
@Suite("Generic RGB against CoreGraphics")
struct GenericRGBTests {
    static let profileURL = URL(
        fileURLWithPath: "/System/Library/ColorSync/Profiles/Generic RGB Profile.icc")

    @Test(arguments: [
        [0.5, 0.5, 0.5],
        [0.2, 0.4, 0.6],
        [0.7, 0.3, 0.4],
        [0.35, 0.6, 0.3],
        [0.9, 0.85, 0.2],
    ])
    func matchesColorSync(_ components: [Double]) throws {
        let data = try Data(contentsOf: Self.profileURL)
        let generic = try #require(CGColorSpace(iccData: data as CFData))
        let srgb = try #require(CGColorSpace(name: CGColorSpace.extendedSRGB))
        let cg = try #require(CGColor(colorSpace: generic, components: components.map { CGFloat($0) } + [1]))
        let converted = try #require(cg.converted(to: srgb, intent: .relativeColorimetric, options: nil))
        let expected = try #require(converted.components).prefix(3).map { Double($0) }

        let ours = CSipColor(.genericRGB, components[0], components[1], components[2]).converted(to: .srgb)
        expectComponents(ours, .srgb, expected, tolerance: 1e-4)
    }
}
#endif
