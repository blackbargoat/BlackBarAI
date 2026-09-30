import SwiftUI

/// BlackBar's display lettering: square, geometric, even strokes, wide tracking.
/// Drawn as vector shapes (no font file), so it stays crisp at any size.
/// Covers A–Z, 0–9 and . , : - / ; lowercase is drawn as uppercase.
struct BoxText: View {
    let text: String
    var size: CGFloat
    var color: Color = .white
    /// Space between letters, as a fraction of the letter height.
    var tracking: CGFloat = 0.42
    /// Stroke thickness, as a fraction of the letter height.
    var stroke: CGFloat = 0.13

    var body: some View {
        let shape = BoxTextShape(text: text.uppercased(), tracking: tracking, stroke: stroke)
        shape
            .fill(color)
            .frame(width: shape.aspectWidth * size, height: size)
            .accessibilityLabel(text)
    }
}

struct BoxTextShape: Shape {
    let text: String
    let tracking: CGFloat
    let stroke: CGFloat

    /// Total width for a letter height of 1.
    var aspectWidth: CGFloat {
        let widths = text.map { BoxGlyph.width(of: $0, stroke: stroke) }
        return widths.reduce(0, +) + tracking * CGFloat(max(widths.count - 1, 0))
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        var x: CGFloat = 0
        for character in text {
            var glyph = BoxGlyph(width: BoxGlyph.width(of: character, stroke: stroke), stroke: stroke)
            glyph.draw(character)
            path.addPath(glyph.path, transform: CGAffineTransform(translationX: x, y: 0))
            x += glyph.width + tracking
        }
        let scale = rect.height
        return path.applying(CGAffineTransform(scaleX: scale, y: scale).translatedBy(x: rect.minX / scale, y: rect.minY / scale))
    }
}

/// One letter on a unit grid: height 1, y grows downward. Strokes are filled
/// rectangles and parallelograms, all wound the same way so overlaps stay solid.
private struct BoxGlyph {
    let width: CGFloat
    let stroke: CGFloat
    var path = Path()

    static func width(of character: Character, stroke t: CGFloat) -> CGFloat {
        switch character {
        case "I", "1", ".", ",", ":", "!", "'": return t
        case "M", "W": return 1.2
        case " ": return 0.5
        case "-": return 0.5
        case "/": return 0.6
        default: return 0.95
        }
    }

    // Shorthands: t stroke, r right stem x, c centre stem x, m middle bar y, b bottom bar y.
    private var t: CGFloat { stroke }
    private var w: CGFloat { width }
    private var r: CGFloat { width - stroke }
    private var c: CGFloat { (width - stroke) / 2 }
    private var m: CGFloat { (1 - stroke) / 2 }
    private var b: CGFloat { 1 - stroke }

    mutating func draw(_ character: Character) {
        switch character {
        case "A": v(0); v(r); h(0); h(m)
        case "B", "8": v(0); v(r); h(0); h(m); h(b)
        case "C": v(0); h(0); h(b)
        case "D": v(0); h(0, 0, r); h(b, 0, r); v(r, t, b)
        case "E": v(0); h(0); h(m, 0, w * 0.8); h(b)
        case "F": v(0); h(0); h(m, 0, w * 0.8)
        case "G": v(0); h(0); h(b); v(r, m, 1); h(m, w * 0.5, w)
        case "H": v(0); v(r); h(m)
        case "I", "1": v(0)
        case "J": v(r); h(b); v(0, 0.55, 1)
        case "K":
            v(0)
            let tx = slant(w - t, m)
            diag(top: w - tx, bottom: t, from: 0, to: m + t / 2)
            diag(top: t, bottom: w - tx, from: m + t / 2, to: 1)
        case "L": v(0); h(b)
        case "M": v(0); v(r); v(c); h(0)
        case "N": v(0); v(r); h(0)
        case "O", "0": v(0); v(r); h(0); h(b)
        case "P": v(0); h(0); h(m); v(r, 0, m + t)
        case "Q": v(0); v(r); h(0); h(b); v(c, b, 1.14)
        case "R":
            v(0); h(0); h(m); v(r, 0, m + t)
            let tx = slant(w * 0.5, 1 - m - t)
            diag(top: w * 0.45, bottom: w - tx, from: m + t, to: 1)
        case "S", "5": h(0); v(0, 0, m + t); h(m); v(r, m, 1); h(b)
        case "T": h(0); v(c)
        case "U": v(0); v(r); h(b)
        case "V":
            let tx = slant(c, 1)
            diag(top: 0, bottom: c, from: 0, to: 1)
            diag(top: w - tx, bottom: c, from: 0, to: 1)
        case "W": v(0); v(r); v(c); h(b)
        case "X":
            let tx = slant(w, 1)
            diag(top: 0, bottom: w - tx, from: 0, to: 1)
            diag(top: w - tx, bottom: 0, from: 0, to: 1)
        case "Y":
            let tx = slant(c, m)
            diag(top: 0, bottom: c, from: 0, to: m + t / 2)
            diag(top: w - tx, bottom: c, from: 0, to: m + t / 2)
            v(c, m, 1)
        case "Z":
            h(0); h(b)
            let tx = slant(w, 1 - 2 * t)
            diag(top: w - tx, bottom: 0, from: t, to: b)
        case "2": h(0); v(r, 0, m + t); h(m); v(0, m, 1); h(b)
        case "3": h(0); h(m, w * 0.25, w); h(b); v(r)
        case "4": v(0, 0, m + t); h(m); v(r)
        case "6": h(0); v(0); h(m); v(r, m, 1); h(b)
        case "7": h(0); v(r)
        case "9": h(0); v(0, 0, m + t); h(m); v(r); h(b)
        case ".", ",": box(0, b, t, t)
        case ":": box(0, 0.2, t, t); box(0, b - 0.1, t, t)
        case "!": v(0, 0, 0.62); box(0, b, t, t)
        case "'": v(0, 0, 0.3)
        case "-": h(m)
        case "/":
            let tx = slant(w, 1)
            diag(top: w - tx, bottom: 0, from: 0, to: 1)
        default: break
        }
    }

    /// Horizontal bar with its top edge at y.
    private mutating func h(_ y: CGFloat, _ x0: CGFloat = 0, _ x1: CGFloat? = nil) {
        box(x0, y, (x1 ?? w) - x0, t)
    }

    /// Vertical stem with its left edge at x.
    private mutating func v(_ x: CGFloat, _ y0: CGFloat = 0, _ y1: CGFloat = 1) {
        box(x, y0, t, y1 - y0)
    }

    private mutating func box(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
        polygon([CGPoint(x: x, y: y), CGPoint(x: x + width, y: y),
                 CGPoint(x: x + width, y: y + height), CGPoint(x: x, y: y + height)])
    }

    /// Horizontal thickness that gives a slanted stroke the same visual weight
    /// as the straight ones.
    private func slant(_ dx: CGFloat, _ dy: CGFloat) -> CGFloat {
        t * (dx * dx + dy * dy).squareRoot() / max(dy, 0.001)
    }

    /// Slanted stroke whose left edge runs from (top, from) to (bottom, to).
    private mutating func diag(top x0: CGFloat, bottom x1: CGFloat, from y0: CGFloat, to y1: CGFloat) {
        let tx = slant(abs(x1 - x0) + t, y1 - y0)
        polygon([CGPoint(x: x0, y: y0), CGPoint(x: x0 + tx, y: y0),
                 CGPoint(x: x1 + tx, y: y1), CGPoint(x: x1, y: y1)])
    }

    /// Adds a closed polygon, reversed if needed so every piece winds the same
    /// direction (overlapping strokes then fill solid under non-zero winding).
    private mutating func polygon(_ points: [CGPoint]) {
        var area: CGFloat = 0
        for i in points.indices {
            let a = points[i], z = points[(i + 1) % points.count]
            area += a.x * z.y - z.x * a.y
        }
        let ordered = area >= 0 ? points : points.reversed()
        path.addLines(ordered)
        path.closeSubpath()
    }
}
