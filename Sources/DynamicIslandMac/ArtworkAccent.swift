import AppKit

/// Derives the warm accent tint used for the equalizer from the album art,
/// the way the reference design colors its bars to match the cover.
/// Picks the most colorful pixel of a downsampled cover rather than the plain
/// average, which on mixed covers washes out to grey.
enum ArtworkAccent {
    static func color(from image: NSImage) -> NSColor {
        let fallback = NSColor(calibratedRed: 0.80, green: 0.70, blue: 0.58, alpha: 1)

        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return fallback
        }

        let side = 16
        let bytesPerRow = side * 4
        var pixels = [UInt8](repeating: 0, count: side * side * 4)

        guard let ctx = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return fallback
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        var bestScore: CGFloat = -1
        var bestHue: CGFloat = 0
        var bestSaturation: CGFloat = 0

        for i in 0..<(side * side) {
            let r = CGFloat(pixels[i * 4]) / 255
            let g = CGFloat(pixels[i * 4 + 1]) / 255
            let b = CGFloat(pixels[i * 4 + 2]) / 255

            let maxC = max(r, g, b)
            let minC = min(r, g, b)
            guard maxC > 0 else { continue }

            let saturation = (maxC - minC) / maxC
            // Favor pixels that are both colorful and mid-to-bright, so the tint
            // stays legible against the near-black panel.
            let score = saturation * maxC

            if score > bestScore {
                bestScore = score
                var hue: CGFloat = 0
                var sat: CGFloat = 0
                var bri: CGFloat = 0
                NSColor(calibratedRed: r, green: g, blue: b, alpha: 1)
                    .getHue(&hue, saturation: &sat, brightness: &bri, alpha: nil)
                bestHue = hue
                bestSaturation = sat
            }
        }

        guard bestScore > 0.03 else { return fallback }

        // Normalize to a consistently light, softly saturated tint regardless of
        // how dark or garish the source pixel was.
        return NSColor(
            calibratedHue: bestHue,
            saturation: min(bestSaturation, 0.35),
            brightness: 0.88,
            alpha: 1
        )
    }
}
