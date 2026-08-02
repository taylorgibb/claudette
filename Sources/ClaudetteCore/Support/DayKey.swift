import Foundation

/// A local-calendar day, e.g. `2026-08-02`. The bucket every cost tally is
/// filed under.
///
/// Deliberately a type rather than a `String`: it is used as a dictionary key
/// alongside `ModelID` (also a String), and untyped `[String: [String: _]]`
/// gives no clue which nesting level is which.
///
/// Resolved through `Calendar.current` on every call rather than a cached
/// formatter. This app runs for weeks at a time, so a frozen time zone would
/// silently mis-file spend across the day boundary after travel or a DST
/// change — and those keys then persist in the cache.
public struct DayKey: Hashable, Sendable, Comparable, Codable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    public init(_ date: Date) {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        self.init(year: year, month: month, day: day)
    }

    public var rawValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public var description: String { rawValue }

    /// Midnight local time on this day, or nil if the components don't name a
    /// real instant (a DST spring-forward gap).
    public var startOfDay: Date? {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // Encoded as the plain `2026-08-02` string, not as three fields.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = DayKey(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Not a yyyy-MM-dd day key: \(raw)")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Lets `[DayKey: _]` encode as a JSON object keyed by `2026-08-02` rather
/// than as a flat alternating array, which is what `Codable` falls back to for
/// non-String dictionary keys.
extension DayKey: CodingKeyRepresentable {
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { nil }
    }

    public var codingKey: CodingKey { Key(rawValue) }

    public init?<T: CodingKey>(codingKey: T) {
        self.init(rawValue: codingKey.stringValue)
    }
}

/// A Claude model identifier, lowercased, e.g. `claude-opus-5`. An alias
/// rather than a type: it is compared, prefix-matched and used as a dictionary
/// key exactly like the `String` it is, and only exists to say which `String`
/// a nested dictionary's keys are.
public typealias ModelID = String
