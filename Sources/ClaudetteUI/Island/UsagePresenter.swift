import Foundation
import ClaudetteCore

struct UsagePresenter: Equatable {
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

    var problemText: String? {
        switch state.phase {
        case .ok, .initializing:
            return nil
        case .credentialsUnavailable(let reason):
            return Self.guidance(for: reason)
        case .unauthorized:
            return "Session expired. Sign in again from Settings."
        case .scopeMissing:
            return Self.guidance(for: .scopeMissing)
        case .rateLimited(let until):
            guard let until else { return "Usage API rate limited. Backing off." }
            let wait = Format.compactCountdown(to: until, from: now, spaced: true)
            return "Usage API rate limited. Retrying in \(wait)."
        case .offline:
            return state.syncedAt == nil ? "Can't reach the usage API." : nil
        case .serverError(let status):
            guard state.syncedAt == nil else { return nil }
            return status.map { "The usage API returned an error (HTTP \($0))." }
                ?? "The usage API returned something unreadable."
        }
    }

    static func guidance(for reason: CredentialFailureReason) -> String {
        switch reason {
        case .signedOut:
            return "Sign in with Claude from Settings to see your usage."
        case .scopeMissing:
            return "This sign-in can't read usage. Sign in again from Settings."
        case .expired:
            return "Session expired. Sign in again from Settings."
        }
    }
}
