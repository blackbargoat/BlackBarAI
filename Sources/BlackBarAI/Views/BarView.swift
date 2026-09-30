import AppKit
import SwiftUI

/// The bar: black and silent, with an invisible input in the middle (no box drawn;
/// only your text and the cursor show). After you send, the
/// answer streams into that same box; scroll inside it to read line by line.
/// Typing covers it with your next question; the conversation stays until Esc. The bar never changes height on
/// its own; drag the top edge to resize it.
struct BarView: View {
    @Bindable var model: AppModel
    @FocusState private var inputFocused: Bool

    private static let boxWidth: CGFloat = 560

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.bar
                // Placed along the bar by Settings → Text box position.
                let margin: CGFloat = 16
                let width = min(Self.boxWidth, max(0, geo.size.width - 2 * margin))
                let free = max(0, geo.size.width - 2 * margin - width)
                box(height: max(12, geo.size.height - 6))
                    .frame(width: width)
                    .padding(.leading, margin + free * model.prefs.boxPosition)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .overlay(alignment: .top) {
            EdgeResizeHandle { model.resizeBar(toTopEdge: $0) }
        }
        .background(shortcuts)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.focusRequest) { inputFocused = true }
    }

    private func box(height: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            TextField("", text: $model.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: model.prefs.fontSize))
                .foregroundStyle(Color(nsColor: model.prefs.textColor))
                .tint(Color(nsColor: model.prefs.caretColor))
                .lineLimit(1...max(1, Int((height - 6) / (model.prefs.fontSize * 1.3))))
                .focused($inputFocused)
                .onSubmit(submit)
                .padding(.horizontal, 11)

            if model.replyIsInBox {
                TranscriptView(messages: model.chat.messages, isSelected: model.isReplySelected,
                               revealed: model.revealedMessages, onReveal: model.toggleReveal,
                               scrollLine: model.replyScrollLine, prefs: model.prefs)
                    .contentShape(Rectangle())
                    .onTapGesture { inputFocused = true }
            }
        }
        .frame(height: height)
        .clipped()
        // ⌥Space: nothing but black, instantly (no animation).
        .opacity(model.isBlanked ? 0 : 1)
        .animation(nil, value: model.isBlanked)
        .contentShape(Rectangle())
        .onTapGesture { inputFocused = true }
    }

    /// Invisible keyboard shortcuts (no buttons on screen).
    private var shortcuts: some View {
        ZStack {
            Button("", action: model.clearConversation).keyboardShortcut("k", modifiers: .command)
            Button("", action: model.chat.stop).keyboardShortcut(".", modifiers: .command)
            Button("", action: model.retryLastQuestion).keyboardShortcut("r", modifiers: .command)
            Button("", action: model.copyLatestReply).keyboardShortcut("c", modifiers: [.command, .shift])
            Button("", action: model.appendLatestReplyToDocument).keyboardShortcut("d", modifiers: [.command, .shift])
        }
        .opacity(0)
        .allowsHitTesting(false)
    }

    private func submit() {
        if model.send(model.draft) { model.draft = "" }
    }
}

/// The whole conversation, scrollable inside the input box, until Esc wipes
/// it. Each new answer is brought into view once (its first line at the top);
/// after that you scroll at your own pace, up for earlier questions and answers.
private struct TranscriptView: View {
    let messages: [ChatStore.Message]
    let isSelected: Bool
    let revealed: Set<UUID>
    let onReveal: (UUID) -> Void
    /// Line of the latest answer to bring to the top (demo mode).
    let scrollLine: Int
    let prefs: Preferences

    private var latestReplyID: UUID? { messages.last(where: { $0.role == .assistant })?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages) { message in
                        MessageLines(message: message, isSelected: isSelected || revealed.contains(message.id), prefs: prefs)
                            .contentShape(Rectangle())
                            // Double-click a message to highlight (reveal) it; again to hide.
                            .onTapGesture(count: 2) { onReveal(message.id) }
                    }
                }
                .font(.system(size: prefs.fontSize))
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.never)
            .background(Theme.bar)
            .onAppear { showLatestAnswer(proxy, line: 0, animated: false) }
            .onChange(of: messages.count) { showLatestAnswer(proxy, line: 0, animated: false) }
            .onChange(of: scrollLine) { showLatestAnswer(proxy, line: scrollLine, animated: true) }
        }
    }

    private func showLatestAnswer(_ proxy: ScrollViewProxy, line: Int, animated: Bool) {
        guard let id = latestReplyID else { return }
        let target = MessageLines.lineID(id, line)
        if animated {
            withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(target, anchor: .top) }
        } else {
            proxy.scrollTo(target, anchor: .top)
        }
    }
}

/// One message, split into lines so the box can scroll a line at a time.
private struct MessageLines: View {
    let message: ChatStore.Message
    let isSelected: Bool
    let prefs: Preferences

    static func lineID(_ id: UUID, _ line: Int) -> String { "\(id.uuidString)-\(line)" }

    private var lines: [String] {
        message.text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private var color: Color {
        if isSelected { return prefs.trueBlackout ? .black : Color(white: 0.45) }
        return Color(nsColor: message.role == .user ? prefs.softTextColor : prefs.textColor)
    }

    /// In True Blackout the only way to see text is to select it, like a real
    /// text selection: the system highlight colour behind black text.
    private var selectionBackground: Color {
        guard isSelected else { return .clear }
        return prefs.trueBlackout ? Color(nsColor: .selectedTextBackgroundColor) : Theme.barSelection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if message.text.isEmpty && message.isStreaming && message.errorText == nil {
                if prefs.trueBlackout {
                    // Invisible like everything else; double-click to check on it.
                    Text("loading...")
                        .foregroundStyle(color)
                        .background(selectionBackground)
                        .id(Self.lineID(message.id, 0))
                } else {
                    ProgressView().controlSize(.mini).tint(Theme.barTextSoft).opacity(0.6)
                        .id(Self.lineID(message.id, 0))
                }
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                Text(Self.render(line))
                    .foregroundStyle(color)
                    .background(selectionBackground)
                    .id(Self.lineID(message.id, index))
            }
            if let error = message.errorText {
                Text((prefs.trueBlackout ? "failed · " : "") + error + "   ⌘R to try again")
                    .foregroundStyle(prefs.trueBlackout ? .black : (isSelected ? Color(white: 0.6) : Theme.barError))
                    .background(selectionBackground)
                    .id(Self.lineID(message.id, max(lines.count, 1)))
            }
            if let note = message.note {
                Text(note).foregroundStyle(color).background(selectionBackground)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func render(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Invisible strip along the bar's top edge that resizes it vertically.
/// Uses the screen-space mouse position so the math stays stable while the
/// window itself changes size.
struct EdgeResizeHandle: View {
    let onDrag: (CGFloat) -> Void

    var body: some View {
        Color.clear
            .frame(height: 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(DragGesture(minimumDistance: 1).onChanged { _ in
                onDrag(NSEvent.mouseLocation.y)
            })
    }
}
