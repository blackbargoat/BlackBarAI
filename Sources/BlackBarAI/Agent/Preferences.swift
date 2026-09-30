import AppKit
import Carbon.HIToolbox
import Observation

/// A global keyboard shortcut (Carbon key code + modifiers) and how to show it.
struct KeyCombo: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var display: String

    static let showHide = KeyCombo(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥Space")
    static let settings = KeyCombo(keyCode: UInt32(kVK_ANSI_Comma), modifiers: UInt32(controlKey | optionKey), display: "⌃⌥,")
    static let blackout = KeyCombo(keyCode: UInt32(kVK_ANSI_B), modifiers: UInt32(optionKey), display: "⌥B")

    /// Builds a combo from a key press; nil unless ⌘, ⌥ or ⌃ is held.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.subtracting(.shift).isEmpty else { return nil }
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        self.init(keyCode: UInt32(event.keyCode), modifiers: carbon, display: symbols + Self.keyName(event))
    }

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    private static func keyName(_ event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Delete: return "Delete"
        case kVK_Escape: return "Esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1...kVK_F20: return "F\(fKeyNumber(Int(event.keyCode)))"
        default: return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static func fKeyNumber(_ code: Int) -> Int {
        let order = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                     kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
        return (order.firstIndex(of: code) ?? 0) + 1
    }
}

/// User-adjustable look and shortcuts, saved in UserDefaults.
@MainActor @Observable
final class Preferences {
    static let fontSizeRange: ClosedRange<Double> = 8...16

    var fontSize: Double = Preferences.load("fontSize", default: 13.0) {
        didSet { save(fontSize, "fontSize") }
    }
    /// Where the text box sits along the bar: 0 = far left, 0.5 = centre, 1 = far right.
    var boxPosition: Double = Preferences.load("boxPosition", default: 0.5) {
        didSet { save(boxPosition, "boxPosition") }
    }
    /// Text and caret are drawn in the bar's own black: invisible unless selected.
    var trueBlackout: Bool = Preferences.load("trueBlackout", default: false) {
        didSet { save(trueBlackout, "trueBlackout"); onAppearanceChanged?() }
    }

    /// Demo recordings only (not saved): bright text so it reads on camera.
    var demoBright = false {
        didSet { onAppearanceChanged?() }
    }

    var showHideKey: KeyCombo = Preferences.loadCombo("key.showHide") ?? .showHide {
        didSet { saveCombo(showHideKey, "key.showHide") }
    }
    var settingsKey: KeyCombo = Preferences.loadCombo("key.settings") ?? .settings {
        didSet { saveCombo(settingsKey, "key.settings") }
    }
    var blackoutKey: KeyCombo = Preferences.loadCombo("key.blackout") ?? .blackout {
        didSet { saveCombo(blackoutKey, "key.blackout") }
    }
    /// While a shortcut is being recorded, global hotkeys are switched off so
    /// the key press reaches the recorder.
    var isRecordingShortcut = false {
        didSet { onHotKeysChanged?() }
    }

    @ObservationIgnored var onHotKeysChanged: (() -> Void)?
    @ObservationIgnored var onAppearanceChanged: (() -> Void)?

    func resetShortcuts() {
        showHideKey = .showHide
        settingsKey = .settings
        blackoutKey = .blackout
    }

    // MARK: Colors for text inside the bar

    var textColor: NSColor { demoBright ? NSColor(white: 0.96, alpha: 1) : trueBlackout ? .black : NSColor(white: 0.30, alpha: 1) }
    var softTextColor: NSColor { demoBright ? NSColor(white: 0.62, alpha: 1) : trueBlackout ? .black : NSColor(white: 0.20, alpha: 1) }
    var caretColor: NSColor { demoBright ? NSColor(white: 0.96, alpha: 1) : trueBlackout ? .black : NSColor(white: 0.30, alpha: 1) }

    // MARK: Storage

    private static func load<T>(_ key: String, default value: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? value
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func loadCombo(_ key: String) -> KeyCombo? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(KeyCombo.self, from: $0) }
    }

    private func saveCombo(_ combo: KeyCombo, _ key: String) {
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: key)
        onHotKeysChanged?()
    }
}
