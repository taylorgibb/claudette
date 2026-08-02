import Foundation

/// Lightweight update check against GitHub releases: notify-and-link only,
/// once a day when enabled. (Sparkle can replace this later.)
@MainActor
final class UpdateChecker: ObservableObject {
    @Published var availableVersion: String? {
        didSet {
            if availableVersion != oldValue {
                onAvailableChange?(availableVersion)
            }
        }
    }

    var onAvailableChange: (@MainActor (String?) -> Void)?

    private let latestReleaseURL = URL(string: "https://api.github.com/repos/taylorgibb/claudette/releases/latest")!
    private var timerTask: Task<Void, Never>?

    func startDaily(isEnabled: @escaping @MainActor () -> Bool) {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                if isEnabled() {
                    await self?.checkNow()
                }
                try? await Task.sleep(nanoseconds: 24 * 3600 * 1_000_000_000)
            }
        }
    }

    func checkNow() async {
        struct Release: Decodable {
            let tagName: String
            enum CodingKeys: String, CodingKey { case tagName = "tag_name" }
        }
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            let release = try? JSONDecoder().decode(Release.self, from: data)
        else { return }

        var latest = release.tagName
        if latest.hasPrefix("v") { latest.removeFirst() }
        availableVersion = Self.isNewer(latest, than: AppInfo.version) ? latest : nil
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard current != "dev" else { return false }
        let a = candidate.split(separator: ".").compactMap { Int($0) }
        let b = current.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(a.count, b.count) {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }
}
