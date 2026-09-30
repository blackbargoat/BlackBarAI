import AppKit

/// A document the user has open somewhere else (for now: a Google Doc in a browser tab).
struct DocumentRef: Equatable {
    let id: String
    let url: URL
    var title: String?
}

struct DocumentSnapshot {
    let ref: DocumentRef
    let title: String
    let text: String
}

enum DocumentIssue: Error, Equatable {
    /// macOS Automation permission for the browser was denied.
    case browserAccessDenied(appName: String)
}

/// Everything the agent needs from "the document the user is working in".
/// The UI and chat only talk to this protocol, so new sources (a Chrome
/// extension bridge, Pages, Word, ...) plug in without touching the interface.
@MainActor
protocol DocumentContextProvider: AnyObject {
    /// Which document is in front in `app`, if any. Cheap; called when the bar gains focus.
    func detectActiveDocument(in app: NSRunningApplication?) -> Result<DocumentRef?, DocumentIssue>
    func title(of ref: DocumentRef) async throws -> String
    /// Full current text of the document.
    func snapshot(of ref: DocumentRef) async throws -> DocumentSnapshot
    /// Adds text to the end of the document.
    func append(_ text: String, to ref: DocumentRef) async throws
}

// Not implemented yet, on purpose. The Google Docs REST API cannot see the user's
// cursor or selection; that lives only in the browser tab. Reading or replacing
// the *selection* needs a bridge running inside the page (a Chrome extension or
// an Apps Script sidebar) that talks to BlackBarAI over a localhost socket. When
// that exists, it conforms to this protocol and the bar gets selection actions.
@MainActor
protocol DocumentSelectionBridge: AnyObject {
    func selectedText(in ref: DocumentRef) async throws -> String?
    func replaceSelection(in ref: DocumentRef, with text: String) async throws
}
