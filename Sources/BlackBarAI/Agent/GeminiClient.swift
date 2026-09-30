import Foundation

struct GeminiError: LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? {
        switch status {
        case 400 where message.localizedCaseInsensitiveContains("api key"),
             401, 403:
            return "Your Gemini API key was rejected. Check it in Settings (⌃⌥,)."
        case 429: return "Gemini rate limit or quota reached. Try again in a moment."
        default: return message
        }
    }
}

/// Streams from the Gemini API (generativelanguage.googleapis.com) over SSE.
struct GeminiClient: ChatModelClient {
    static let model = "gemini-3.6-flash"
    /// Tried in order when a model is overloaded or temporarily unavailable.
    static let fallbackModels = ["gemini-flash-latest", "gemini-3.5-flash"]

    let apiKey: String

    func stream(system: String, messages: [[String: String]]) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let body: [String: Any] = [
                        "systemInstruction": ["parts": [["text": system]]],
                        "contents": messages.map { turn in
                            ["role": turn["role"] == "assistant" ? "model" : "user",
                             "parts": [["text": turn["content"] ?? ""]]]
                        },
                    ]
                    let bodyData = try JSONSerialization.data(withJSONObject: body)
                    let bytes = try await Self.openStream(body: bodyData, apiKey: apiKey)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        if let error = chunk["error"] as? [String: Any] {
                            throw GeminiError(status: error["code"] as? Int ?? 0, message: error["message"] as? String ?? "Gemini stream failed.")
                        }
                        if (chunk["promptFeedback"] as? [String: Any])?["blockReason"] != nil {
                            continuation.yield(.stopped(reason: "refusal"))
                        }
                        guard let candidate = (chunk["candidates"] as? [[String: Any]])?.first else { continue }
                        let parts = (candidate["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
                        for part in parts where part["thought"] as? Bool != true {
                            if let text = part["text"] as? String, !text.isEmpty { continuation.yield(.text(text)) }
                        }
                        if let finish = candidate["finishReason"] as? String {
                            continuation.yield(.stopped(reason: Self.normalize(finish)))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Opens the SSE stream, moving down the model list while Google reports
    /// overload (429/5xx) or the model is briefly unavailable (404).
    private static func openStream(body: Data, apiKey: String) async throws -> URLSession.AsyncBytes {
        var lastError: Error = GeminiError(status: 0, message: "Gemini is unavailable right now.")
        let chain = [model] + fallbackModels
        for (attempt, model) in (chain + chain).enumerated() {
            if attempt > 0 { try await Task.sleep(for: .milliseconds(500 * attempt)) }
            let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 600
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = body

            let (bytes, response) = try await URLSession.shared.bytes(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200 { return bytes }
            var data = Data()
            for try await byte in bytes { data.append(byte) }
            lastError = GeminiError(status: status, message: errorMessage(in: data) ?? "Gemini API error \(status).")
            guard status == 404 || status == 429 || status >= 500 else { throw lastError }
        }
        throw lastError
    }

    private static func normalize(_ finishReason: String) -> String {
        switch finishReason {
        case "STOP": return "end"
        case "MAX_TOKENS": return "max_tokens"
        case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": return "refusal"
        default: return finishReason
        }
    }

    private static func errorMessage(in data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data)
        let root = (object as? [String: Any]) ?? (object as? [[String: Any]])?.first
        return (root?["error"] as? [String: Any])?["message"] as? String
    }
}
