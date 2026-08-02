import Foundation

public struct HTTPResponse: Sendable {
    public let status: Int
    public let data: Data
    /// Header names lowercased.
    public let headers: [String: String]

    public init(status: Int, data: Data, headers: [String: String] = [:]) {
        self.status = status
        self.data = data
        self.headers = headers
    }
}

/// The seam every network call goes through, so the whole package — including
/// the telemetry egress path — is exercisable without a network.
public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse
    func post(_ url: URL, headers: [String: String], body: Data) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    /// `waitsForConnectivity` is off by default: a poller that blocks for the
    /// full resource timeout while offline leaves the UI claiming it is
    /// refreshing. Failing fast and retrying on the normal schedule is both
    /// more honest and cheaper.
    public init(waitsForConnectivity: Bool = false) {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = waitsForConnectivity
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 40
        self.session = URLSession(configuration: config)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPResponse {
        try await send(url, method: "GET", headers: headers, body: nil)
    }

    public func post(
        _ url: URL, headers: [String: String], body: Data
    ) async throws -> HTTPResponse {
        try await send(url, method: "POST", headers: headers, body: body)
    }

    private func send(
        _ url: URL, method: String, headers: [String: String], body: Data?
    ) async throws -> HTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return HTTPResponse(status: 0, data: data)
        }
        var lowered: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                lowered[k.lowercased()] = v
            }
        }
        return HTTPResponse(status: http.statusCode, data: data, headers: lowered)
    }
}

/// Stable hashing for values that outlive the process.
public enum Hash {
    /// 64-bit FNV-1a. Used for persisted dedup keys because `Hasher` is
    /// per-process seeded and therefore unstable across launches.
    public static func fnv1a64(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
