# BlackBar

**An AI assistant that lives in a thin black bar at the bottom of your Mac screen.**

Keep working in Google Docs (or anything else). Click the bar, ask, and read the answer right
there, without switching apps, opening a browser tab, or losing your place.

[![BlackBar demo: True Blackout keeps the bar black while you type and read, and ⌥B blanks it instantly](docs/blackbar-demo.gif)](docs/blackbar-demo.mp4)

<sub>**True Blackout:** your question and the answer are drawn in the bar's own black, so anyone glancing at your screen sees an empty bar. Peek with ⌘A, double-click the answer to reveal it, and ⌥B blanks the bar instantly. The answer shown is real Gemini output. [Watch in HD (MP4)](docs/blackbar-demo.mp4)</sub>

- **Always there.** Floats above every app and every Space, including full-screen apps.
- **Never steals focus.** You can type in the bar while your document stays the front app. Esc hands the keyboard back.
- **Reads your Google Doc.** It sees which Doc is open in your browser and can read it and add answers to the end of it.
- **Your keys, your data.** Bring your own Gemini (free) or Claude API key. There's no server, account or tracking. Requests go straight from your Mac to the model provider.
- **True Blackout.** Turn it on in Settings and everything in the bar, including your question, the answer and the cursor, is drawn in the bar's own black. Only you can read it: ⌘A to peek, double-click an answer to reveal it. ⌥B blanks the bar instantly.

Works on macOS 14 (Sonoma) or newer, Apple Silicon and Intel.

---

## Install

1. Download **`BlackBarAI-<version>.dmg`** from the [latest release](../../releases/latest).
2. Open it and drag **BlackBarAI** into **Applications**.
3. Open BlackBarAI from Applications.

**First launch:** BlackBar isn't signed with a paid Apple Developer ID, so macOS asks once:

- If you see *"Apple could not verify BlackBarAI…"*, click **Done**.
- Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to BlackBarAI. Confirm with your password.
- On older macOS: right-click BlackBarAI → **Open** → **Open**.

If you'd rather not trust a downloaded binary, [build it yourself](#build-from-source). It takes about a minute.

## Set up (about 1 minute)

Settings opens by itself the first time.

1. Get an API key:
   - **Gemini (free):** https://aistudio.google.com/apikey
   - **or Claude:** https://console.anthropic.com
2. Paste it into **1 · MODEL**, click **SAVE KEY**, and close Settings.
3. Click the black bar at the bottom of your screen, type a question, and press **Return**.

Keys are stored in `~/Library/Application Support/BlackBarAI/secrets.json`, readable only by
your user account (permissions `0600`). They are never sent anywhere except the provider you picked.

## Shortcuts

| Shortcut | What it does |
|---|---|
| ⌃⌥Space | Show / hide the bar (from anywhere) |
| ⌥B | Black out the bar instantly (press again to bring it back) |
| ⌃⌥, | Open Settings |
| Return | Send |
| Esc | Clear and hand focus back to your document |
| ⌘R | Ask the last question again |
| ⌘. | Stop the answer |
| ⌘K | Clear the conversation |
| ⇧⌘C | Copy the last answer |
| ⌘A, ⌘C | Copy everything |
| ⇧⌘D | Add the last answer to the end of your Google Doc |

The global shortcuts can be changed in **Settings → 3 · SHORTCUTS**. The **▭** icon in the menu
bar has Show/Hide, Settings and Quit.

## Google Docs (optional)

BlackBar can read the Google Doc you have open and append answers to it. Google requires every
app that touches your Docs to use an OAuth client, so you create your own. It's free, and it
means your documents are only ever shared between your Mac and your Google account.

1. Go to [Google Cloud Console](https://console.cloud.google.com/) and create a project (any name).
2. **APIs & Services → Library** → enable the **Google Docs API**.
3. **APIs & Services → OAuth consent screen** → External, fill in the app name and your email,
   and add yourself under **Test users**.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID** → application type
   **Desktop app**.
5. Copy the **client ID** and **client secret** into **Settings → 5 · GOOGLE DOCS** and click **CONNECT**.
   Your browser opens and you sign in. When it says *"BlackBarAI is connected"*, you're done.
6. The first time you ask about a Doc, macOS asks whether BlackBar may control your browser.
   Click **OK**. BlackBar only reads the address of the front tab to find which Doc is open,
   never the page content.

Supported browsers: Chrome, Safari, Arc, Brave and Edge.

| Capability | Status |
|---|---|
| Know which Doc is open | ✅ via the front browser tab's URL |
| Read the whole document | ✅ Google Docs API |
| Summarize / continue / rewrite / answer questions about it | ✅ |
| Add an answer to the end of the Doc | ✅ (⇧⌘D) |
| Read or replace the *selected* text | ❌ not yet. The Docs API can't see your selection; this needs a browser-extension bridge (see `DocumentSelectionBridge`) |

## Build from source

Requires Xcode 15+ or the Swift 5.10+ command-line tools.

```sh
git clone https://github.com/blackbargoat/BlackBarAI.git
cd BlackBarAI
./scripts/build-app.sh          # → build/BlackBarAI.app (for this Mac)
open build/BlackBarAI.app
```

To make a shareable universal `.dmg` and `.zip`:

```sh
./scripts/package.sh            # → dist/BlackBarAI-<version>.dmg and .zip
```

If you have a *Developer ID Application* certificate and a notarytool profile named `BlackBarAI`,
`package.sh` signs and notarizes automatically, so users can open it with a plain double-click.
Otherwise it builds ad-hoc signed (users click *Open Anyway* once).

## Uninstall

Quit from the **▭** menu-bar icon, delete BlackBarAI from Applications, and optionally remove its data:

```sh
rm -rf ~/Library/Application\ Support/BlackBarAI
defaults delete app.blackbarai.BlackBarAI
```

## Models

- **Gemini:** `gemini-3.6-flash`, falling back to other Flash models when Google reports overload. The free tier has a small daily request limit.
- **Claude:** `claude-opus-5-5`, streamed, with server-side refusal fallbacks.

Switch between them in **Settings → 1 · MODEL**.

## How it's built

A native Swift / AppKit + SwiftUI app with no dependencies.

```
Sources/BlackBarAI/
  App/            main, AppDelegate (menu bar item, hotkeys, settings), HotKey (Carbon), Theme
  Panels/         AgentPanel (non-activating floating NSPanel), PanelController (bottom anchoring)
  Views/          BarView, SettingsView, BoxFont / BoxControls (the boxy lettering), ShortcutRecorder
  Agent/          AppModel, ChatStore, GeminiClient + ClaudeClient (SSE streaming), SecretStore, Preferences
  Integrations/   DocumentContextProvider protocol, ActiveBrowserTab (Apple Events)
    Google/       GoogleAuth (OAuth 2.0 + PKCE, loopback redirect), LoopbackServer, GoogleDocsClient
```

New document sources implement `DocumentContextProvider`; the UI only talks to that protocol.

The demo video is rendered from `demo-video/scene.html` (a virtual Mac recreating the bar) by
`demo-video/record.mjs`; `script.json` holds the real model answers it shows.

## Privacy

BlackBar has no backend. It talks only to:

- the model provider you chose (`generativelanguage.googleapis.com` or `api.anthropic.com`)
- Google's OAuth and Docs APIs, if you connect Google Docs

Your conversation lives in memory and is gone when you clear it or quit.

## License

[MIT](LICENSE)
