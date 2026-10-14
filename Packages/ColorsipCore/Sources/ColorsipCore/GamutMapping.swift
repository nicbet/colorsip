extension CSipColor {
    /// This color in `space`, brought into its gamut with the CSS Color 4 gamut mapping algorithm:
    /// a binary search that reduces OKLCH chroma until clipping the result changes it by less
    /// than a just-noticeable difference. Lightness and hue are kept. OKLab and OKLCH are returned
    /// unchanged apart from the conversion.
    ///
    /// See https://www.w3.org/TR/css-color-4/#binsearch
    public func gamutMapped(to space: ColorSpace = .srgb) -> CSipColor {
        guard let rgb = space.gamutSpace else { return converted(to: space) }

        let origin = converted(to: .oklch)
        let lightness = origin.components[0]
        if lightness >= 1 {
            return CSipColor(rgb.colorSpace, 1, 1, 1, alpha: alpha).converted(to: space)
        }
        if lightness <= 0 {
            return CSipColor(rgb.colorSpace, 0, 0, 0, alpha: alpha).converted(to: space)
        }
        if isInGamut(space) { return converted(to: space) }

        let jnd = 0.02
        let epsilon = 0.0001
        func clip(_ color: CSipColor) -> CSipColor {
            let c = color.converted(to: rgb.colorSpace).vector.map { min(max($0, 0), 1) }
            return CSipColor(rgb.colorSpace, c, alpha: alpha)
        }

        var current = origin
        var clipped = clip(current)
        if clipped.deltaEOK(current) < jnd { return clipped.converted(to: space) }

        var low = 0.0
        var high = origin.components[1]
        var lowInGamut = true
        while high - low > epsilon {
            let chroma = (low + high) / 2
            current.components[1] = chroma
            if lowInGamut && current.isInGamut(rgb.colorSpace) {
                low = chroma
                continue
            }
            clipped = clip(current)
            let delta = clipped.deltaEOK(current)
            if delta < jnd {
                if jnd - delta < epsilon { break }
                lowInGamut = false
                low = chroma
            } else {
                high = chroma
            }
        }
        return clipped.converted(to: space)
    }
}
