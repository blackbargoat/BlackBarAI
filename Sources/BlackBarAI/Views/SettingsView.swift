import ServiceManagement
import SwiftUI

/// BlackBar settings: black, boxed sections, BoxText lettering.
struct SettingsView: View {
    let model: AppModel
    @Bindable var google: GoogleAuth
    @Bindable var prefs: Preferences

    @State private var provider = ChatProvider.selected
    @State private var geminiKey = ""
    @State private var apiKey = ""
    @State private var keySaved = false
    @State private var clientSecret = ""
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                modelSection
                barSection
                shortcutsSection
                inBarSection
                googleSection
                generalSection
                BoxText(text: "BLACKBAR.AI", size: 7, color: BoxStyle.faint, tracking: 0.6)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 28)
            .padding(.top, 44)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.never)
        .frame(width: 580)
        .frame(minHeight: 600)
        .background(BoxStyle.background)
        .environment(\.colorScheme, .dark)
        .onAppear {
            apiKey = Credentials.anthropicAPIKey ?? ""
            geminiKey = Credentials.geminiAPIKey ?? ""
            clientSecret = google.clientSecret
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            BoxText(text: "BLACKBAR.", size: 34, color: .white, stroke: 0.12)
            HStack(spacing: 14) {
                BoxText(text: "SETTINGS", size: 8, color: BoxStyle.muted, tracking: 0.6)
                Rectangle().fill(BoxStyle.lineStrong).frame(height: 1)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: Sections

    private var modelSection: some View {
        BoxSection(index: 1, title: "MODEL") {
            BoxSegmented(options: ChatProvider.allCases.map { ($0.displayName, $0) }, selection: $provider)
                .onChange(of: provider) { ChatProvider.selected = provider; keySaved = false }
            if provider == .gemini {
                BoxField(placeholder: "Gemini API key", text: $geminiKey, secure: true)
                Text("\(GeminiClient.model) · key from aistudio.google.com/apikey")
                    .font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.muted)
            } else {
                BoxField(placeholder: "sk-ant-…", text: $apiKey, secure: true)
                Text("\(ClaudeClient.model) · key from console.anthropic.com")
                    .font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.muted)
            }
            HStack(spacing: 12) {
                BoxButton(title: "SAVE KEY", filled: true,
                          isEnabled: !(provider == .gemini ? geminiKey : apiKey).trimmingCharacters(in: .whitespaces).isEmpty) {
                    if provider == .gemini { Credentials.geminiAPIKey = geminiKey } else { Credentials.anthropicAPIKey = apiKey }
                    keySaved = true
                }
                if keySaved { BoxText(text: "SAVED", size: 7.5, color: BoxStyle.ok, tracking: 0.5, stroke: 0.15) }
            }
        }
    }

    private var barSection: some View {
        BoxSection(index: 2, title: "BAR") {
            BoxRow(label: "BAR HEIGHT") {
                BoxSlider(value: barHeight, range: Double(PanelController.minBarHeight)...120) { "\(Int($0)) PT" }
            }
            BoxRow(label: "TEXT BOX POSITION") {
                BoxSlider(value: boxPosition, range: 0...1) { value in
                    switch value {
                    case ..<0.01: return "LEFT"
                    case 0.99...: return "RIGHT"
                    case 0.49...0.51: return "CENTER"
                    default: return "\(Int((value * 100).rounded()))%"
                    }
                }
            }
            BoxRow(label: "TEXT SIZE") {
                BoxSlider(value: $prefs.fontSize, range: Preferences.fontSizeRange, step: 0.5) { String(format: "%.1f PT", $0) }
            }
            BoxRow(label: "TRUE BLACKOUT", detail: "Text and cursor turn the bar's black. Select text to see it.") {
                BoxToggle(isOn: $prefs.trueBlackout)
            }
        }
    }

    private var shortcutsSection: some View {
        BoxSection(index: 3, title: "SHORTCUTS") {
            BoxRow(label: "SHOW / HIDE") { ShortcutRecorder(combo: $prefs.showHideKey, prefs: prefs) }
            BoxRow(label: "BLACKOUT") { ShortcutRecorder(combo: $prefs.blackoutKey, prefs: prefs) }
            BoxRow(label: "SETTINGS") { ShortcutRecorder(combo: $prefs.settingsKey, prefs: prefs) }
            HStack {
                Text("Click a key, press the new shortcut. Esc cancels.")
                    .font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.muted)
                Spacer()
                BoxButton(title: "RESET") { prefs.resetShortcuts() }
            }
        }
    }

    private var inBarSection: some View {
        BoxSection(index: 4, title: "IN THE BAR") {
            BoxRow(label: "CLEAR + BACK TO DOC") { KeyCap(keys: "esc") }
            BoxRow(label: "TRY AGAIN") { KeyCap(keys: "⌘R") }
            BoxRow(label: "COPY EVERYTHING") { KeyCap(keys: "⌘A  ⌘C") }
            BoxRow(label: "COPY LAST ANSWER") { KeyCap(keys: "⇧⌘C") }
            BoxRow(label: "ADD ANSWER TO DOC") { KeyCap(keys: "⇧⌘D") }
            BoxRow(label: "STOP ANSWERING") { KeyCap(keys: "⌘.") }
            BoxRow(label: "CLEAR CONVERSATION") { KeyCap(keys: "⌘K") }
        }
    }

    private var googleSection: some View {
        BoxSection(index: 5, title: "GOOGLE DOCS") {
            if google.isConnected {
                BoxRow(label: "CONNECTED") {
                    BoxButton(title: "DISCONNECT", danger: true) { google.disconnect() }
                }
                if case .browserAccessDenied(let app) = model.documentIssue {
                    BoxButton(title: "ALLOW BROWSER ACCESS") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                    Text("BlackBar needs permission to see which Doc is open in \(app).")
                        .font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.muted)
                }
            } else {
                BoxField(placeholder: "OAuth client ID", text: $google.clientID)
                BoxField(placeholder: "OAuth client secret", text: $clientSecret, secure: true)
                HStack(spacing: 12) {
                    BoxButton(title: google.isConnecting ? "WAITING FOR BROWSER" : "CONNECT",
                              filled: true, isEnabled: google.isConfigured && !google.isConnecting) {
                        google.clientSecret = clientSecret
                        Task {
                            await google.connect()
                            model.refreshActiveDocument()
                        }
                    }
                    if google.isConnecting { BoxButton(title: "CANCEL") { google.cancelConnect() } }
                }
                Text("""
                Uses your own Google OAuth client; nothing goes through a third party.
                1  Google Cloud Console: new project, enable the Google Docs API.
                2  OAuth consent screen: External, add yourself as a test user.
                3  Credentials → OAuth client ID → Desktop app. Paste ID + secret.
                """)
                .font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            }
            if let error = google.lastError {
                Text(error).font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.danger)
            }
        }
    }

    private var generalSection: some View {
        BoxSection(index: 6, title: "GENERAL") {
            BoxRow(label: "OPEN AT LOGIN") {
                BoxToggle(isOn: $openAtLogin)
            }
            .onChange(of: openAtLogin) { setOpenAtLogin(openAtLogin) }
            if let loginError { Text(loginError).font(BoxStyle.mono(10)).foregroundStyle(BoxStyle.danger) }
        }
    }

    // MARK: Helpers

    /// Snaps to centre when dragged close to it, so centre is easy to hit.
    private var boxPosition: Binding<Double> {
        Binding(
            get: { prefs.boxPosition },
            set: { prefs.boxPosition = abs($0 - 0.5) < 0.03 ? 0.5 : $0 })
    }

    /// 0 in the model means "default height".
    private var barHeight: Binding<Double> {
        Binding(
            get: { Double(model.barHeight > 0 ? model.barHeight : PanelController.defaultBarHeight) },
            set: { model.barHeight = CGFloat($0.rounded()) })
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}
