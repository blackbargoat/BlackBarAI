import AppKit
import SwiftUI

/// Owns the bar panel and keeps it anchored to the bottom of the screen: full
/// width, directly above the Dock, or flush with the screen edge when nothing
/// reserves the bottom (full-screen apps, hidden Dock). The height only changes
/// when you drag the top edge; replies scroll inside the input box.
@MainActor
final class PanelController {
    static let defaultBarHeight: CGFloat = 28
    static let minBarHeight: CGFloat = 16

    private let model: AppModel
    private let bar = AgentPanel()
    /// Solid black window laid over the bar for the ⌥B blackout. It sits above
    /// everything in the bar, including the live text field editor, which
    /// SwiftUI can't hide, and never takes keyboard focus.
    private let cover: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.backgroundColor = .black
        panel.isOpaque = true
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        return panel
    }()
    private var isHidden = false
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        let host = FirstMouseHostingView(rootView: BarView(model: model))
        host.sizingOptions = []
        bar.contentView = host

        model.onLayoutChange = { [weak self] in self?.layout() }
        model.onBlankChange = { [weak self] blanked in self?.setBlackout(blanked) }
        model.prefs.onAppearanceChanged = { [weak self] in self?.applyTextColors() }
        applyTextColors()

        // The text field swallows Esc and ⌘A/⌘C before the window sees them,
        // so handle those at the app level while the bar has the keyboard.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.bar else { return event }
            return self.handleKey(event) ? nil : event
        }
        model.returnFocus = { [weak self] in self?.returnToWorkspace() }

        let center = NotificationCenter.default
        center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layout() }
        }
        // The user just clicked into the bar, coming from their browser: that's
        // the moment to check which Google Doc (if any) is in front.
        center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: bar, queue: .main) { [weak model] _ in
            MainActor.assumeIsolated { model?.barDidGainFocus() }
        }
        // Entering/leaving full screen switches Spaces; re-anchor once the switch settles.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                for delay in [0.05, 0.6] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        MainActor.assumeIsolated { self?.layout() }
                    }
                }
            }
        }
    }

    private var screen: NSScreen? { NSScreen.screens.first }

    /// Returns true when the key was handled here.
    private func handleKey(_ event: NSEvent) -> Bool {
        if event.keyCode == 53 { // Esc
            returnToWorkspace()
            return true
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased()
        if flags == .command, model.replyIsInBox {
            if key == "a" {
                model.isReplySelected = true
                return true
            }
            if key == "c", model.isReplySelected {
                model.copyTranscript()
                return true
            }
        }
        if model.isReplySelected, flags.isEmpty || key != "c" {
            model.isReplySelected = false
        }
        return false
    }

    func show() {
        isHidden = false
        layout()
    }

    private func applyTextColors() {
        bar.caretColor = model.prefs.caretColor
        bar.typingColor = model.prefs.textColor
        bar.forceArrowCursor = model.prefs.trueBlackout
    }

    private func setBlackout(_ on: Bool) {
        if on {
            cover.setFrame(bar.frame, display: false)
            bar.addChildWindow(cover, ordered: .above)
            cover.orderFrontRegardless()
        } else {
            bar.removeChildWindow(cover)
            cover.orderOut(nil)
        }
    }

    func toggleVisibility() {
        isHidden.toggle()
        if isHidden {
            bar.orderOut(nil)
            cover.orderOut(nil)
        } else {
            layout()
            if model.isBlanked { setBlackout(true) }
        }
    }

    func focusInput() {
        if isHidden { show() }
        bar.makeKeyAndOrderFront(nil)
        model.focusRequest += 1
    }

    /// Show/hide shortcut: a plain toggle. Hidden → show it with the cursor in
    /// the box. Showing → hide it (and hand the keyboard back if it had it).
    func toggleFromHotKey() {
        if isHidden {
            focusInput()
        } else {
            let hadKeyboard = bar.isKeyWindow
            toggleVisibility()
            if hadKeyboard { model.activateLastApp() }
        }
    }

    /// Esc: wipe the conversation (a fresh start) and give the keyboard back to
    /// the document. Ordering the panel out and back in drops its key status, so
    /// the browser's window takes the keyboard again.
    func returnToWorkspace() {
        model.clearConversation()
        model.draft = ""
        bar.orderOut(nil)
        if !isHidden { bar.orderFrontRegardless() }
        model.activateLastApp()
    }

    /// True when an app window spans the full width and reaches the bottom edge of
    /// the screen: a full-screen app (window sits below the notch, so it's shorter
    /// than the screen) or a hidden Dock. Either way nothing reserves the bottom,
    /// so the bar should sit flush on it. Bounds need no Screen Recording permission.
    private static func isFullScreenAppInFront(on screen: NSScreen) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CG window bounds are top-left based, in the primary display's space.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let screenRect = CGRect(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY,
                                width: screen.frame.width, height: screen.frame.height)
        return info.contains { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return false }
            return abs(bounds.minX - screenRect.minX) < 2
                && bounds.width >= screenRect.width - 2
                && abs(bounds.maxY - screenRect.maxY) < 2
                && bounds.height > screenRect.height * 0.8
        }
    }

    func layout() {
        guard !isHidden, let screen else { return }
        var area = screen.visibleFrame
        if Self.isFullScreenAppInFront(on: screen) {
            area.size.height += area.minY - screen.frame.minY
            area.origin.y = screen.frame.minY
        }
        model.barBottomY = area.minY
        model.maxBarHeight = (area.height * 0.6).rounded()

        let preferred = model.barHeight > 0 ? model.barHeight : Self.defaultBarHeight
        let height = min(max(preferred, Self.minBarHeight), model.maxBarHeight)
        bar.setFrame(NSRect(x: area.minX, y: area.minY, width: area.width, height: height), display: true)
        bar.orderFrontRegardless()
        if model.isBlanked { cover.setFrame(bar.frame, display: false) }
    }
}
