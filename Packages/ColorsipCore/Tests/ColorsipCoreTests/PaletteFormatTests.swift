import Foundation
import Testing
@testable import ColorsipCore

/// A palette that exercises every field and the awkward names.
func richPalette() throws -> Palette {
    var library = Library()
    let p = library.createPalette(name: "Brand ✨", at: t0)
    try library.setDescription("The brand colors", of: p, at: t0)
    try library.setIcon(.symbol("paintpalette.fill"), of: p, at: t0)
    let g = try library.addGroup(name: "Neutrals", to: p, at: t0)
    let odd = try library.addGroup(name: "a.b", to: p, at: t0)
    try library.insertSwatch(color: CSipColor(.displayP3, 0.2364, 0.2353, 0.8588), name: "Blue", into: .ungrouped(p), at: t0)
    try library.insertSwatch(color: redColor, name: "Red", description: "Alarm", into: .ungrouped(p), index: 1, at: t1)
    try library.insertSwatch(color: greenColor, name: "Red", into: .ungrouped(p), index: 2, at: t1)  // same name
    try library.insertSwatch(color: CSipColor(.oklch, 0.7, 0.4, 150, alpha: 0.5), name: "{ref}", into: .ungrouped(p), index: 3, at: t1)
    try library.insertSwatch(color: CSipColor(.hsl, 210, 40, 50), name: "$money", into: .ungrouped(p), index: 4, at: t1)
    try library.insertSwatch(color: CSipColor(.srgb, 2, -0.5, 0.25), name: "", into: .ungrouped(p), index: 5, at: t1)
    try library.insertSwatch(color: CSipColor(.srgb, 0.5, 0.5, 0.5), name: "Neutrals", into: .ungrouped(p), index: 6, at: t1)
    try library.insertSwatch(color: CSipColor(.genericRGB, 0.1, 0.2, 0.3), name: "Gray 1.5", into: .group(g, in: p), at: t2)
    try library.insertSwatch(color: CSipColor(.hwb, 30, 10, 20), name: "Warm", into: .group(g, in: p), index: 1, at: t2)
    _ = odd
    return try #require(library.palette(p))
}

private func object(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite("Colorsip palette format")
struct PaletteFormatTests {
    @Test func roundTrip() throws {
        let palette = try richPalette()
        let decoded = try ColorsipPaletteFormat.decode(ColorsipPaletteFormat.encode(palette))
        #expect(decoded == palette)
    }

    @Test func roundTripsLockedEmptyAndEmojiPalettes() throws {
        var palette = Palette(name: "Empty", at: t0)
        palette.isLocked = true
        palette.icon = .emoji("🎨")
        #expect(try ColorsipPaletteFormat.decode(ColorsipPaletteFormat.encode(palette)) == palette)
    }

    @Test func dtcgShape() throws {
        let palette = try richPalette()
        let root = try object(ColorsipPaletteFormat.encode(palette))
        #expect(root["$description"] as? String == "The brand colors")
        #expect(root["formatVersion"] == nil)
        let meta = try #require((root["$extensions"] as? [String: Any])?["app.colorsip"] as? [String: Any])
        #expect(meta["formatVersion"] as? Int == 1)
        #expect(meta["id"] as? String == palette.id.uuidString)
        #expect(meta["name"] as? String == "Brand ✨")
        #expect(meta["locked"] as? Bool == false)
        #expect(meta["createdAt"] as? String == "2027-01-15T08:00:00.000Z")
        #expect((meta["icon"] as? [String: String]) == ["symbol": "paintpalette.fill"])
        #expect(
            meta["order"] as? [String]
                == ["Blue", "Red", "Red 2", "_ref_", "money", "Color", "Neutrals", "Neutrals 2", "a_b"])

        let red = try #require(root["Red"] as? [String: Any])
        #expect(red["$type"] as? String == "color")
        #expect(red["$description"] as? String == "Alarm")
        let value = try #require(red["$value"] as? [String: Any])
        #expect(value["colorSpace"] as? String == "srgb")
        #expect(value["components"] as? [Double] == [1, 0, 0])
        #expect(value["alpha"] as? Double == 1)
        #expect(value["hex"] as? String == "#ff0000")

        let group = try #require(root["Neutrals 2"] as? [String: Any])
        #expect(group["$type"] == nil && group["$value"] == nil)
        let groupMeta = try #require((group["$extensions"] as? [String: Any])?["app.colorsip"] as? [String: Any])
        #expect(groupMeta["name"] as? String == "Neutrals")
        #expect(groupMeta["order"] as? [String] == ["Gray 1_5", "Warm"])
        #expect(group["Gray 1_5"] != nil)
    }

    @Test func outputIsDeterministicAndSorted() throws {
        let palette = try richPalette()
        let data = ColorsipPaletteFormat.encode(palette)
        #expect(data == ColorsipPaletteFormat.encode(palette))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\n  "))  // pretty-printed
        let blue = try #require(text.range(of: "\"Blue\""))
        let red = try #require(text.range(of: "\"Red\""))
        #expect(blue.lowerBound < red.lowerBound)
    }

    @Test func hexIsIgnoredOnRead() throws {
        let data = Data(##"{ "colorSpace": "srgb", "components": [0, 0, 1], "hex": "#ff0000" }"##.utf8)
        let color = try JSONDecoder().decode(CSipColor.self, from: data)
        #expect(color == CSipColor(.srgb, 0, 0, 1))  // alpha defaults to 1
    }

    @Test func colorCodingRejectsBadValues() {
        for json in [
            #"{ "colorSpace": "cmyk", "components": [0, 0, 1] }"#,
            #"{ "colorSpace": "srgb", "components": [0, 1] }"#,
        ] {
            #expect(throws: DecodingError.self) { try JSONDecoder().decode(CSipColor.self, from: Data(json.utf8)) }
        }
    }

    @Test func newerFormatIsRefused() throws {
        var root = try object(ColorsipPaletteFormat.encode(Palette(name: "A", at: t0)))
        var extensions = try #require(root["$extensions"] as? [String: Any])
        var meta = try #require(extensions["app.colorsip"] as? [String: Any])
        meta["formatVersion"] = 2
        extensions["app.colorsip"] = meta
        root["$extensions"] = extensions
        let data = try JSONSerialization.data(withJSONObject: root)
        #expect(throws: ColorsipFormatError.newerFormat(2)) { try ColorsipPaletteFormat.decode(data) }
    }

    @Test func invalidFilesAreRefused() {
        for json in ["not json", "[]", #"{ "Red": { "$type": "color" } }"#] {
            #expect(throws: ColorsipFormatError.self) { try ColorsipPaletteFormat.decode(Data(json.utf8)) }
        }
    }
}

@Suite("Colorsip palette schema")
struct PaletteSchemaTests {
    @Test func encodedPalettesValidate() throws {
        let schema = try SchemaValidator.colorsipPalette()
        var locked = Palette(name: "Locked", at: t0)
        locked.isLocked = true
        locked.icon = .emoji("🎨")
        for palette in [try richPalette(), Palette(name: "Empty", at: t0), locked] {
            let errors = try schema.errors(ColorsipPaletteFormat.encode(palette))
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    @Test(arguments: [
        // No metadata
        #"{ "Red": { "$type": "color", "$value": { "colorSpace": "srgb", "components": [1, 0, 0] } } }"#,
        // Bad color space
        validPalette(token: #""$value": { "colorSpace": "cmyk", "components": [1, 0, 0] }"#),
        // Two components
        validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0] }"#),
        // Alpha out of range
        validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0, 0], "alpha": 2 }"#),
        // Unknown key in a token
        validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0, 0] }, "extra": 1"#),
        // Bad hex
        validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0, 0], "hex": "red" }"#),
    ])
    func invalidFilesFail(json: String) throws {
        let schema = try SchemaValidator.colorsipPalette()
        #expect(try !schema.errors(Data(json.utf8)).isEmpty)
    }

    @Test func handWrittenValidFilePasses() throws {
        let schema = try SchemaValidator.colorsipPalette()
        let json = validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0, 0] }"#)
        #expect(try schema.errors(Data(json.utf8)) == [])
    }

    @Test func dottedKeyFails() throws {
        let schema = try SchemaValidator.colorsipPalette()
        let json = validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0, 0] }"#)
            .replacingOccurrences(of: #""Red":"#, with: #""Re.d":"#)
        #expect(try !schema.errors(Data(json.utf8)).isEmpty)
    }

    @Test func missingFormatVersionFails() throws {
        let schema = try SchemaValidator.colorsipPalette()
        let json = validPalette(token: #""$value": { "colorSpace": "srgb", "components": [1, 0, 0] }"#)
            .replacingOccurrences(of: #""formatVersion": 1, "#, with: "")
        #expect(try !schema.errors(Data(json.utf8)).isEmpty)
    }
}

/// A minimal valid `.colorsip` file with one token "Red" whose body is `token` plus metadata.
private func validPalette(token: String) -> String {
    let stamp = "2026-10-14T10:00:00.000Z"
    return #"""
        { "$extensions": { "app.colorsip": {
            "formatVersion": 1, "id": "6F1C4A42-8E0B-4D1B-9E36-0A8D4E0F1B2C", "name": "P",
            "locked": false, "createdAt": "\#(stamp)", "modifiedAt": "\#(stamp)", "order": ["Red"] } },
          "Red": { "$type": "color", \#(token),
            "$extensions": { "app.colorsip": {
              "id": "0E7B7F5A-3A51-4B1C-8F7E-2B6C1D9A4E10", "name": "Red",
              "createdAt": "\#(stamp)", "modifiedAt": "\#(stamp)" } } } }
        """#
}
