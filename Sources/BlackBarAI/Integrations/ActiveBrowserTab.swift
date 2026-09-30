import AppKit

/// Reads the URL of the front tab of a supported browser via Apple Events.
/// macOS asks the user for Automation permission the first time.
enum ActiveBrowserTab {
    private static let scripts: [String: String] = [
        "com.google.Chrome": "tell application id \"com.google.Chrome\" to get URL of active tab of front window",
        "com.brave.Browser": "tell application id \"com.brave.Browser\" to get URL of active tab of front window",
        "com.microsoft.edgemac": "tell application id \"com.microsoft.edgemac\" to get URL of active tab of front window",
        "company.thebrowser.Browser": "tell application id \"company.thebrowser.Browser\" to get URL of active tab of front window",
        "com.apple.Safari": "tell application id \"com.apple.Safari\" to get URL of current tab of front window",
    ]

    @MainActor
    static func url(in app: NSRunningApplication?) -> Result<URL?, DocumentIssue> {
        guard let app, let bundleID = app.bundleIdentifier, let source = scripts[bundleID] else {
            return .success(nil)
        }
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 {
            return .failure(.browserAccessDenied(appName: app.localizedName ?? "your browser"))
        }
        return .success(result?.stringValue.flatMap(URL.init(string:)))
    }
}
