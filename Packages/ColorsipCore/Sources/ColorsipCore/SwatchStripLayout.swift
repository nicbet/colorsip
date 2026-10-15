/// The geometry of a palette's swatch strip (`spec.md` §7.3), in points.
///
/// Up to 16 swatches spread out to fill the strip. Beyond that each segment is 1/16 of the width and
/// the strip scrolls horizontally. The ungrouped section and each group are drawn as their own
/// section, separated by ``groupGap``; empty sections are left out.
public struct SwatchStripLayout: Sendable, Equatable {
    public static let swatchesAcross = 16
    public static let groupGap = 6.0
    /// How far from an end the scroll offset can be and still count as at that end.
    static let fadeTolerance = 0.5

    /// A run of touching segments: the ungrouped section or one group.
    public struct Section: Sendable, Equatable, Identifiable {
        /// `nil` for the ungrouped section.
        public var group: SwatchGroup.ID?
        public var swatches: [Swatch]
        public var x: Double
        public var width: Double
        public var segmentWidth: Double

        public var id: SwatchGroup.ID? { group }

        /// The x position of the swatch at `index` in the strip.
        public func swatchX(_ index: Int) -> Double { x + Double(index) * segmentWidth }
    }

    /// Which edges of the strip fade because there is more content in that direction.
    public struct Fades: Sendable, Equatable {
        public var leading: Bool
        public var trailing: Bool

        public init(leading: Bool, trailing: Bool) {
            self.leading = leading
            self.trailing = trailing
        }
    }

    public let width: Double
    public let segmentWidth: Double
    public let sections: [Section]
    public let contentWidth: Double

    public init(palette: Palette, width: Double) {
        self.init(runs: [(nil, palette.ungrouped)] + palette.groups.map { ($0.id, $0.swatches) }, width: width)
    }

    /// A strip of `swatches` as one section, such as Color History.
    public init(swatches: [Swatch], width: Double) {
        self.init(runs: [(nil, swatches)], width: width)
    }

    private init(runs: [(SwatchGroup.ID?, [Swatch])], width: Double) {
        let width = max(width, 0)
        let filled = runs.filter { !$0.1.isEmpty }
        let count = filled.reduce(0) { $0 + $1.1.count }
        let segmentWidth: Double
        if count > 0 && count <= Self.swatchesAcross {
            // Few enough to spread out: the segments share what the gaps leave.
            let gaps = Double(filled.count - 1) * Self.groupGap
            segmentWidth = max(width - gaps, 0) / Double(count)
        } else {
            segmentWidth = width / Double(Self.swatchesAcross)
        }
        var sections: [Section] = []
        var x = 0.0
        for (group, swatches) in runs where !swatches.isEmpty {
            if !sections.isEmpty { x += Self.groupGap }
            let sectionWidth = Double(swatches.count) * segmentWidth
            sections.append(Section(group: group, swatches: swatches, x: x, width: sectionWidth, segmentWidth: segmentWidth))
            x += sectionWidth
        }
        self.width = width
        self.segmentWidth = segmentWidth
        self.sections = sections
        self.contentWidth = x
    }

    /// The palette has no swatches, so the "Drop colors here" target is shown instead.
    public var isEmpty: Bool { sections.isEmpty }

    public var isScrollable: Bool { contentWidth > width + Self.fadeTolerance }

    /// The fades for the horizontal scroll `offset` (0 at the start).
    public func fades(offset: Double) -> Fades {
        guard isScrollable else { return Fades(leading: false, trailing: false) }
        return Fades(
            leading: offset > Self.fadeTolerance,
            trailing: offset + width < contentWidth - Self.fadeTolerance)
    }
}
