import SwiftUI
import ClaudetteCore

struct PanelView: View {
    @ObservedObject var vm: IslandViewModel
    @ObservedObject var settings: AppSettings
    let ns: Namespace.ID

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: vm.geometry.notchHeight)
            header
                .padding(.horizontal, 18)
                .padding(.top, 10)

            ZStack {
                if vm.page == .usage {
                    usagePage
                        .transition(.asymmetric(
                            insertion: .move(edge: .leading).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                } else {
                    CostView(vm: vm, settings: settings)
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .trailing).combined(with: .opacity)))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.9), value: vm.page)
            .clipped()
            .gesture(
                DragGesture(minimumDistance: 20)
                    .onEnded { value in
                        if value.translation.width < -40 {
                            vm.goToCostPage()
                        } else if value.translation.width > 40 {
                            vm.page = .usage
                        }
                    })

            Spacer(minLength: 0)

            if vm.showConsent {
                consentRow
            }
        }
        .frame(width: vm.size(for: .panel).width)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button(action: { vm.refreshTapped() }) {
                Text(vm.syncStatusText)
                    .font(Tokens.label())
                    .tracking(0.6)
                    .foregroundStyle(vm.isStale ? Tokens.haze.opacity(0.5) : Tokens.haze)
            }
            .buttonStyle(.plain)
            .help("Refresh now")

            Spacer()

            Button(action: { vm.page = .usage }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(vm.page == .usage ? Tokens.haze.opacity(0.3) : Tokens.haze)
            }
            .buttonStyle(.plain)
            .disabled(vm.page == .usage)

            Button(action: { vm.goToCostPage() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(vm.page == .cost ? Tokens.haze.opacity(0.3) : Tokens.haze)
            }
            .buttonStyle(.plain)
            .disabled(vm.page == .cost)

            Button(action: { vm.openSettings() }) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.haze)
            }
            .buttonStyle(.plain)
            .help("Settings")
        }
    }

    private var usagePage: some View {
        VStack(alignment: .leading, spacing: 14) {
            GaugeBar(
                label: "SESSION",
                window: vm.usage.snapshot?.fiveHour,
                windowLength: 5 * 3600,
                displayRemaining: settings.displayRemaining,
                now: vm.now,
                dimmed: vm.isStale,
                geometryID: "left-num",
                ns: ns)
            GaugeBar(
                label: "WEEK",
                window: vm.usage.snapshot?.sevenDay,
                windowLength: 7 * 86_400,
                displayRemaining: settings.displayRemaining,
                now: vm.now,
                dimmed: vm.isStale,
                geometryID: "right-num",
                ns: ns)
            // Ghost row keeps panel height stable when the model-scoped
            // window is absent (decision D2a).
            GaugeBar(
                label: vm.usage.snapshot?.modelWeekly.map { "\($0.label) · 7D" } ?? "MODEL · 7D",
                window: vm.usage.snapshot?.modelWeekly?.window,
                windowLength: 7 * 86_400,
                displayRemaining: settings.displayRemaining,
                now: vm.now,
                dimmed: vm.isStale)

            if let problem = vm.problemText {
                Text(problem)
                    .font(.system(size: 10))
                    .foregroundStyle(Tokens.haze)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let update = vm.updateAvailable {
                Link(destination: AppSettings.releasesURL) {
                    Text("UPDATE V\(update) AVAILABLE")
                        .font(Tokens.label())
                        .tracking(0.6)
                        .foregroundStyle(Tokens.vapor.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var consentRow: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(Tokens.hairline)
                .frame(height: 1)
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Anonymous usage & crash reporting")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Tokens.vapor)
                    Text("Redacted events only — never prompts, tokens, paths, or your usage numbers. Behavioral analytics stays off unless you opt in from Settings.")
                        .font(.system(size: 9))
                        .foregroundStyle(Tokens.haze)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Details", destination: AppSettings.telemetryDetailsURL)
                        .font(.system(size: 9))
                        .foregroundStyle(Tokens.haze)
                }
                Spacer()
                Toggle("", isOn: $settings.telemetryEssential)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                Button("OK") { vm.acknowledgeConsent() }
                    .controlSize(.small)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        }
    }
}
