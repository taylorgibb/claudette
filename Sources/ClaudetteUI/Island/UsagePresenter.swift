import Foundation
import ClaudetteCore

/// Turns a `UsageState` into everything the usage page renders: three gauge
/// rows, the sync label, and the problem sentence.
///
/// A value type with no dependencies beyond its two inputs, so the decisions
/// about which rows a plan has and what each failure reads like can be tested
/// without a window, a display, or a network.
struct UsagePresenter: Equatable {
    /// One gauge: a label, the window behind it, and how long that window
    /// spans. A nil window means the plan doesn't have this limit.
    struct Gauge: Equatable, Identifiable {
        let label: String
        let window: LimitWindow?
        let duration: TimeInterval
        var id: String { label }

        var isUnavailable: Bool { window == nil }
    }

    let state: UsageState
    let now: Date

    var isStale: Bool { state.isStale(now: now) }

    /// Always three rows, in a fixed order. A row the plan doesn't have is
    /// rendered unavailable rather than dropped, so the island never resizes
    /// under the pointer as limits come and go.
    var gauges: [Gauge] {
        let snapshot = state.snapshot
        let perModel = snapshot?.weeklyForModel
        return [
            Gauge(
                label: "Session",
                window: snapshot?.session,
                duration: UsageLimit.Kind.session.windowDuration),
            Gauge(
                label: "Week",
                window: snapshot?.weekly,
                duration: UsageLimit.Kind.weeklyAllModels.windowDuration),
            Gauge(
                label: perModel.map { Format.modelLabel($0.modelName ?? "") } ?? "Model",
                window: perModel?.window,
                duration: UsageLimit.Kind.weeklyPerModel.windowDuration),
        ]
    }

    /// The collapsed bar shows the first two limits the plan actually has, so
    /// an account without a session window promotes the next one up. Derived
    /// from `gauges` rather than deciding the plan's shape a second time.
    private var populatedWindows: [LimitWindow] {
        gauges.compactMap(\.window)
    }

    var leadingPillWindow: LimitWindow? { populatedWindows.first }

    var trailingPillWindow: LimitWindow? {
        populatedWindows.count > 1 ? populatedWindows[1] : nil
    }

    var syncStatusText: String {
        if state.isRefreshing { return "Syncing…" }
        switch state.phase {
        case .ok, .initializing, .offline, .serverError:
            return Format.ago(state.syncedAt, from: now)
        case .credentialsUnavailable:
            return "No credentials"
        case .unauthorized:
            return "Signed out"
        case .scopeMissing:
            return "Token lacks scope"
        case .rateLimited:
            return "Rate limited"
        }
    }

    /// The sentence shown under the gauges, or nil when there is nothing
    /// wrong. Every failure that the user can act on says what to run.
    var problemText: String? {
        switch state.phase {
        case .ok, .initializing:
            return nil
        case .credentialsUnavailable(let reason):
            return Self.guidance(for: reason)
        case .unauthorized:
            return "Session expired. Run `claude login` and Claudette will pick it up."
        case .scopeMissing:
            return Self.guidance(for: .scopeMissing)
        case .rateLimited(let until):
            guard let until else { return "Usage API rate limited. Backing off." }
            let wait = Format.compactCountdown(to: until, from: now, spaced: true)
            return "Usage API rate limited. Retrying in \(wait)."
        case .offline:
            // A stale reading is better than an error the user can't act on,
            // so this only speaks up when there is nothing to show at all.
            return state.syncedAt == nil ? "Can't reach the usage API." : nil
        case .serverError(let status):
            guard state.syncedAt == nil else { return nil }
            return status.map { "The usage API returned an error (HTTP \($0))." }
                ?? "The usage API returned something unreadable."
        }
    }

    /// User-facing copy for a credential failure. Core reports the code; the
    /// wording lives here with the rest of the app's copy.
    static func guidance(for reason: CredentialFailureReason) -> String {
        switch reason {
        case .noKeychainItem:
            return "No Claude Code credentials found. Sign in with `claude login`."
        case .mcpOnly:
            return "Claude Code stored MCP-only credentials. Re-authenticate with `claude login`."
        case .scopeMissing:
            return "This token can't read usage. Re-authenticate with `claude login`."
        case .expired:
            return "Claude Code token expired. Open Claude Code or run `claude login`."
        case .malformed:
            return "Stored credentials are unreadable. Re-authenticate with `claude login`."
        }
    }
}
