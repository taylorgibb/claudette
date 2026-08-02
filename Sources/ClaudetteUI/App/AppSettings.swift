import Foundation
import Combine
import ClaudetteCore

/// Everything the user can change, backed by `UserDefaults`.
///
/// Writes publish through `changes` rather than calling out directly: a
/// `didSet` that synchronously mutates another `ObservableObject` is one
/// refactor away from "Publishing changes from within view updates is not
/// allowed", and a SwiftUI `Picker` binding writes these from inside a view
/// update.
@MainActor
final class AppSettings: ObservableObject {
    /// A setting that changed, and its new value rendered for telemetry.
    /// Paths and other free-form values report `nil` and are never sent.
    struct Change: Sendable {
        let key: Key
        let reportedValue: String?
    }

    /// Typed so a wiring switch can be exhaustive. A stringly-typed key was
    /// the app's only wiring bus, and a typo'd case was a silently dead
    /// setting with nothing to catch it.
    enum Key: String, Sendable, CaseIterable {
        case pollIntervalMinutes
        case planTierOverride
        case extraLogRoots
        case launchesAtLogin
        case preventsSleep
        case checksForUpdatesAutomatically
        case lastHeartbeatDay
    }

    private let defaults: UserDefaults
    private let changeSubject = PassthroughSubject<Change, Never>()

    var changes: AnyPublisher<Change, Never> { changeSubject.eraseToAnyPublisher() }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.pollIntervalMinutes.rawValue: 5,
            Key.planTierOverride.rawValue: PlanTier.automaticID,
            Key.extraLogRoots.rawValue: [String](),
            Key.launchesAtLogin.rawValue: false,
            Key.preventsSleep.rawValue: false,
            Key.checksForUpdatesAutomatically.rawValue: true,
            Key.lastHeartbeatDay.rawValue: "",
        ])
        if defaults.object(forKey: Self.firstLaunchKey) == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: Self.firstLaunchKey)
        }

        pollIntervalMinutes = defaults.integer(forKey: Key.pollIntervalMinutes.rawValue)
        planTierOverride = defaults.string(forKey: Key.planTierOverride.rawValue) ?? PlanTier.automaticID
        extraLogRoots = defaults.stringArray(forKey: Key.extraLogRoots.rawValue) ?? []
        launchesAtLogin = defaults.bool(forKey: Key.launchesAtLogin.rawValue)
        preventsSleep = defaults.bool(forKey: Key.preventsSleep.rawValue)
        checksForUpdatesAutomatically = defaults.bool(forKey: Key.checksForUpdatesAutomatically.rawValue)
        lastHeartbeatDay = defaults.string(forKey: Key.lastHeartbeatDay.rawValue) ?? ""
    }

    private static let firstLaunchKey = "firstLaunchDate"

    private func store(_ key: Key, _ value: Any, reported: String?) {
        defaults.set(value, forKey: key.rawValue)
        changeSubject.send(Change(key: key, reportedValue: reported))
    }

    @Published var pollIntervalMinutes: Int {
        didSet { store(.pollIntervalMinutes, pollIntervalMinutes, reported: "\(pollIntervalMinutes)") }
    }
    @Published var planTierOverride: String {
        didSet { store(.planTierOverride, planTierOverride, reported: planTierOverride) }
    }
    @Published var extraLogRoots: [String] {
        // Paths never leave the machine.
        didSet { store(.extraLogRoots, extraLogRoots, reported: nil) }
    }
    @Published var launchesAtLogin: Bool {
        didSet { store(.launchesAtLogin, launchesAtLogin, reported: "\(launchesAtLogin)") }
    }
    /// Keeps the machine awake for long agent runs. The display is still
    /// allowed to sleep.
    @Published var preventsSleep: Bool {
        didSet { store(.preventsSleep, preventsSleep, reported: "\(preventsSleep)") }
    }
    @Published var checksForUpdatesAutomatically: Bool {
        didSet {
            store(.checksForUpdatesAutomatically, checksForUpdatesAutomatically,
                  reported: "\(checksForUpdatesAutomatically)")
        }
    }
    @Published var lastHeartbeatDay: String {
        didSet { store(.lastHeartbeatDay, lastHeartbeatDay, reported: nil) }
    }

    var pollIntervalSeconds: TimeInterval {
        TimeInterval(pollIntervalMinutes * 60)
    }

    var daysSinceInstall: Int {
        let first = defaults.double(forKey: Self.firstLaunchKey)
        guard first > 0 else { return 0 }
        return max(0, Int(Date().timeIntervalSince1970 - first) / 86_400)
    }

    /// The tier to bill against: an explicit choice wins, otherwise whatever
    /// the account reported. An override naming a tier that no longer exists
    /// falls back to detection rather than stranding the user on no price.
    func billingTier(detected: String?) -> PlanTier? {
        PlanTier.effective(override: planTierOverride, detected: detected)
    }
}
