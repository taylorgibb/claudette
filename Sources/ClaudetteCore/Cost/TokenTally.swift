import Foundation

public struct TokenTally: Codable, Sendable, Equatable {
    public var input: Int64 = 0
    public var output: Int64 = 0
    public var cacheWrite5m: Int64 = 0
    public var cacheWrite1h: Int64 = 0
    public var cacheRead: Int64 = 0

    public init() {}

    public init(
        input: Int64 = 0,
        output: Int64 = 0,
        cacheWrite5m: Int64 = 0,
        cacheWrite1h: Int64 = 0,
        cacheRead: Int64 = 0
    ) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    public var total: Int64 {
        input + output + cacheWrite5m + cacheWrite1h + cacheRead
    }

    public var isEmpty: Bool { total == 0 }

    public static func += (lhs: inout TokenTally, rhs: TokenTally) {
        lhs.input += rhs.input
        lhs.output += rhs.output
        lhs.cacheWrite5m += rhs.cacheWrite5m
        lhs.cacheWrite1h += rhs.cacheWrite1h
        lhs.cacheRead += rhs.cacheRead
    }

    public static func + (lhs: TokenTally, rhs: TokenTally) -> TokenTally {
        var result = lhs
        result += rhs
        return result
    }
}
