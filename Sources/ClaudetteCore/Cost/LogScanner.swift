import Foundation

/// One parsed assistant turn worth of usage from a session JSONL line.
public struct ParsedUsage: Sendable, Equatable {
    public let dedupHash: UInt64
    public let model: String
    public let dayKey: String
    public let tally: TokenTally
}

/// Pure log-scanning machinery: root discovery, file listing, line parsing,
/// chunked incremental file reads. No state; `CostEngine` owns the cache.
public enum LogScanner {

    // MARK: - Root discovery

    /// Claude Code session log roots, in order, deduplicated by resolved path.
    public static func discoverRoots(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        extraRoots: [String] = []
    ) -> [URL] {
        var candidates: [URL] = []

        if let configDir = environment["CLAUDE_CONFIG_DIR"] {
            for part in configDir.split(separator: ",") {
                let trimmed = part.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                candidates.append(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
                    .appendingPathComponent("projects"))
            }
        }
        candidates.append(home.appendingPathComponent(".config/claude/projects"))
        candidates.append(home.appendingPathComponent(".claude/projects"))

        // Claude desktop app session containers: <base>/**/.claude/projects
        let appSupport = home.appendingPathComponent("Library/Application Support/Claude")
        for container in ["claude-code-sessions", "local-agent-mode-sessions"] {
            let base = appSupport.appendingPathComponent(container)
            candidates.append(contentsOf: nestedProjectRoots(under: base))
        }

        for extra in extraRoots {
            let trimmed = extra.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            candidates.append(URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath))
        }

        var seen = Set<String>()
        var roots: [URL] = []
        let fm = FileManager.default
        for candidate in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
                  isDirectory.boolValue,
                  seen.insert(resolved.path).inserted
            else { continue }
            roots.append(resolved)
        }
        return roots
    }

    /// Finds `**/.claude/projects` under a base directory, bounded depth.
    static func nestedProjectRoots(under base: URL, maxDepth: Int = 5) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: base,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsPackageDescendants]
        ) else { return [] }

        let baseDepth = base.pathComponents.count
        var found: [URL] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - baseDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            if url.lastPathComponent == "projects",
               url.deletingLastPathComponent().lastPathComponent == ".claude" {
                found.append(url)
                enumerator.skipDescendants()
            }
        }
        return found
    }

    /// All `.jsonl` files below the given roots.
    public static func sessionFiles(in roots: [URL]) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: []
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                files.append(url)
            }
        }
        return files.sorted { $0.path < $1.path }
    }

    // MARK: - Line parsing

    struct LogLine: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                struct CacheCreation: Decodable {
                    let ephemeral5m: Int64?
                    let ephemeral1h: Int64?

                    enum CodingKeys: String, CodingKey {
                        case ephemeral5m = "ephemeral_5m_input_tokens"
                        case ephemeral1h = "ephemeral_1h_input_tokens"
                    }
                }

                let inputTokens: Int64?
                let outputTokens: Int64?
                let cacheCreationInputTokens: Int64?
                let cacheReadInputTokens: Int64?
                let cacheCreation: CacheCreation?

                enum CodingKeys: String, CodingKey {
                    case inputTokens = "input_tokens"
                    case outputTokens = "output_tokens"
                    case cacheCreationInputTokens = "cache_creation_input_tokens"
                    case cacheReadInputTokens = "cache_read_input_tokens"
                    case cacheCreation = "cache_creation"
                }
            }

            let id: String?
            let model: String?
            let usage: Usage?
        }

        let type: String?
        let message: Message?
        let requestId: String?
        let timestamp: String?
    }

    nonisolated(unsafe) private static let decoder = JSONDecoder()

    /// Parses one JSONL line into usage, or nil for anything that isn't an
    /// assistant turn with usage attached.
    public static func parseLine(_ line: Data) -> ParsedUsage? {
        // Cheap pre-filter before running the decoder on every line.
        guard !line.isEmpty else { return nil }
        guard let parsed = try? decoder.decode(LogLine.self, from: line) else { return nil }
        guard parsed.type == "assistant",
              let message = parsed.message,
              let usage = message.usage,
              let model = message.model,
              !model.isEmpty,
              model != "<synthetic>"
        else { return nil }

        var tally = TokenTally()
        tally.input = usage.inputTokens ?? 0
        tally.output = usage.outputTokens ?? 0
        tally.cacheRead = usage.cacheReadInputTokens ?? 0
        if let breakdown = usage.cacheCreation,
           breakdown.ephemeral5m != nil || breakdown.ephemeral1h != nil {
            tally.cacheWrite5m = breakdown.ephemeral5m ?? 0
            tally.cacheWrite1h = breakdown.ephemeral1h ?? 0
        } else {
            // No TTL breakdown: assume 5m.
            tally.cacheWrite5m = usage.cacheCreationInputTokens ?? 0
        }
        guard !tally.isEmpty else { return nil }

        let date = parsed.timestamp.flatMap(ISO8601.parse) ?? Date()
        // Streaming chunks repeat usage for the same message; without this
        // dedup key the totals overcount badly.
        let hash = fnv1a64("\(message.id ?? ""):\(parsed.requestId ?? "")")
        return ParsedUsage(
            dedupHash: hash,
            model: model.lowercased(),
            dayKey: DayKey.from(date),
            tally: tally)
    }

    // MARK: - File scanning

    public struct FileScanResult: Sendable {
        public var consumedOffset: UInt64
        public var entries: [ParsedUsage]
    }

    /// Reads a session file from `offset`, in 1 MB chunks, splitting lines
    /// manually. A truncated final line (no trailing newline) is left
    /// unconsumed so the next incremental pass picks it up once complete.
    public static func scanFile(at url: URL, from offset: UInt64) throws -> FileScanResult {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: offset)

        let chunkSize = 1 << 20
        var carry = Data()
        var consumed = offset
        var entries: [ParsedUsage] = []
        let newline = UInt8(ascii: "\n")

        while true {
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            carry.append(chunk)

            var searchStart = carry.startIndex
            while let newlineIndex = carry[searchStart...].firstIndex(of: newline) {
                let lineData = carry.subdata(in: searchStart..<newlineIndex)
                consumed += UInt64(newlineIndex - searchStart) + 1
                if let parsed = parseLine(lineData) {
                    entries.append(parsed)
                }
                searchStart = carry.index(after: newlineIndex)
            }
            carry.removeSubrange(carry.startIndex..<searchStart)
        }

        return FileScanResult(consumedOffset: consumed, entries: entries)
    }
}
