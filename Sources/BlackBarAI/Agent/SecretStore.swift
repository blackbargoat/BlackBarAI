import Foundation

/// Secrets (API keys, Google refresh token) in a JSON file only the current
/// user can read: ~/Library/Application Support/BlackBarAI/secrets.json (0600).
///
/// Not the Keychain on purpose: BlackBarAI is ad-hoc signed, so the Keychain sees
/// every rebuild as a different app and blocks launch with a password prompt.
/// With a Developer ID signature, this can move back to the SecretStore.
enum SecretStore {
    private static let directory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BlackBarAI", isDirectory: true)
    private static let file = directory.appendingPathComponent("secrets.json")

    static func get(_ name: String) -> String? {
        read()[name]
    }

    static func set(_ value: String?, for name: String) {
        var secrets = read()
        if let value, !value.isEmpty { secrets[name] = value } else { secrets.removeValue(forKey: name) }
        write(secrets)
    }

    private static func read() -> [String: String] {
        guard let data = try? Data(contentsOf: file),
              let secrets = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { return [:] }
        return secrets
    }

    private static func write(_ secrets: [String: String]) {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let data = try? JSONSerialization.data(withJSONObject: secrets, options: [.prettyPrinted, .sortedKeys]) else { return }
        fm.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600])
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

enum Credentials {
    static var geminiAPIKey: String? {
        get { SecretStore.get("gemini.apiKey") ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] }
        set { SecretStore.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), for: "gemini.apiKey") }
    }

    static var anthropicAPIKey: String? {
        get { SecretStore.get("anthropic.apiKey") ?? ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"] }
        set { SecretStore.set(newValue?.trimmingCharacters(in: .whitespacesAndNewlines), for: "anthropic.apiKey") }
    }
}
