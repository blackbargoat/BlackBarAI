import Foundation

enum ChatEvent {
    case text(String)
    /// Normalized stop reason: "end", "max_tokens", "refusal", or a provider-specific value.
    case stopped(reason: String?)
}

/// A streaming chat model. History is plain text turns: role "user" / "assistant".
protocol ChatModelClient {
    func stream(system: String, messages: [[String: String]]) -> AsyncThrowingStream<ChatEvent, Error>
}

enum ChatProvider: String, CaseIterable, Identifiable {
    case gemini, claude
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .claude: return "Claude"
        }
    }

    static var selected: ChatProvider {
        get { ChatProvider(rawValue: UserDefaults.standard.string(forKey: "chatProvider") ?? "") ?? .gemini }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "chatProvider") }
    }

    /// A client for this provider, or nil when its API key is missing.
    func makeClient() -> ChatModelClient? {
        switch self {
        case .gemini:
            guard let key = Credentials.geminiAPIKey, !key.isEmpty else { return nil }
            return GeminiClient(apiKey: key)
        case .claude:
            guard let key = Credentials.anthropicAPIKey, !key.isEmpty else { return nil }
            return ClaudeClient(apiKey: key)
        }
    }
}
