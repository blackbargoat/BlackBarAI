import AppKit

/// Scripted walkthrough for recording a launch demo. Everything happens in the
/// real app with a real model response; it only sets the bar's own state (no
/// synthetic keystrokes to other apps). Writes `demo-done` when finished so a
/// recording script knows when to continue.
@MainActor
struct DemoDirector {
    let model: AppModel
    let panels: PanelController

    static let doneMarker = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("BlackBarAI/demo-done")

    func run(first: String?, followUp: String?) async {
        try? FileManager.default.removeItem(at: Self.doneMarker)
        let first = first ?? "Give me 3 punchy opening lines for an essay about attention being the world's most valuable currency. One per line, no numbering."
        let followUp = followUp ?? "Make the second one shorter. Just the line."

        model.clearConversation()
        await pause(1.0)
        panels.focusInput()
        await pause(0.9)

        // 1. Ask, stream, then read it line by line.
        await ask(first)
        await pause(1.4)
        let lines = model.latestReply?.text.split(separator: "\n", omittingEmptySubsequences: true).count ?? 1
        for line in 1..<max(lines, 1) {
            model.replyScrollLine = line
            await pause(1.5)
        }
        await pause(0.8)

        // 2. Follow-up (the model remembers the conversation).
        await ask(followUp)
        await pause(1.6)

        // 3. ⌘A, ⌘C
        model.isReplySelected = true
        await pause(1.1)
        model.copyLatestReply()
        await pause(0.9)

        // 4. Esc: back to the document.
        panels.returnToWorkspace()
        FileManager.default.createFile(atPath: Self.doneMarker.path, contents: Data())
    }

    private func ask(_ question: String) async {
        for character in question {
            model.draft.append(character)
            await pause(character == " " ? 0.06 : Double.random(in: 0.03...0.07))
        }
        await pause(0.5)
        let text = model.draft
        if model.send(text) { model.draft = "" }
        model.replyScrollLine = 0
        await pause(0.3)
        while model.chat.isResponding { await pause(0.1) }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}
