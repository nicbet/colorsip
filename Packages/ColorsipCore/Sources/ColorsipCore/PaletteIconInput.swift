/// Input for the icon picker: one emoji, or an SF Symbol from a curated list.
extension PaletteIcon {
    /// `input` as an emoji icon if, trimmed, it is exactly one emoji: 🎨, 👍🏽, 🇨🇦, 👩‍🎨 or ❤️. Plain
    /// characters that only have an emoji variant, such as "#", "7" and "©", are refused.
    public static func emoji(from input: String) -> PaletteIcon? {
        guard let text = input.trimmedNonEmpty, text.count == 1, let first = text.unicodeScalars.first else { return nil }
        let scalars = text.unicodeScalars
        let isEmoji = first.properties.isEmojiPresentation
            || (first.properties.isEmoji && (scalars.contains("\u{FE0F}") || scalars.count > 1 && !scalars.contains("\u{20E3}")))
        return isEmoji ? .emoji(text) : nil
    }

    /// SF Symbols that suit a palette, in picker order.
    public static let curatedSymbols: [String] = [
        "paintpalette", "swatchpalette", "paintbrush", "paintbrush.pointed", "eyedropper", "pencil",
        "scribble", "drop", "circle.lefthalf.filled", "circle.hexagongrid", "square.on.square",
        "rectangle.3.group", "star", "heart", "bolt", "flame", "leaf", "tree", "sun.max", "moon",
        "cloud", "snowflake", "sparkles", "wand.and.stars", "camera", "photo", "film", "tv",
        "desktopcomputer", "laptopcomputer", "iphone", "applewatch", "gamecontroller", "music.note",
        "book", "bookmark", "folder", "doc", "tag", "flag", "bell", "briefcase", "cart", "gift",
        "house", "building.2", "globe", "map", "airplane", "car", "bicycle", "pawprint", "fish",
        "bird", "ladybug", "cup.and.saucer", "fork.knife", "birthday.cake", "tshirt", "crown",
        "diamond", "heart.circle", "star.circle", "person", "person.2", "face.smiling",
    ]

    /// The curated symbols whose names contain `query`, case-insensitively; all of them for an
    /// empty query.
    public static func symbols(matching query: String) -> [String] {
        guard let query = query.trimmedNonEmpty?.lowercased() else { return curatedSymbols }
        return curatedSymbols.filter { $0.contains(query) }
    }
}
