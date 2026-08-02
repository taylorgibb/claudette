import XCTest
import ClaudetteCore
@testable import ClaudetteUI

/// Which rows a plan shows, and what each failure reads like. All of this
/// used to live in an executable target with no test target attached.
final class UsagePresenterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func state(
        _ phase: UsageState.Phase = .ok,
        limits: [UsageLimit] = [],
        syncedAt: Date? = Date(timeIntervalSince1970: 1_800_000_000)
    ) -> UsageState {
        var state = UsageState()
        state.phase = phase
        state.snapshot = UsageSnapshot(limits: limits)
        state.syncedAt = syncedAt
        return state
    }

    private func limit(
        _ kind: UsageLimit.Kind, _ percent: Double, model: String? = nil
    ) -> UsageLimit {
        UsageLimit(
            kind: kind,
            window: LimitWindow(percentUsed: percent, resetsAt: nil),
            modelName: model)
    }

    func testAlwaysThreeGaugesInAFixedOrder() {
        let presenter = UsagePresenter(state: state(limits: []), now: now)
        XCTAssertEqual(presenter.gauges.map(\.label), ["Session", "Week", "Model"])
        XCTAssertTrue(presenter.gauges.allSatisfy(\.isUnavailable))
    }

    /// The row keeps its slot even when the plan has no such limit, so the
    /// island never resizes under the pointer as limits come and go.
    func testMissingLimitBecomesAnUnavailableRowNotAMissingOne() {
        let presenter = UsagePresenter(
            state: state(limits: [limit(.session, 20)]), now: now)
        XCTAssertEqual(presenter.gauges.count, 3)
        XCTAssertFalse(presenter.gauges[0].isUnavailable)
        XCTAssertTrue(presenter.gauges[1].isUnavailable)
        XCTAssertTrue(presenter.gauges[2].isUnavailable)
    }

    func testModelRowIsNamedByTheAPI() {
        let presenter = UsagePresenter(
            state: state(limits: [limit(.weeklyPerModel, 12, model: "Fable")]), now: now)
        XCTAssertEqual(presenter.gauges[2].label, "Fable")
        XCTAssertEqual(presenter.gauges[2].window?.percentUsed, 12)
    }

    /// One casing policy, at the view layer. The API returns "Fable"; anything
    /// arriving lowercase is raised rather than shown as-is.
    func testModelNameCasingIsNormalisedOnce() {
        let presenter = UsagePresenter(
            state: state(limits: [limit(.weeklyPerModel, 1, model: "opus")]), now: now)
        XCTAssertEqual(presenter.gauges[2].label, "Opus")
    }

    func testGaugeDurationsComeFromTheLimitKind() {
        let presenter = UsagePresenter(state: state(), now: now)
        XCTAssertEqual(presenter.gauges[0].duration, 5 * 3600)
        XCTAssertEqual(presenter.gauges[1].duration, 7 * 86_400)
        XCTAssertEqual(presenter.gauges[2].duration, 7 * 86_400)
    }

    /// The collapsed bar shows the first two limits that exist, so an account
    /// without a session window promotes the next one up rather than showing
    /// a blank.
    func testPillsPromoteThroughMissingLimits() {
        let presenter = UsagePresenter(
            state: state(limits: [
                limit(.weeklyAllModels, 30),
                limit(.weeklyPerModel, 40, model: "Fable"),
            ]),
            now: now)
        XCTAssertEqual(presenter.leadingPillWindow?.percentUsed, 30)
        XCTAssertEqual(presenter.trailingPillWindow?.percentUsed, 40)
    }

    func testPillsAreEmptyWithNoLimitsAtAll() {
        let presenter = UsagePresenter(state: state(limits: []), now: now)
        XCTAssertNil(presenter.leadingPillWindow)
        XCTAssertNil(presenter.trailingPillWindow)
    }

    func testEveryActionableFailureSaysWhatToRun() {
        let phases: [UsageState.Phase] = [
            .unauthorized,
            .scopeMissing,
            .credentialsUnavailable(.noKeychainItem),
            .credentialsUnavailable(.expired),
            .credentialsUnavailable(.mcpOnly),
        ]
        for phase in phases {
            let text = UsagePresenter(state: state(phase), now: now).problemText
            XCTAssertNotNil(text, "\(phase) has no guidance")
            XCTAssertTrue(
                text?.contains("claude login") ?? false,
                "\(phase) doesn't say what to run: \(text ?? "nil")")
        }
    }

    func testHealthyStateHasNoProblemText() {
        XCTAssertNil(UsagePresenter(state: state(.ok), now: now).problemText)
        XCTAssertNil(UsagePresenter(state: state(.initializing), now: now).problemText)
    }

    /// A stale reading beats an error the user can do nothing about, so a
    /// transient outage stays quiet as long as there is something to show.
    func testTransientFailuresStayQuietWhenThereIsStillAReadingOnScreen() {
        XCTAssertNil(UsagePresenter(state: state(.offline), now: now).problemText)
        XCTAssertNil(
            UsagePresenter(state: state(.serverError(status: 500)), now: now).problemText)

        let neverSynced = state(.offline, syncedAt: nil)
        XCTAssertNotNil(UsagePresenter(state: neverSynced, now: now).problemText)
    }

    func testRateLimitedSaysHowLong() {
        let until = now.addingTimeInterval(90 * 60)
        let text = UsagePresenter(state: state(.rateLimited(until: until)), now: now).problemText
        XCTAssertEqual(text, "Usage API rate limited. Retrying in 1H 30M.")
    }

    func testSyncLabelPrefersRefreshingOverEverythingElse() {
        var refreshing = state(.unauthorized)
        refreshing.isRefreshing = true
        XCTAssertEqual(UsagePresenter(state: refreshing, now: now).syncStatusText, "Syncing…")
        XCTAssertEqual(
            UsagePresenter(state: state(.unauthorized), now: now).syncStatusText, "Signed out")
        XCTAssertEqual(
            UsagePresenter(state: state(.ok), now: now).syncStatusText, "Synced just now")
    }
}
