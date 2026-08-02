import Foundation

/// Shared parsing/formatting helpers.
public enum ISO8601 {
    // Formatter instances are documented thread-safe for formatting/parsing.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// Parses ISO-8601 timestamps with or without fractional seconds. The
    /// Anthropic usage endpoint returns 6-digit microseconds, which the plain
    /// `.iso8601` decoder strategy rejects.
    public static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string)
    }

    public static func format(_ date: Date) -> String {
        plain.string(from: date)
    }

    /// A `JSONDecoder` whose date strategy tolerates fractional seconds.
    public static func tolerantDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = ISO8601.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unparseable ISO8601 date: \(raw)")
            }
            return date
        }
        return decoder
    }
}

public enum DayKey {
    nonisolated(unsafe) private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone.current
        return f
    }()

    /// Local-calendar-day bucket key, e.g. "2026-08-02".
    public static func from(_ date: Date) -> String {
        formatter.string(from: date)
    }

    public static func date(from key: String) -> Date? {
        formatter.date(from: key)
    }
}

/// 64-bit FNV-1a. Used for persisted dedup keys because `Hasher` is
/// per-process seeded and therefore unstable across launches.
public func fnv1a64(_ string: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in string.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
}

// MARK: - HTTP transport

public struct HTTPReply: Sendable {
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

public protocol HTTPTransport: Sendable {
    func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(waitsForConnectivity: Bool = true) {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = waitsForConnectivity
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)
    }

    public func get(_ url: URL, headers: [String: String]) async throws -> HTTPReply {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return HTTPReply(status: 0, data: data)
        }
        var lowered: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                lowered[k.lowercased()] = v
            }
        }
        return HTTPReply(status: http.statusCode, data: data, headers: lowered)
    }
}
