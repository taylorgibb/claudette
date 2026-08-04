import Foundation
import ClaudetteCore

@MainActor
final class UpdateChecker {
    private(set) var availableVersion: String? {
        didSet {
            guard availableVersion != oldValue else { return }
            onAvailableVersionChange?(availableVersion)
        }
    }

    var onAvailableVersionChange: (@MainActor (String?) -> Void)?

    private let transport: any HTTPTransport
    private var timerTask: Task<Void, Never>?

    init(transport: any HTTPTransport = URLSessionTransport()) {
        self.transport = transport
    }

    deinit {
        timerTask?.cancel()
    }

    func startDaily(isEnabled: @escaping @MainActor () -> Bool) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                if isEnabled() {
                    await self?.checkNow()
                }
                try? await Task.sleep(for: .seconds(Intervals.updateCheck))
            }
        }
    }

    func checkNow() async {
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
        }
        guard
            let reply = try? await transport.get(
                Endpoints.latestRelease, headers: ["Accept": "application/vnd.github+json"]),
            reply.status == 200,
            let release = try? JSONDecoder().decode(Release.self, from: reply.data)
        else { return }

        var latest = release.tagName
        if latest.hasPrefix("v") { latest.removeFirst() }
        availableVersion = Self.isNewer(latest, than: AppInfo.version) ? latest : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard current != "dev" else { return false }
        let left = candidate.split(separator: ".").compactMap { Int($0) }
        let right = current.split(separator: ".").compactMap { Int($0) }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }
}
