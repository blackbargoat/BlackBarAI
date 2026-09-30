import Foundation

struct GoogleAPIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

/// Thin wrapper over the Google Docs REST API (v1).
struct GoogleDocsClient {
    let accessToken: String
    private static let base = URL(string: "https://docs.googleapis.com/v1/documents/")!

    func title(documentID: String) async throws -> String {
        let json = try await get(documentID: documentID, fields: "title")
        return json["title"] as? String ?? "Untitled document"
    }

    func document(documentID: String) async throws -> (title: String, text: String) {
        let json = try await get(documentID: documentID, fields: nil)
        let body = (json["body"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        return (json["title"] as? String ?? "Untitled document", Self.plainText(from: body))
    }

    /// Inserts `text` at the end of the document body in a new paragraph.
    func append(_ text: String, documentID: String) async throws {
        let body: [String: Any] = ["requests": [
            ["insertText": ["endOfSegmentLocation": [String: Any](), "text": "\n" + text]]
        ]]
        var request = URLRequest(url: Self.base.appendingPathComponent("\(documentID):batchUpdate"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await send(request)
    }

    // MARK: Private

    private func get(documentID: String, fields: String?) async throws -> [String: Any] {
        var components = URLComponents(url: Self.base.appendingPathComponent(documentID), resolvingAgainstBaseURL: false)!
        if let fields { components.queryItems = [.init(name: "fields", value: fields)] }
        return try await send(URLRequest(url: components.url!))
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String ?? "Google Docs API error \(status)."
            throw GoogleAPIError(status: status, message: message)
        }
        return json
    }

    private static func plainText(from content: [[String: Any]]) -> String {
        var out = ""
        for element in content {
            if let paragraph = element["paragraph"] as? [String: Any] {
                for run in paragraph["elements"] as? [[String: Any]] ?? [] {
                    out += (run["textRun"] as? [String: Any])?["content"] as? String ?? ""
                }
            } else if let table = element["table"] as? [String: Any] {
                for row in table["tableRows"] as? [[String: Any]] ?? [] {
                    let cells = (row["tableCells"] as? [[String: Any]] ?? []).map {
                        plainText(from: $0["content"] as? [[String: Any]] ?? []).trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                    out += cells.joined(separator: "\t") + "\n"
                }
            } else if let toc = element["tableOfContents"] as? [String: Any] {
                out += plainText(from: toc["content"] as? [[String: Any]] ?? [])
            }
        }
        return out
    }
}
