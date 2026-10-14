import Foundation

/// An entry of a color name list.
public struct ColorName: Sendable, Hashable {
    public let name: String
    /// The entry's color, in sRGB.
    public let color: CSipColor
}

/// Friendly color names: the nearest entry by ΔEOK in a name list. See `spec.md` §5.5.
///
/// The entries are indexed once in a static 3-d k-d tree over OKLab, so lookups are fast enough
/// to run on every pointer move in the loupe.
public final class ColorNames: Sendable {
    /// The bundled meodai/color-name-list (MIT), loaded and indexed on first use.
    public static let shared: ColorNames = {
        guard
            let url = Bundle.module.url(forResource: "colornames", withExtension: "csv"),
            let csv = try? String(contentsOf: url, encoding: .utf8)
        else { preconditionFailure("colornames.csv is missing from the ColorsipCore bundle") }
        return ColorNames(csv: csv)
    }()

    /// The entries in list order.
    let entries: [ColorName]
    /// The entries' OKLab positions, by list index.
    private let points: [Vector3]
    /// List indices in k-d order: each sub-range has its split node in the middle, the entries
    /// below it on the left and those above it on the right. The split axis cycles L, a, b.
    private let tree: [Int]

    /// Builds the index from `name,#rrggbb` lines. Lines that don't match, such as a header, are
    /// skipped.
    public init(csv: String) {
        entries = csv.split(whereSeparator: \.isNewline).compactMap(Self.parse)
        points = entries.map { $0.color.converted(to: .oklab).vector }
        var tree = Array(entries.indices)
        Self.build(&tree, points, tree.startIndex..<tree.endIndex, axis: 0)
        self.tree = tree
    }

    public var count: Int { entries.count }

    /// The nearest entry by ΔEOK, or `nil` if the list is empty. Alpha is ignored. On a tie, the
    /// entry that comes first in the list wins.
    public func nearest(to color: CSipColor) -> ColorName? {
        guard !tree.isEmpty else { return nil }
        var best = (index: Int.max, distance: Double.infinity)
        search(color.converted(to: .oklab).vector, tree.startIndex..<tree.endIndex, axis: 0, &best)
        return entries[best.index]
    }

    private func search(
        _ query: Vector3, _ range: Range<Int>, axis: Int, _ best: inout (index: Int, distance: Double)
    ) {
        guard !range.isEmpty else { return }
        let mid = range.lowerBound + range.count / 2
        let index = tree[mid]
        let point = points[index]
        let distance = (query - point).lengthSquared
        if distance < best.distance || (distance == best.distance && index < best.index) {
            best = (index, distance)
        }
        let diff = query[axis] - point[axis]
        let left = range.lowerBound..<mid
        let right = mid + 1..<range.upperBound
        let next = (axis + 1) % 3
        search(query, diff < 0 ? left : right, axis: next, &best)
        // `<=` keeps equal-distance entries on the far side reachable, for the tie rule.
        if diff * diff <= best.distance {
            search(query, diff < 0 ? right : left, axis: next, &best)
        }
    }

    private static func build(_ tree: inout [Int], _ points: [Vector3], _ range: Range<Int>, axis: Int) {
        guard range.count > 1 else { return }
        tree[range].sort { points[$0][axis] < points[$1][axis] }
        let mid = range.lowerBound + range.count / 2
        let next = (axis + 1) % 3
        build(&tree, points, range.lowerBound..<mid, axis: next)
        build(&tree, points, mid + 1..<range.upperBound, axis: next)
    }

    private static func parse(_ line: Substring) -> ColorName? {
        guard let comma = line.lastIndex(of: ",") else { return nil }
        let name = line[..<comma].trimmingCharacters(in: .whitespaces)
        let hex = line[line.index(after: comma)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !name.isEmpty, hex.count == 7, hex.first == "#",
            hex.dropFirst().allSatisfy(\.isHexDigit),
            let value = Int(hex.dropFirst(), radix: 16)
        else { return nil }
        let color = CSipColor(
            .srgb, Double((value >> 16) & 0xff) / 255, Double((value >> 8) & 0xff) / 255,
            Double(value & 0xff) / 255)
        return ColorName(name: name, color: color)
    }
}

extension CSipColor {
    /// The name of the nearest entry in the bundled color name list.
    public var friendlyName: String {
        ColorNames.shared.nearest(to: self)?.name ?? ""
    }
}
