import Foundation

enum ClaudeError: LocalizedError {
    case api(status: Int, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .api(401, _): return "Your Anthropic API key was rejected. Check it in Settings."
        case .api(429, _): return "Rate limited by the Claude API. Try again in a moment."
        case .api(_, let message): return message
        case .badResponse: return "Unexpected response from the Claude API."
        }
    }
}

/// Streams a Messages API response over SSE (raw HTTP: there is no official Swift SDK).
struct ClaudeClient: ChatModelClient {
    static let model = "claude-opus-5-5"
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    let apiKey: String

    func stream(system: String, messages: [[String: String]]) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: Self.endpoint)
                    request.httpMethod = "POST"
                    request.timeoutInterval = 600
                    request.setValue("application/json", forHTTPHeaderField: "content-type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    // Server-side fallback: if a safety classifier declines, the API
                    // re-runs the request on Anthropic's recommended fallback model.
                    request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
                    let body: [String: Any] = [
                        "model": Self.model,
                        "max_tokens": 64000,
                        "stream": true,
                        "system": system,
                        "messages": messages,
                        "fallbacks": "default",
                    ]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ClaudeError.badResponse }
                    guard http.statusCode == 200 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw ClaudeError.api(status: http.statusCode, message: Self.errorMessage(in: data) ?? "Claude API error \(http.statusCode).")
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let type = event["type"] as? String else { continue }
                        let delta = event["delta"] as? [String: Any]
                        switch type {
                        case "content_block_delta":
                            if delta?["type"] as? String == "text_delta", let text = delta?["text"] as? String {
                                continuation.yield(.text(text))
                            }
                        case "message_delta":
                            continuation.yield(.stopped(reason: delta?["stop_reason"] as? String))
                        case "error":
                            throw ClaudeError.api(status: 0, message: Self.errorMessage(in: data) ?? "The response stream failed.")
                        default:
                            break
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

    private static func errorMessage(in data: Data) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (object?["error"] as? [String: Any])?["message"] as? String
    }
}
