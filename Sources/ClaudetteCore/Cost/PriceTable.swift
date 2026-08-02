import Foundation

/// Per-model rates in USD per million tokens. Cache dimensions default to
/// the standard multipliers when absent: write 1.25× input at 5m TTL,
/// 2× input at 1h TTL, read 0.1× input.
public struct ModelPrice: Codable, Sendable, Equatable {
    public var input: Double
    public var output: Double
    public var cacheRead: Double?
    public var cacheWrite5m: Double?
    public var cacheWrite1h: Double?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case cacheRead = "cache_read"
        case cacheWrite5m = "cache_write_5m"
        case cacheWrite1h = "cache_write_1h"
    }

    public init(
        input: Double,
        output: Double,
        cacheRead: Double? = nil,
        cacheWrite5m: Double? = nil,
        cacheWrite1h: Double? = nil
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public var effectiveCacheRead: Double { cacheRead ?? input * 0.1 }
    public var effectiveCacheWrite5m: Double { cacheWrite5m ?? input * 1.25 }
    public var effectiveCacheWrite1h: Double { cacheWrite1h ?? input * 2.0 }
}

public struct PriceTable: Sendable, Equatable {
    public private(set) var models: [String: ModelPrice]
    public let version: Int
    public let updatedAt: String?

    struct FileFormat: Codable {
        var version: Int
        var updatedAt: String?
        var models: [String: ModelPrice]

        enum CodingKeys: String, CodingKey {
            case version
            case updatedAt = "updated_at"
            case models
        }
    }

    public init(models: [String: ModelPrice], version: Int = 1, updatedAt: String? = nil) {
        self.models = Dictionary(uniqueKeysWithValues: models.map { ($0.key.lowercased(), $0.value) })
        self.version = version
        self.updatedAt = updatedAt
    }

    public static func load(from data: Data) throws -> PriceTable {
        let file = try JSONDecoder().decode(FileFormat.self, from: data)
        return PriceTable(models: file.models, version: file.version, updatedAt: file.updatedAt)
    }

    /// Ships in the app bundle; the floor that remote refreshes override.
    public static func bundled() -> PriceTable {
        guard
            let url = Bundle.module.url(forResource: "prices", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let table = try? load(from: data)
        else {
            return PriceTable(models: [:])
        }
        return table
    }

    /// Remote overrides by model ID; bundled entries survive unless overridden.
    public func merging(_ override: PriceTable) -> PriceTable {
        var merged = models
        for (key, value) in override.models {
            merged[key] = value
        }
        return PriceTable(
            models: merged,
            version: max(version, override.version),
            updatedAt: override.updatedAt ?? updatedAt)
    }

    /// Exact match first, then prefix matching for dated variants:
    /// `claude-sonnet-4-6-20260514` matches `claude-sonnet-4-6`. The suffix
    /// after a prefix match must look like a date/`latest`/revision so
    /// `claude-opus-4-5` never silently picks up `claude-opus-4` pricing.
    public func price(forModel modelID: String) -> ModelPrice? {
        var id = modelID.lowercased()
        if let slash = id.lastIndex(of: "/") {
            id = String(id[id.index(after: slash)...])
        }
        if let exact = models[id] {
            return exact
        }
        var best: (key: String, price: ModelPrice)?
        for (key, price) in models {
            guard id.hasPrefix(key), id.count > key.count else { continue }
            let suffix = String(id.dropFirst(key.count))
            guard Self.isVariantSuffix(suffix) else { continue }
            if best == nil || key.count > best!.key.count {
                best = (key, price)
            }
        }
        return best?.price
    }

    static func isVariantSuffix(_ suffix: String) -> Bool {
        guard suffix.hasPrefix("-") else { return false }
        let tail = String(suffix.dropFirst())
        if tail == "latest" { return true }
        // Date stamp: 20250514 etc.
        if tail.count == 8, tail.allSatisfy(\.isNumber), tail.hasPrefix("20") { return true }
        // Bedrock-style revision: v2:0, v1
        if tail.hasPrefix("v"), tail.dropFirst().first?.isNumber == true { return true }
        return false
    }

    /// Dollar cost of a tally, or nil for unknown models. Never silently
    /// price an unknown model at zero.
    public func dollars(for tally: TokenTally, model: String) -> Double? {
        guard let price = price(forModel: model) else { return nil }
        let million = 1_000_000.0
        return Double(tally.input) / million * price.input
            + Double(tally.output) / million * price.output
            + Double(tally.cacheWrite5m) / million * price.effectiveCacheWrite5m
            + Double(tally.cacheWrite1h) / million * price.effectiveCacheWrite1h
            + Double(tally.cacheRead) / million * price.effectiveCacheRead
    }
}

/// Keeps the price table fresh: bundled floor, remote overrides, weekly check.
public actor PriceTableLoader {
    private let remoteURL: URL?
    private let cacheDirectory: URL?
    private let transport: any HTTPTransport
    private var table: PriceTable
    private let checkInterval: TimeInterval = 7 * 24 * 3600

    public init(
        remoteURL: URL?,
        cacheDirectory: URL?,
        transport: any HTTPTransport = URLSessionTransport()
    ) {
        self.remoteURL = remoteURL
        self.cacheDirectory = cacheDirectory
        self.transport = transport
        var loaded = PriceTable.bundled()
        if let dir = cacheDirectory,
           let data = try? Data(contentsOf: dir.appendingPathComponent("prices-remote.json")),
           let cached = try? PriceTable.load(from: data) {
            loaded = loaded.merging(cached)
        }
        self.table = loaded
    }

    public func current() -> PriceTable { table }

    public func refreshIfStale(now: Date = Date()) async {
        guard let remoteURL, let cacheDirectory else { return }
        let stampURL = cacheDirectory.appendingPathComponent("prices-last-check")
        if let stampData = try? Data(contentsOf: stampURL),
           let stamp = TimeInterval(String(decoding: stampData, as: UTF8.self)),
           now.timeIntervalSince1970 - stamp < checkInterval {
            return
        }
        guard let reply = try? await transport.get(remoteURL, headers: [:]),
              reply.status == 200,
              let remote = try? PriceTable.load(from: reply.data)
        else { return }
        table = PriceTable.bundled().merging(remote)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try? reply.data.write(to: cacheDirectory.appendingPathComponent("prices-remote.json"), options: .atomic)
        try? Data(String(now.timeIntervalSince1970).utf8).write(to: stampURL, options: .atomic)
    }
}
