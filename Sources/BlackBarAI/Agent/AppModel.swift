import AppKit
import Observation

/// Shared state for the bar and settings.
@MainActor @Observable
final class AppModel {
    let chat = ChatStore()
    let google = GoogleAuth()
    let prefs = Preferences()
    @ObservationIgnored let documents: DocumentContextProvider

    // MARK: Layout

    /// Height of the idle bar in points (0 = default).
    var barHeight: CGFloat = UserDefaults.standard.double(forKey: "barHeight") {
        didSet {
            UserDefaults.standard.set(Double(barHeight), forKey: "barHeight")
            onLayoutChange?()
        }
    }
    /// Whether the input box is showing the latest reply (until you type again).
    var isShowingReply = false {
        didSet { if !isShowingReply { isReplySelected = false } }
    }
    /// Line of the reply scrolled to the top of the box (used by demo mode).
    var replyScrollLine = 0
    /// ⌥B blacks out the bar instantly; press again to bring it back.
    var isBlanked = false {
        didSet { if oldValue != isBlanked { onBlankChange?(isBlanked) } }
    }
    @ObservationIgnored var onBlankChange: ((Bool) -> Void)?
    /// Messages revealed by double-clicking them (shown highlighted, like a
    /// selection, which is how you read them in True Blackout).
    var revealedMessages: Set<UUID> = []
    /// ⌘A while the reply is showing selects all of it; ⌘C then copies it.
    var isReplySelected = false
    /// What's typed in the box. Typing replaces the reply shown there.
    var draft = "" {
        didSet { if !draft.isEmpty { isShowingReply = false } }
    }
    /// The conversation is on screen in the box (nothing typed over it). It
    /// stays until Esc, so you can scroll back through earlier answers.
    var replyIsInBox: Bool { draft.isEmpty && !chat.messages.isEmpty }
    /// Increment to move keyboard focus into the input field.
    var focusRequest = 0

    @ObservationIgnored var barBottomY: CGFloat = 0
    @ObservationIgnored var maxBarHeight: CGFloat = 600
    @ObservationIgnored var onLayoutChange: (() -> Void)?
    @ObservationIgnored var openSettings: (() -> Void)?
    @ObservationIgnored var returnFocus: (() -> Void)?

    // MARK: Document context

    var activeDocument: DocumentRef?
    var documentIssue: DocumentIssue?
    var includeDocument = true

    @ObservationIgnored private var lastExternalApp: NSRunningApplication?

    init() {
        documents = GoogleDocsProvider(auth: google)
        let ownID = Bundle.main.bundleIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != ownID {
            lastExternalApp = front
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != ownID else { return }
            MainActor.assumeIsolated { self?.lastExternalApp = app }
        }
    }

    // MARK: Actions

    func send(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !chat.isResponding else { return false }
        isShowingReply = true
        isBlanked = false

        var loader: ChatStore.DocumentLoader?
        let attached = includeDocument && google.isConnected ? activeDocument : nil
        if let ref = attached {
            let documents = documents
            loader = { try await documents.snapshot(of: ref) }
        }
        chat.send(trimmed, documentTitle: attached.map { $0.title ?? "Google Doc" }, loadDocument: loader)
        return true
    }

    /// Drag on the bar's top edge.
    func resizeBar(toTopEdge y: CGFloat) {
        barHeight = max(PanelController.minBarHeight, min(y - barBottomY, maxBarHeight))
    }

    func toggleBlank() {
        isBlanked.toggle()
        NSLog("BlackBarAI: blackout %@", isBlanked ? "on" : "off")
    }

    func toggleReveal(_ id: UUID) {
        if revealedMessages.contains(id) { revealedMessages.remove(id) } else { revealedMessages.insert(id) }
    }

    func clearConversation() {
        revealedMessages = []
        chat.clear()
        isShowingReply = false
    }

    func resetHeights() {
        barHeight = 0
    }

    func barDidGainFocus() {
        refreshActiveDocument()
    }

    var latestReply: ChatStore.Message? {
        chat.messages.last(where: { $0.role == .assistant })
    }

    /// ⌘R: ask the last question again (e.g. after the model failed).
    func retryLastQuestion() {
        guard let question = chat.removeLastExchange() else { return }
        _ = send(question)
    }

    /// Everything in the box, questions and answers, as plain text.
    var transcriptText: String {
        chat.messages.filter { !$0.text.isEmpty }.map(\.text).joined(separator: "\n\n")
    }

    func copyTranscript() {
        guard !transcriptText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
    }

    func copyLatestReply() {
        guard let reply = latestReply, !reply.text.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(reply.text, forType: .string)
    }

    func appendLatestReplyToDocument() {
        guard let reply = latestReply, !reply.text.isEmpty, !reply.isStreaming else { return }
        appendToDocument(reply)
    }

    func returnFocusToWorkspace() { returnFocus?() }

    func activateLastApp() {
        lastExternalApp?.activate()
    }

    func refreshActiveDocument() {
        guard google.isConnected else {
            activeDocument = nil
            return
        }
        switch documents.detectActiveDocument(in: lastExternalApp) {
        case .success(let ref?):
            documentIssue = nil
            guard ref.id != activeDocument?.id else { return }
            activeDocument = ref
            Task {
                guard let title = try? await documents.title(of: ref), activeDocument?.id == ref.id else { return }
                activeDocument?.title = title
            }
        case .success(nil):
            activeDocument = nil
            documentIssue = nil
        case .failure(let issue):
            activeDocument = nil
            documentIssue = issue
        }
    }

    var canAppendToDocument: Bool { google.isConnected && activeDocument != nil }

    func appendToDocument(_ message: ChatStore.Message) {
        guard let ref = activeDocument else { return }
        Task {
            do {
                try await documents.append(message.text, to: ref)
                chat.setNote("Added to “\(ref.title ?? "document")”", on: message.id)
            } catch {
                chat.setNote("Couldn't add to doc: \(error.localizedDescription)", on: message.id)
            }
        }
    }
}
