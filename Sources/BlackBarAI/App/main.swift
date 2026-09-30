import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Accessory: no Dock icon, no ⌘-Tab entry. BlackBarAI is a utility, not a workspace.
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) { app.run() }
}
