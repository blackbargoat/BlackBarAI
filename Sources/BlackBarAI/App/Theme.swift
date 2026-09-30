import SwiftUI

/// True black to match the MacBook display border. Flat: no gradients, no glow.
/// Text tones come from ~/DESIGN.md's on-dark palette.
enum Theme {
    static let bar = Color.black
    static let field = Color(white: 0.02)                                    // #050505
    static let raised = Color(white: 0.10)                                   // #1a1a1a
    static let hairline = Color.white.opacity(0.06)
    static let fieldBorder = Color.white.opacity(0.07)
    static let fieldBorderFocused = Color.white.opacity(0.14)
    static let hover = Color.white.opacity(0.07)
    static let text = Color(red: 0.980, green: 0.976, blue: 0.961)           // #faf9f5
    static let textSoft = Color(red: 0.627, green: 0.616, blue: 0.588)       // #a09d96
    static let error = Color(red: 0.827, green: 0.380, blue: 0.360)

    // Text inside the bar: dim greys that sink into the black. Readable up
    // close, invisible from across the room.
    static let barText = Color(white: 0.30)
    static let barTextSoft = Color(white: 0.20)
    static let barError = Color(red: 0.40, green: 0.20, blue: 0.19)
    static let barSelection = Color(white: 0.12)
}
