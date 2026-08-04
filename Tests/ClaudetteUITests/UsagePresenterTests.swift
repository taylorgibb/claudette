import XCTest
import ClaudetteCore
@testable import ClaudetteUI

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
        var phases: [UsageState.Phase] = [.unauthorized, .scopeMissing]
        phases += CredentialFailureReason.allCases.map { .credentialsUnavailable($0) }
        for phase in phases {
            let text = UsagePresenter(state: state(phase), now: now).problemText
            XCTAssertNotNil(text, "\(phase) has no guidance")
            XCTAssertTrue(
                text?.contains("Sign in") ?? false,
                "\(phase) doesn't say what to do: \(text ?? "nil")")
        }
    }

    func testHealthyStateHasNoProblemText() {
        XCTAssertNil(UsagePresenter(state: state(.ok), now: now).problemText)
        XCTAssertNil(UsagePresenter(state: state(.initializing), now: now).problemText)
    }

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
