import SwiftUI

/// Building blocks for BlackBar's boxy settings: square outlines on black,
/// BoxText labels, monospaced values.
enum BoxStyle {
    static let background = Color.black
    static let card = Color.white.opacity(0.025)
    static let line = Color.white.opacity(0.13)
    static let lineStrong = Color.white.opacity(0.32)
    static let label = Color.white.opacity(0.88)
    static let muted = Color.white.opacity(0.42)
    static let faint = Color.white.opacity(0.22)
    static let danger = Color(red: 0.86, green: 0.36, blue: 0.33)
    static let ok = Color(red: 0.45, green: 0.80, blue: 0.55)

    static func mono(_ size: CGFloat = 11, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// A numbered, outlined section: "01  MODEL".
struct BoxSection<Content: View>: View {
    let index: Int
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                BoxText(text: String(format: "%02d", index), size: 8, color: BoxStyle.faint)
                BoxText(text: title, size: 8, color: BoxStyle.muted)
                Rectangle().fill(BoxStyle.line).frame(height: 1)
            }
            VStack(alignment: .leading, spacing: 14) { content }
        }
        .padding(18)
        .background(BoxStyle.card)
        .overlay(Rectangle().strokeBorder(BoxStyle.line, lineWidth: 1))
    }
}

/// Label on the left, control on the right.
struct BoxRow<Trailing: View>: View {
    let label: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                BoxText(text: label, size: 9, color: BoxStyle.label)
                if let detail {
                    Text(detail).font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
    }
}

struct BoxButton: View {
    let title: String
    var filled = false
    var danger = false
    var isEnabled = true
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            BoxText(text: title, size: 7.5, color: filled ? .black : (danger ? BoxStyle.danger : BoxStyle.label), tracking: 0.5, stroke: 0.15)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(filled ? Color.white.opacity(hovering ? 0.85 : 1) : Color.white.opacity(hovering ? 0.08 : 0))
                .overlay(Rectangle().strokeBorder(filled ? Color.clear : (danger ? BoxStyle.danger.opacity(0.6) : BoxStyle.lineStrong), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .onHover { hovering = $0 && isEnabled }
    }
}

/// Two or more options side by side; the selected one is filled white.
struct BoxSegmented<Value: Hashable>: View {
    let options: [(String, Value)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let (title, value) = options[i]
                let selected = value == selection
                Button { selection = value } label: {
                    BoxText(text: title, size: 7.5, color: selected ? .black : BoxStyle.muted, tracking: 0.5, stroke: 0.15)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected ? Color.white : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(Rectangle().strokeBorder(BoxStyle.lineStrong, lineWidth: 1))
    }
}

/// Square checkbox with ON / OFF.
struct BoxToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 10) {
                BoxText(text: isOn ? "ON" : "OFF", size: 7.5, color: isOn ? BoxStyle.label : BoxStyle.muted, tracking: 0.5, stroke: 0.15)
                ZStack {
                    Rectangle().strokeBorder(isOn ? Color.white : BoxStyle.lineStrong, lineWidth: 1)
                    if isOn { Rectangle().fill(Color.white).padding(3) }
                }
                .frame(width: 16, height: 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Plain or secure text field in a square outline.
struct BoxField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField("", text: $text, prompt: Text(placeholder).foregroundStyle(BoxStyle.faint))
            } else {
                TextField("", text: $text, prompt: Text(placeholder).foregroundStyle(BoxStyle.faint))
            }
        }
        .textFieldStyle(.plain)
        .font(BoxStyle.mono(12))
        .foregroundStyle(BoxStyle.label)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
        .overlay(Rectangle().strokeBorder(BoxStyle.line, lineWidth: 1))
    }
}

/// A keyboard shortcut shown as a square key cap.
struct KeyCap: View {
    let keys: String

    var body: some View {
        Text(keys)
            .font(BoxStyle.mono(11, .medium))
            .foregroundStyle(BoxStyle.label)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .overlay(Rectangle().strokeBorder(BoxStyle.lineStrong, lineWidth: 1))
    }
}

/// Slider with its value in mono, tinted white.
struct BoxSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double?
    let format: (Double) -> String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let step { Slider(value: $value, in: range, step: step) } else { Slider(value: $value, in: range) }
            }
            .tint(.white)
            .frame(width: 170)
            Text(format(value)).font(BoxStyle.mono(11)).foregroundStyle(BoxStyle.muted).frame(width: 52, alignment: .trailing)
        }
    }
}
