import Foundation
import Observation

@MainActor @Observable
final class ChatStore {
    enum Role { case user, assistant }

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        var text: String
        /// What was actually sent to Claude (includes attached document text).
        var apiText: String
        /// Title of the Google Doc attached to this message, if any.
        var attachment: String?
        var isStreaming = false
        var errorText: String?
        var note: String?
    }

    typealias DocumentLoader = () async throws -> DocumentSnapshot

    static let systemPrompt = """
    You are BlackBarAI, an assistant that lives in a slim bar at the bottom of the user's Mac screen \
    while they work in their own documents, usually Google Docs. The user reads your replies in a \
    small panel, so be concise and get straight to the point.

    When the user asks you to write, rewrite, continue, or edit text, reply with only the finished \
    text, ready to paste, with no preamble or closing remarks, unless they ask for commentary.

    You cannot see the user's screen. You only see a document when its text is included in the \
    message inside <document> tags. If they refer to a document you haven't been given, tell them \
    to turn on the document chip in the bar.
    """

    private(set) var messages: [Message] = []
    private(set) var isResponding = false
    @ObservationIgnored private var task: Task<Void, Never>?

    func send(_ text: String, documentTitle: String?, loadDocument: DocumentLoader?) {
        guard !isResponding else { return }
        let user = Message(role: .user, text: text, apiText: text, attachment: documentTitle)
        let reply = Message(role: .assistant, text: "", apiText: "", isStreaming: true)
        messages.append(user)
        messages.append(reply)
        isResponding = true
        task = Task { [weak self] in
            await self?.respond(userID: user.id, replyID: reply.id, loadDocument: loadDocument)
            self?.finish(replyID: reply.id)
        }
    }

    func stop() { task?.cancel() }

    /// Removes the most recent question and its reply; returns the question text.
    func removeLastExchange() -> String? {
        guard !isResponding, let index = messages.lastIndex(where: { $0.role == .user }) else { return nil }
        let text = messages[index].text
        messages.removeSubrange(index...)
        return text
    }

    func setNote(_ note: String, on id: UUID) {
        update(id) { $0.note = note }
    }

    func clear() {
        stop()
        messages.removeAll()
    }

    private func respond(userID: UUID, replyID: UUID, loadDocument: DocumentLoader?) async {
        let provider = ChatProvider.selected
        guard let client = provider.makeClient() else {
            update(replyID) { $0.errorText = "Add your \(provider.displayName) API key in Settings (⌃⌥,) to start." }
            return
        }
        if let loadDocument {
            do {
                let doc = try await loadDocument()
                update(userID) {
                    $0.attachment = doc.title
                    $0.apiText = "<document title=\"\(doc.title)\" source=\"Google Docs\">\n\(doc.text)\n</document>\n\n\($0.text)"
                }
            } catch {
                update(replyID) { $0.errorText = "Couldn't read the Google Doc: \(error.localizedDescription)" }
                return
            }
        }

        do {
            for try await event in client.stream(system: Self.systemPrompt, messages: history(through: userID)) {
                switch event {
                case .text(let chunk):
                    update(replyID) { $0.text += chunk }
                case .stopped(reason: "refusal"):
                    update(replyID) { $0.errorText = "The model declined this request." }
                case .stopped(reason: "max_tokens"):
                    update(replyID) { $0.note = "Reply hit the length limit." }
                case .stopped:
                    break
                }
            }
        } catch {
            if error is CancellationError || (error as? URLError)?.code == .cancelled {
                update(replyID) { $0.note = "Stopped." }
            } else {
                update(replyID) { $0.errorText = error.localizedDescription }
            }
        }
    }

    private func finish(replyID: UUID) {
        update(replyID) {
            $0.isStreaming = false
            $0.apiText = $0.text
        }
        isResponding = false
        task = nil
    }

    /// Earlier completed exchanges plus the new user turn. Exchanges whose reply
    /// failed are dropped so the history always alternates user/assistant.
    private func history(through userID: UUID) -> [[String: String]] {
        var turns: [[String: String]] = []
        var i = 0
        while i < messages.count {
            let message = messages[i]
            if message.id == userID {
                turns.append(["role": "user", "content": message.apiText])
                break
            }
            if message.role == .user, i + 1 < messages.count {
                let reply = messages[i + 1]
                if reply.role == .assistant, reply.errorText == nil, !reply.apiText.isEmpty {
                    turns.append(["role": "user", "content": message.apiText])
                    turns.append(["role": "assistant", "content": reply.apiText])
                    i += 2
                    continue
                }
            }
            i += 1
        }
        return turns
    }

    private func update(_ id: UUID, _ change: (inout Message) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        change(&messages[index])
    }
}
