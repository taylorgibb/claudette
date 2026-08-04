import Foundation
import Network

public final class OAuthCallbackServer: @unchecked Sendable {
    public struct Callback: Sendable, Equatable {
        public let code: String
        public let state: String?
    }

    public enum ServerError: Error, Equatable {
        case listenFailed
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "claudette.oauth.callback")
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Callback, Error>?
    private var connections: [NWConnection] = []
    private var stopped = false

    public init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw ServerError.listenFailed
        }
    }

    public func waitForCallback() async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { cont in
                lock.lock()
                if stopped {
                    lock.unlock()
                    cont.resume(throwing: CancellationError())
                    return
                }
                continuation = cont
                lock.unlock()

                listener.newConnectionHandler = { [weak self] connection in
                    self?.accept(connection)
                }
                listener.stateUpdateHandler = { [weak self] state in
                    if case .failed = state {
                        self?.finish(.failure(ServerError.listenFailed))
                    }
                }
                listener.start(queue: queue)
            }
        } onCancel: {
            finish(.failure(CancellationError()))
        }
    }

    public func stop() {
        finish(.failure(CancellationError()))
    }

    private func accept(_ connection: NWConnection) {
        lock.lock()
        connections.append(connection)
        lock.unlock()
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
            [weak self] data, _, _, _ in
            guard let self else { return }
            guard
                let data, let request = String(data: data, encoding: .utf8),
                let callback = Self.parse(request)
            else {
                self.respond(connection, status: "404 Not Found", body: "")
                return
            }
            self.respond(
                connection,
                status: "200 OK",
                body: """
                <!doctype html><meta charset="utf-8"><title>Claudette</title>\
                <body style="font-family: -apple-system; background: #1c1c1e; \
                color: #f5f7fa; display: grid; place-items: center; height: 100vh; margin: 0">\
                <div style="text-align: center"><h2>Claudette is connected</h2>\
                <p style="color: #8e8e93">You can close this tab.</p></div>
                """)
            self.finish(.success(callback))
        }
    }

    static func parse(_ request: String) -> Callback? {
        guard let requestLine = request.split(separator: "\r\n").first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }
        guard
            let components = URLComponents(string: String(parts[1])),
            components.path == "/callback",
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
            !code.isEmpty
        else { return nil }
        let state = components.queryItems?.first(where: { $0.name == "state" })?.value
        return Callback(code: code, state: state)
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let payload = Data("""
        HTTP/1.1 \(status)\r
        Content-Type: text/html; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """.utf8)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ result: Result<Callback, Error>) {
        lock.lock()
        let cont = continuation
        continuation = nil
        stopped = true
        lock.unlock()
        guard let cont else { return }
        queue.asyncAfter(deadline: .now() + 0.25) { [listener] in
            listener.cancel()
        }
        switch result {
        case .success(let callback): cont.resume(returning: callback)
        case .failure(let error): cont.resume(throwing: error)
        }
    }
}
