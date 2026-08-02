import Foundation

/// ISO-8601 parsing and the JSON coders everything persisted goes through.
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

    /// Writes plain ISO-8601. `tolerantDecoder` reads either form, so
    /// everything we persist should be written in the plain one.
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
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
