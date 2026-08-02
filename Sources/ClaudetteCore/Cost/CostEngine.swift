import Foundation

public struct CostProgress: Sendable, Equatable {
    public let filesDone: Int
    public let filesTotal: Int
    public var fraction: Double {
        filesTotal > 0 ? Double(filesDone) / Double(filesTotal) : 0
    }
}

/// Owns the scan cache and produces `CostReport`s off the main thread.
public actor CostEngine {
    private let cacheURL: URL?
    private let analytics: any Analytics
    private var extraRoots: [String]
    private var cache: CostCache
    private var progressContinuations: [UUID: AsyncStream<CostProgress>.Continuation] = [:]

    public init(
        cacheURL: URL?,
        extraRoots: [String] = [],
        analytics: any Analytics = NoopAnalytics()
    ) {
        self.cacheURL = cacheURL
        self.extraRoots = extraRoots
        self.analytics = analytics
        self.cache = cacheURL.flatMap(CostCache.load(from:)) ?? CostCache()
    }

    public func progress() -> AsyncStream<CostProgress> {
        let (stream, continuation) = AsyncStream.makeStream(of: CostProgress.self)
        let id = UUID()
        progressContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeProgressContinuation(id) }
        }
        return stream
    }

    private func removeProgressContinuation(_ id: UUID) {
        progressContinuations[id] = nil
    }

    private func publishProgress(_ progress: CostProgress) {
        for continuation in progressContinuations.values {
            continuation.yield(progress)
        }
    }

    public func setExtraRoots(_ roots: [String]) {
        extraRoots = roots
    }

    /// Drops the cache and rescans everything.
    public func rebuild(prices: PriceTable, now: Date = Date()) async -> CostReport {
        cache = CostCache()
        return await refresh(prices: prices, now: now)
    }

    /// Incremental scan: new/grown files get their tails read; a shrunk file
    /// or changed inode forces a full rebuild (totals are global, so a single
    /// file's contribution can't be subtracted).
    public func refresh(prices: PriceTable, now: Date = Date()) async -> CostReport {
        let started = DispatchTime.now()
        let fm = FileManager.default
        let roots = LogScanner.discoverRoots(extraRoots: extraRoots)
        let files = LogScanner.sessionFiles(in: roots)

        // Detect invalidation before scanning anything.
        var marks: [String: (mark: CostCache.FileMark, url: URL)] = [:]
        var needsRebuild = false
        for url in files {
            guard let attrs = try? fm.attributesOfItem(atPath: url.path) else { continue }
            let inode = (attrs[.systemFileNumber] as? UInt64) ?? 0
            let size = (attrs[.size] as? UInt64) ?? 0
            let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let mark = CostCache.FileMark(inode: inode, size: size, mtime: mtime, offset: 0)
            marks[url.path] = (mark, url)
            if let known = cache.files[url.path],
               size < known.offset || (inode != known.inode && known.inode != 0) {
                needsRebuild = true
            }
        }
        if needsRebuild {
            cache = CostCache()
        }

        var seen = cache.seenHashes
        var toScan: [(url: URL, from: UInt64, mark: CostCache.FileMark)] = []
        for (path, entry) in marks {
            let offset = cache.files[path]?.offset ?? 0
            if entry.mark.size > offset {
                toScan.append((entry.url, offset, entry.mark))
            } else if cache.files[path] == nil {
                cache.files[path] = CostCache.FileMark(
                    inode: entry.mark.inode, size: entry.mark.size,
                    mtime: entry.mark.mtime, offset: entry.mark.size)
            }
        }
        toScan.sort { $0.url.path < $1.url.path }

        publishProgress(CostProgress(filesDone: 0, filesTotal: toScan.count))
        var done = 0
        for job in toScan {
            do {
                let result = try LogScanner.scanFile(at: job.url, from: job.from)
                for entry in result.entries where seen.insert(entry.dedupHash).inserted {
                    cache.add(entry)
                }
                cache.files[job.url.path] = CostCache.FileMark(
                    inode: job.mark.inode,
                    size: job.mark.size,
                    mtime: job.mark.mtime,
                    offset: result.consumedOffset)
            } catch {
                analytics.capture(.costScanFailed(failureKind: "read_error", rootKind: "projects"))
            }
            done += 1
            publishProgress(CostProgress(filesDone: done, filesTotal: toScan.count))
            await Task.yield()
        }

        cache.seenHashes = seen
        cache.prune(olderThanDays: 90, now: now)
        if let cacheURL {
            cache.save(to: cacheURL)
        }

        let elapsedMs = Int(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
        let report = CostReport.build(
            from: cache.days,
            prices: prices,
            now: now,
            scanDurationMs: elapsedMs,
            filesScanned: files.count)
        for model in report.unknownModels {
            analytics.capture(.unknownModelPriced(modelID: model))
        }
        return report
    }
}
