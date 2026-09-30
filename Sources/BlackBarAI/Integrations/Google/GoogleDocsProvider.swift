import AppKit

/// Google Docs as a document source: the browser tells us *which* doc is in
/// front; the Docs API (with the user's OAuth grant) reads and writes it.
@MainActor
final class GoogleDocsProvider: DocumentContextProvider {
    private let auth: GoogleAuth

    init(auth: GoogleAuth) {
        self.auth = auth
    }

    func detectActiveDocument(in app: NSRunningApplication?) -> Result<DocumentRef?, DocumentIssue> {
        ActiveBrowserTab.url(in: app).map { url in
            guard let url, let id = Self.documentID(in: url) else { return nil }
            return DocumentRef(id: id, url: url)
        }
    }

    func title(of ref: DocumentRef) async throws -> String {
        try await withClient { try await $0.title(documentID: ref.id) }
    }

    func snapshot(of ref: DocumentRef) async throws -> DocumentSnapshot {
        let doc = try await withClient { try await $0.document(documentID: ref.id) }
        return DocumentSnapshot(ref: ref, title: doc.title, text: doc.text)
    }

    func append(_ text: String, to ref: DocumentRef) async throws {
        try await withClient { try await $0.append(text, documentID: ref.id) }
    }

    /// Runs `call`, retrying once with a fresh token if Google says the token expired.
    private func withClient<T>(_ call: (GoogleDocsClient) async throws -> T) async throws -> T {
        do {
            return try await call(GoogleDocsClient(accessToken: try await auth.validAccessToken()))
        } catch let error as GoogleAPIError where error.status == 401 {
            auth.invalidateAccessToken()
            return try await call(GoogleDocsClient(accessToken: try await auth.validAccessToken()))
        }
    }

    /// docs.google.com/document/d/<id>/edit (or /document/u/1/d/<id>/...)  →  <id>
    static func documentID(in url: URL) -> String? {
        let parts = url.pathComponents
        guard url.host == "docs.google.com", parts.count > 1, parts[1] == "document",
              let d = parts.firstIndex(of: "d"), d + 1 < parts.count else { return nil }
        return parts[d + 1]
    }
}
