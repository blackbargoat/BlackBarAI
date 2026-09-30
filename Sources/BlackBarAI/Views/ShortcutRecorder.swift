import AppKit
import SwiftUI

/// Click, then press a new shortcut (with ⌘, ⌥ or ⌃). Esc cancels.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo
    let prefs: Preferences
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { isRecording ? stop() : start() }) {
            Text(isRecording ? "press keys…" : combo.display)
                .font(BoxStyle.mono(11, .medium))
                .foregroundStyle(isRecording ? Color.black : BoxStyle.label)
                .frame(minWidth: 110)
                .padding(.vertical, 6)
                .background(isRecording ? Color.white : Color.clear)
                .overlay(Rectangle().strokeBorder(BoxStyle.lineStrong, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onDisappear(perform: stop)
    }

    private func start() {
        isRecording = true
        prefs.isRecordingShortcut = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            guard let new = KeyCombo(event: event) else {
                NSSound.beep()
                return nil
            }
            combo = new
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            prefs.isRecordingShortcut = false
        }
    }
}
