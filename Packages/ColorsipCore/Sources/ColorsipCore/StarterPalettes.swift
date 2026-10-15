import Foundation

/// One color in an optional palette distributed with Colorsip.
public struct StarterSwatch: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let color: CSipColor

    public init(id: UUID, name: String, color: CSipColor) {
        self.id = id
        self.name = name
        self.color = color
    }
}

/// A palette the user can choose to add to their library.
public struct StarterPalette: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let libraryName: String
    public let collectionName: String
    public let attribution: String
    public let swatches: [StarterSwatch]

    public init(
        id: UUID, name: String, libraryName: String, collectionName: String,
        attribution: String, swatches: [StarterSwatch]
    ) {
        self.id = id
        self.name = name
        self.libraryName = libraryName
        self.collectionName = collectionName
        self.attribution = attribution
        self.swatches = swatches
    }

    /// Makes the starter an ordinary, unlocked palette with stable palette and swatch identities.
    public func makePalette(at date: Date = .now) -> Palette {
        Palette(
            id: id,
            name: libraryName,
            description: attribution,
            isLocked: false,
            createdAt: date,
            ungrouped: swatches.map {
                Swatch(id: $0.id, color: $0.color, name: $0.name, createdAt: date)
            }
        )
    }
}

/// A versioned group of optional starter palettes from one source.
public struct StarterPaletteCollection: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let sourceURL: URL
    public let palettes: [StarterPalette]

    public init(id: String, name: String, sourceURL: URL, palettes: [StarterPalette]) {
        self.id = id
        self.name = name
        self.sourceURL = sourceURL
        self.palettes = palettes
    }
}

/// Starter collections bundled with this release. Nothing is installed until the user asks.
public enum StarterPaletteCatalog {
    public static let tailwindCSSV4: StarterPaletteCollection = makeTailwindCSSV4()
    public static let collections = [tailwindCSSV4]

    private static let familyNames = [
        "Slate", "Gray", "Zinc", "Neutral", "Stone", "Red", "Orange", "Amber", "Yellow",
        "Lime", "Green", "Emerald", "Teal", "Cyan", "Sky", "Blue", "Indigo", "Violet",
        "Purple", "Fuchsia", "Pink", "Rose",
    ]
    private static let shadeNames = ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"]
    private static let familyKeys = Set(familyNames.map { $0.lowercased() })

    private static func makeTailwindCSSV4() -> StarterPaletteCollection {
        let collectionName = "Tailwind CSS v4.1.18"
        let values = tailwindValues()
        let palettes = familyNames.enumerated().map { familyOffset, familyName in
            let familyKey = familyName.lowercased()
            let swatches = shadeNames.enumerated().map { shadeOffset, shadeName in
                guard let color = values[familyKey]?[shadeName] else {
                    preconditionFailure("Missing Tailwind color \(familyKey)-\(shadeName)")
                }
                return StarterSwatch(
                    id: stableUUID(prefix: "2295A401", number: (familyOffset + 1) * 1_000 + shadeOffset + 1),
                    name: shadeName,
                    color: color
                )
            }
            return StarterPalette(
                id: stableUUID(prefix: "2295A400", number: familyOffset + 1),
                name: familyName,
                libraryName: "Tailwind \(familyName)",
                collectionName: collectionName,
                attribution: "\(collectionName) — MIT",
                swatches: swatches
            )
        }
        guard let sourceURL = URL(string: "https://github.com/tailwindlabs/tailwindcss/blob/v4.1.18/packages/tailwindcss/theme.css") else {
            preconditionFailure("Invalid pinned Tailwind source URL")
        }
        return StarterPaletteCollection(
            id: "tailwind-css-v4.1.18",
            name: collectionName,
            sourceURL: sourceURL,
            palettes: palettes
        )
    }

    /// Parses the pinned upstream CSS so the distributed data remains directly auditable.
    private static func tailwindValues() -> [String: [String: CSipColor]] {
        guard let url = Bundle.module.url(forResource: "tailwind-v4.1.18-theme", withExtension: "css"),
              let css = try? String(contentsOf: url, encoding: .utf8)
        else {
            preconditionFailure("The bundled Tailwind CSS theme is missing")
        }

        var result: [String: [String: CSipColor]] = [:]
        for rawLine in css.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("--color-"),
                  let separator = line.range(of: ": oklch("),
                  line.hasSuffix(");")
            else { continue }

            let key = String(line[line.index(line.startIndex, offsetBy: 8)..<separator.lowerBound])
            guard let hyphen = key.lastIndex(of: "-") else { continue }
            let family = String(key[..<hyphen])
            let shade = String(key[key.index(after: hyphen)...])
            guard familyKeys.contains(family), shadeNames.contains(shade) else { continue }

            let start = separator.upperBound
            let end = line.index(line.endIndex, offsetBy: -2)
            let parts = line[start..<end].split(whereSeparator: \.isWhitespace)
            guard parts.count == 3,
                  let lightness = Double(parts[0].dropLast()),
                  let chroma = Double(parts[1]),
                  let hue = parts[2] == "none" ? 0 : Double(parts[2])
            else {
                preconditionFailure("Invalid Tailwind color declaration: \(line)")
            }
            result[family, default: [:]][shade] = CSipColor(.oklch, lightness / 100, chroma, hue)
        }
        return result
    }

    private static func stableUUID(prefix: String, number: Int) -> UUID {
        let string = String(format: "%@-0000-4000-8000-%012d", prefix, number)
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Invalid starter palette UUID: \(string)")
        }
        return uuid
    }
}
