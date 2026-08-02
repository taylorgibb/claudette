import Foundation
import Combine
import ClaudetteCore

/// UserDefaults-backed settings. `onChange` lets the app layer apply side
/// effects (poll interval, power assertions, telemetry policy) and emit the
/// `setting_changed` event for enum/bool keys only.
@MainActor
final class AppSettings: ObservableObject {
    static let telemetryDetailsURL = URL(string: "https://github.com/taylorgibb/claudette/blob/main/PRIVACY.md")!
    static let releasesURL = URL(string: "https://github.com/taylorgibb/claudette/releases")!

    private let defaults: UserDefaults
    var onChange: (@MainActor (String, String) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "pollIntervalMinutes": 5,
            "displayRemaining": false,
            "reliableHover": false,
            "displaySelection": "auto",
            "syntheticNotchCompact": false,
            "planTierOverride": "auto",
            "customMonthlyPrice": 0.0,
            "extraLogRoots": [String](),
            "launchAtLogin": false,
            "preventSystemSleep": false,
            "preventDisplaySleep": false,
            "autoCheckUpdates": true,
            "telemetryEssential": true,
            "telemetryBehavioral": false,
            "consentShown": false,
            "lastHeartbeatDay": "",
        ])
        if defaults.object(forKey: "firstLaunchDate") == nil {
            defaults.set(Date().timeIntervalSince1970, forKey: "firstLaunchDate")
        }

        pollIntervalMinutes = defaults.integer(forKey: "pollIntervalMinutes")
        displayRemaining = defaults.bool(forKey: "displayRemaining")
        reliableHover = defaults.bool(forKey: "reliableHover")
        displaySelection = defaults.string(forKey: "displaySelection") ?? "auto"
        syntheticNotchCompact = defaults.bool(forKey: "syntheticNotchCompact")
        planTierOverride = defaults.string(forKey: "planTierOverride") ?? "auto"
        customMonthlyPrice = defaults.double(forKey: "customMonthlyPrice")
        extraLogRoots = defaults.stringArray(forKey: "extraLogRoots") ?? []
        launchAtLogin = defaults.bool(forKey: "launchAtLogin")
        preventSystemSleep = defaults.bool(forKey: "preventSystemSleep")
        preventDisplaySleep = defaults.bool(forKey: "preventDisplaySleep")
        autoCheckUpdates = defaults.bool(forKey: "autoCheckUpdates")
        telemetryEssential = defaults.bool(forKey: "telemetryEssential")
        telemetryBehavioral = defaults.bool(forKey: "telemetryBehavioral")
        consentShown = defaults.bool(forKey: "consentShown")
        lastHeartbeatDay = defaults.string(forKey: "lastHeartbeatDay") ?? ""
    }

    private func store(_ key: String, _ value: Any, reported: String?) {
        defaults.set(value, forKey: key)
        if let reported {
            onChange?(key, reported)
        }
    }

    @Published var pollIntervalMinutes: Int {
        didSet { store("pollIntervalMinutes", pollIntervalMinutes, reported: "\(pollIntervalMinutes)") }
    }
    @Published var displayRemaining: Bool {
        didSet { store("displayRemaining", displayRemaining, reported: "\(displayRemaining)") }
    }
    @Published var reliableHover: Bool {
        didSet { store("reliableHover", reliableHover, reported: "\(reliableHover)") }
    }
    @Published var displaySelection: String {
        didSet { store("displaySelection", displaySelection, reported: displaySelection == "auto" ? "auto" : "pinned") }
    }
    @Published var syntheticNotchCompact: Bool {
        didSet { store("syntheticNotchCompact", syntheticNotchCompact, reported: "\(syntheticNotchCompact)") }
    }
    @Published var planTierOverride: String {
        didSet { store("planTierOverride", planTierOverride, reported: planTierOverride) }
    }
    @Published var customMonthlyPrice: Double {
        // Dollar amounts never leave the machine.
        didSet { store("customMonthlyPrice", customMonthlyPrice, reported: nil) }
    }
    @Published var extraLogRoots: [String] {
        // Paths never leave the machine.
        didSet { store("extraLogRoots", extraLogRoots, reported: nil) }
    }
    @Published var launchAtLogin: Bool {
        didSet { store("launchAtLogin", launchAtLogin, reported: "\(launchAtLogin)") }
    }
    @Published var preventSystemSleep: Bool {
        didSet { store("preventSystemSleep", preventSystemSleep, reported: "\(preventSystemSleep)") }
    }
    @Published var preventDisplaySleep: Bool {
        didSet { store("preventDisplaySleep", preventDisplaySleep, reported: "\(preventDisplaySleep)") }
    }
    @Published var autoCheckUpdates: Bool {
        didSet { store("autoCheckUpdates", autoCheckUpdates, reported: "\(autoCheckUpdates)") }
    }
    @Published var telemetryEssential: Bool {
        didSet { store("telemetryEssential", telemetryEssential, reported: "\(telemetryEssential)") }
    }
    @Published var telemetryBehavioral: Bool {
        didSet { store("telemetryBehavioral", telemetryBehavioral, reported: "\(telemetryBehavioral)") }
    }
    @Published var consentShown: Bool {
        didSet { store("consentShown", consentShown, reported: nil) }
    }
    @Published var lastHeartbeatDay: String {
        didSet { store("lastHeartbeatDay", lastHeartbeatDay, reported: nil) }
    }

    var pollIntervalSeconds: TimeInterval {
        TimeInterval(pollIntervalMinutes * 60)
    }

    var telemetryPolicy: TelemetryPolicy {
        TelemetryPolicy(essential: telemetryEssential, behavioral: telemetryBehavioral)
    }

    var daysSinceInstall: Int {
        let first = defaults.double(forKey: "firstLaunchDate")
        guard first > 0 else { return 0 }
        return max(0, Int(Date().timeIntervalSince1970 - first) / 86_400)
    }

    /// Resolved monthly subscription price in USD, or nil when unknown.
    func monthlyPrice(autoDetectedTier: String?) -> (label: String, usd: Double)? {
        switch planTierOverride {
        case "auto":
            guard let info = PlanTier.resolve(autoDetectedTier) else { return nil }
            return (info.displayName, info.monthlyUSD)
        case "custom":
            guard customMonthlyPrice > 0 else { return nil }
            return ("Custom", customMonthlyPrice)
        default:
            guard let info = PlanTier.known.first(where: { $0.id == planTierOverride }) else { return nil }
            return (info.displayName, info.monthlyUSD)
        }
    }
}
