import Foundation
import Network

/// A one-shot HTTP listener on 127.0.0.1 that receives the OAuth redirect.
@MainActor
final class LoopbackServer {
    private let listener: NWListener
    private var callback: CheckedContinuation<URL, Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    /// Starts listening and returns the port the OS assigned.
    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            var resumed = false
            listener.stateUpdateHandler = { [listener] state in
                MainActor.assumeIsolated {
                    guard !resumed else { return }
                    switch state {
                    case .ready:
                        resumed = true
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    case .failed(let error):
                        resumed = true
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                MainActor.assumeIsolated { self?.handle(connection) }
            }
            listener.start(queue: .main)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            callback = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.resume(with: .failure(GoogleAuthError.timedOut))
            }
        }
    }

    func cancel() {
        resume(with: .failure(GoogleAuthError.denied("cancelled")))
    }

    func stop() {
        listener.cancel()
    }

    private func resume(with result: Result<URL, Error>) {
        guard let callback else { return }
        self.callback = nil
        callback.resume(with: result)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            MainActor.assumeIsolated {
                let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?
                    .components(separatedBy: "\r\n").first ?? ""
                let parts = requestLine.split(separator: " ")
                let path = parts.count > 1 ? String(parts[1]) : "/"
                let isCallback = path.contains("code=") || path.contains("error=")

                let body = isCallback
                    ? "<html><body style=\"font-family:-apple-system;background:#171717;color:#faf9f5;display:grid;place-items:center;height:90vh\"><p>BlackBarAI is connected. You can close this tab.</p></body></html>"
                    : ""
                let status = isCallback ? "200 OK" : "404 Not Found"
                let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })

                if isCallback, let url = URL(string: "http://127.0.0.1\(path)") {
                    self?.resume(with: .success(url))
                }
            }
        }
    }
}
