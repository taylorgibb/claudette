import Foundation
@testable import ClaudetteCore

final class StubTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var _requests: [(url: URL, body: Data?)] = []
    let reply: HTTPResponse
    let error: (any Error)?

    init(reply: HTTPResponse = HTTPResponse(status: 200, data: Data()), error: (any Error)? = nil) {
        self.reply = reply
        self.error = error
    }

    convenience init(status: Int, body: String, headers: [String: String] = [:]) {
        self.init(reply: HTTPResponse(status: status, data: Data(body.utf8), headers: headers))
    }

    var requests: [(url: URL, body: Data?)] {
        lock.lock()
        defer { lock.unlock() }
        return _requests
    }

    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try record(url, body: nil)
    }

    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse {
        try record(url, body: body)
    }

    private func record(_ url: URL, body: Data?) throws -> HTTPResponse {
        lock.lock()
        _requests.append((url, body))
        lock.unlock()
        if let error { throw error }
        return reply
    }
}
