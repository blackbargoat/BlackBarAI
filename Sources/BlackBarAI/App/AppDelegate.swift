import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var panels: PanelController!
    private var statusItem: NSStatusItem!
    private var hotKeys: [HotKey] = []
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMainMenu()
        panels = PanelController(model: model)
        panels.show()

        model.openSettings = { [weak self] in self?.showSettings() }
        setUpStatusItem()
        model.prefs.onHotKeysChanged = { [weak self] in self?.registerHotKeys() }
        registerHotKeys()

        // Only on first run: nothing works without a key, so ask once.
        if ChatProvider.selected.makeClient() == nil { showSettings() }
    }

    /// blackbar://demo?q1=…&q2=…  runs the scripted launch demo in the real app.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first, url.host == "demo" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        let director = DemoDirector(model: model, panels: panels)
        Task { await director.run(first: value("q1"), followUp: value("q2")) }
    }

    /// (Re)registers the global shortcuts from Preferences. Off while a new
    /// shortcut is being recorded in Settings.
    private func registerHotKeys() {
        hotKeys = []
        let prefs = model.prefs
        guard !prefs.isRecordingShortcut else { return }
        let bindings: [(KeyCombo, () -> Void)] = [
            (prefs.showHideKey, { [weak self] in self?.panels.toggleFromHotKey() }),
            (prefs.settingsKey, { [weak self] in self?.showSettings() }),
            (prefs.blackoutKey, { [weak self] in self?.model.toggleBlank() }),
        ]
        hotKeys = bindings.compactMap { combo, action in
            HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers, action: action)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: Status item

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.bottomhalf.inset.filled", accessibilityDescription: "BlackBarAI")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Hide Agent", action: #selector(toggleAgent), keyEquivalent: "")
        menu.addItem(withTitle: "Black Out Text", action: #selector(toggleBlank), keyEquivalent: "")
        menu.addItem(withTitle: "Clear Conversation", action: #selector(clearConversation), keyEquivalent: "")
        menu.addItem(withTitle: "Reset Bar Height", action: #selector(resetBarHeight), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit BlackBarAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        statusItem.menu = menu
    }

    @objc private func toggleBlank() { model.toggleBlank() }
    @objc private func clearConversation() { model.clearConversation() }
    @objc private func resetBarHeight() { model.resetHeights() }
    @objc private func toggleAgent() { panels.toggleVisibility() }
    @objc private func openSettingsFromMenu() { showSettings() }

    // MARK: Settings

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false)
            window.title = "BlackBar Settings"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.backgroundColor = .black
            window.appearance = NSAppearance(named: .darkAqua)
            window.minSize = NSSize(width: 580, height: 480)
            window.maxSize = NSSize(width: 580, height: 2000)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, google: model.google, prefs: model.prefs))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Accessory apps still need an Edit menu, or ⌘C / ⌘V / ⌘A do nothing in text fields.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit BlackBarAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)
        return main
    }
}
