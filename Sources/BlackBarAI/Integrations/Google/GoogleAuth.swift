import AppKit
import CryptoKit
import Foundation
import Observation

enum GoogleAuthError: LocalizedError {
    case notConfigured, notConnected, denied(String), stateMismatch, noRefreshToken, timedOut
    case tokenRequest(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Add a Google OAuth client ID in Settings first."
        case .notConnected: return "Google Docs isn't connected. Connect it in Settings."
        case .denied(let reason): return "Google sign-in was cancelled (\(reason))."
        case .stateMismatch: return "Google sign-in response didn't match this request."
        case .noRefreshToken: return "Google didn't return a refresh token. Remove BlackBarAI's access at myaccount.google.com/permissions and connect again."
        case .timedOut: return "Google sign-in timed out."
        case .tokenRequest(let message): return message
        }
    }
}

/// OAuth 2.0 for installed apps: authorization code + PKCE with a loopback
/// redirect (http://127.0.0.1:<port>). Uses the user's own "Desktop app" OAuth
/// client from Google Cloud. The refresh token lives in the SecretStore.
@MainActor @Observable
final class GoogleAuth {
    static let scopes = ["https://www.googleapis.com/auth/documents"]

    var clientID: String = UserDefaults.standard.string(forKey: "google.clientID") ?? "" {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespaces), forKey: "google.clientID") }
    }
    private(set) var isConnected = SecretStore.get("google.refreshToken") != nil
    private(set) var isConnecting = false
    var lastError: String?

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private var accessTokenExpiry = Date.distantPast
    @ObservationIgnored private var server: LoopbackServer?

    var clientSecret: String {
        get { SecretStore.get("google.clientSecret") ?? "" }
        set { SecretStore.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), for: "google.clientSecret") }
    }

    var isConfigured: Bool { !clientID.trimmingCharacters(in: .whitespaces).isEmpty }

    func connect() async {
        guard isConfigured else { lastError = GoogleAuthError.notConfigured.errorDescription; return }
        isConnecting = true
        lastError = nil
        defer {
            isConnecting = false
            server?.stop()
            server = nil
        }
        do {
            let verifier = Self.randomURLSafeString(bytes: 32)
            let challenge = Self.base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
            let state = Self.randomURLSafeString(bytes: 16)

            let server = try LoopbackServer()
            self.server = server
            let port = try await server.start()
            let redirectURI = "http://127.0.0.1:\(port)"

            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                .init(name: "client_id", value: clientID.trimmingCharacters(in: .whitespaces)),
                .init(name: "redirect_uri", value: redirectURI),
                .init(name: "response_type", value: "code"),
                .init(name: "scope", value: Self.scopes.joined(separator: " ")),
                .init(name: "code_challenge", value: challenge),
                .init(name: "code_challenge_method", value: "S256"),
                .init(name: "state", value: state),
                .init(name: "access_type", value: "offline"),
                .init(name: "prompt", value: "consent"),
            ]
            NSWorkspace.shared.open(components.url!)

            let callback = try await server.waitForCallback(timeout: 300)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
            if let error = value("error") { throw GoogleAuthError.denied(error) }
            guard value("state") == state else { throw GoogleAuthError.stateMismatch }
            guard let code = value("code") else { throw GoogleAuthError.denied("no code returned") }

            let token = try await tokenRequest([
                "grant_type": "authorization_code",
                "code": code,
                "redirect_uri": redirectURI,
                "code_verifier": verifier,
            ])
            guard let refresh = token.refreshToken else { throw GoogleAuthError.noRefreshToken }
            SecretStore.set(refresh, for: "google.refreshToken")
            accessToken = token.accessToken
            accessTokenExpiry = Date().addingTimeInterval(token.expiresIn)
            isConnected = true
        } catch {
            lastError = error.localizedDescription
        }
    }

    func cancelConnect() {
        server?.cancel()
    }

    func disconnect() {
        if let refresh = SecretStore.get("google.refreshToken") {
            // Best effort: revoke on Google's side too.
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncode(["token": refresh])
            URLSession.shared.dataTask(with: request).resume()
        }
        SecretStore.set(nil, for: "google.refreshToken")
        accessToken = nil
        accessTokenExpiry = .distantPast
        isConnected = false
    }

    /// A non-expired access token, refreshing it if needed.
    func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let refresh = SecretStore.get("google.refreshToken") else {
            isConnected = false
            throw GoogleAuthError.notConnected
        }
        let token = try await tokenRequest(["grant_type": "refresh_token", "refresh_token": refresh])
        accessToken = token.accessToken
        accessTokenExpiry = Date().addingTimeInterval(token.expiresIn)
        return token.accessToken
    }

    func invalidateAccessToken() {
        accessToken = nil
    }

    // MARK: Token endpoint

    private struct TokenResponse {
        let accessToken: String
        let refreshToken: String?
        let expiresIn: TimeInterval
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var fields = fields
        fields["client_id"] = clientID.trimmingCharacters(in: .whitespaces)
        if !clientSecret.isEmpty { fields["client_secret"] = clientSecret }

        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode(fields)

        let (data, response) = try await URLSession.shared.data(for: request)
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200, let access = json["access_token"] as? String else {
            let description = json["error_description"] as? String ?? json["error"] as? String ?? "Google token request failed."
            if json["error"] as? String == "invalid_grant" {
                SecretStore.set(nil, for: "google.refreshToken")
                isConnected = false
            }
            throw GoogleAuthError.tokenRequest(description)
        }
        return TokenResponse(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresIn: (json["expires_in"] as? Double) ?? 3000)
    }

    // MARK: Helpers

    private static func formEncode(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }

    private static func randomURLSafeString(bytes count: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return base64URL(Data(bytes))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
