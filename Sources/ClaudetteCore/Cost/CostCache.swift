import Foundation

/// Persistent incremental scan state. Session JSONL files are append-only,
/// so per-file byte offsets let each rescan read only the tail. Totals are
/// global (day → model → tally) because resumed sessions copy history across
/// files, which makes global dedup necessary; any file that shrinks or
/// changes inode forces a full rebuild.
public struct CostCache: Codable, Sendable, Equatable {
    public static let currentVersion = 1

    public struct FileMark: Codable, Sendable, Equatable {
        public var inode: UInt64
        public var size: UInt64
        public var mtime: Double
        public var offset: UInt64

        public init(inode: UInt64, size: UInt64, mtime: Double, offset: UInt64) {
            self.inode = inode
            self.size = size
            self.mtime = mtime
            self.offset = offset
        }
    }

    public var version: Int = currentVersion
    public var files: [String: FileMark] = [:]
    /// Base64 little-endian UInt64 buffer of seen `message.id + requestId`
    /// hashes — compact enough to persist even for heavy users.
    public var seenHashesBlob: String = ""
    /// dayKey → model → tally
    public var days: [String: [String: TokenTally]] = [:]

    public init() {}

    public var seenHashes: Set<UInt64> {
        get {
            guard let data = Data(base64Encoded: seenHashesBlob), !data.isEmpty else { return [] }
            var result = Set<UInt64>(minimumCapacity: data.count / 8)
            data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                let count = raw.count / 8
                for i in 0..<count {
                    result.insert(raw.loadUnaligned(fromByteOffset: i * 8, as: UInt64.self))
                }
            }
            return result
        }
        set {
            var data = Data(capacity: newValue.count * 8)
            for hash in newValue {
                withUnsafeBytes(of: hash.littleEndian) { data.append(contentsOf: $0) }
            }
            seenHashesBlob = data.base64EncodedString()
        }
    }

    public mutating func add(_ entry: ParsedUsage) {
        days[entry.dayKey, default: [:]][entry.model, default: TokenTally()] += entry.tally
    }

    /// Drops day buckets older than the retention horizon.
    public mutating func prune(olderThanDays retention: Int, now: Date = Date()) {
        guard let cutoffDate = Calendar.current.date(byAdding: .day, value: -retention, to: now) else { return }
        let cutoff = DayKey.from(cutoffDate)
        days = days.filter { $0.key >= cutoff }
    }

    public static func load(from url: URL) -> CostCache? {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(CostCache.self, from: data),
              cache.version == currentVersion
        else { return nil }
        return cache
    }

    public func save(to url: URL) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
