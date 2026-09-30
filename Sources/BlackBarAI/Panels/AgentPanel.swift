import AppKit
import SwiftUI

/// A borderless, non-activating floating panel.
/// - Floats above normal app windows (Chrome / Google Docs) on every Space.
/// - Clicking it lets you type without activating BlackBarAI, so the browser
///   stays the frontmost app and nothing else on screen moves or changes.
final class AgentPanel: NSPanel {
    var onEscape: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
    }

    /// Caret and typed-text colors for the box (dim grey, or black in True
    /// Blackout). Applied to the field editor SwiftUI installs; SwiftUI requires
    /// its own editor class, so we restyle it rather than supplying our own.
    var caretColor: NSColor = .gray {
        didSet { applyTextColors() }
    }
    var typingColor: NSColor = .gray {
        didSet { applyTextColors() }
    }

    /// The text field restyles its editor when editing starts, so re-apply the
    /// colors every time something in the bar takes the keyboard.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let result = super.makeFirstResponder(responder)
        applyTextColors()
        DispatchQueue.main.async { [weak self] in self?.applyTextColors() }
        return result
    }

    private func applyTextColors() {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = caretColor
        editor.textColor = typingColor
        editor.typingAttributes[.foregroundColor] = typingColor
        if let storage = editor.textStorage, storage.length > 0 {
            storage.addAttribute(.foregroundColor, value: typingColor, range: NSRange(location: 0, length: storage.length))
        }
    }

    /// True Blackout: keep the plain arrow pointer over the bar, so the text
    /// I-beam doesn't give away that there's hidden text. The top edge keeps its
    /// resize pointer.
    var forceArrowCursor = false {
        didSet {
            guard forceArrowCursor != oldValue else { return }
            if forceArrowCursor { disableCursorRects() } else { enableCursorRects() }
            if let contentView { invalidateCursorRects(for: contentView) }
        }
    }

    override func sendEvent(_ event: NSEvent) {
        guard forceArrowCursor else { return super.sendEvent(event) }
        let onResizeEdge = event.locationInWindow.y > frame.height - 7
        if event.type == .cursorUpdate, !onResizeEdge {
            NSCursor.arrow.set()
            return
        }
        super.sendEvent(event)
        let pointerEvents: [NSEvent.EventType] = [.mouseMoved, .mouseEntered, .leftMouseDown, .leftMouseUp, .leftMouseDragged]
        if pointerEvents.contains(event.type), !onResizeEdge {
            NSCursor.arrow.set()
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }
}

/// Lets the first click on an inactive panel hit buttons/fields directly.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

extension NSScreen {
    /// Real points-per-inch for this display, from its physical size.
    var pointsPerInch: CGFloat {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let id = deviceDescription[key] as? CGDirectDisplayID else { return 110 }
        let mm = CGDisplayScreenSize(id)
        guard mm.width > 0 else { return 110 }
        return min(max(frame.width / (mm.width / 25.4), 72), 220)
    }
}
