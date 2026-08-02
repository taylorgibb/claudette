import SwiftUI
import ClaudetteCore

/// Instrument-cluster palette: a true-black surface that fuses with the bezel.
///
/// Named for role rather than for the colour, so a palette change doesn't
/// leave every call site lying about what it is asking for.
enum Theme {
    /// Matches the hardware notch, so the island reads as part of the bezel.
    static let surface = Color(hex: 0x000000)
    static let primaryText = Color(hex: 0xF5F7FA)
    static let secondaryText = Color(hex: 0x7C8794)
    static let hairline = Color.white.opacity(0.08)

    /// Settings chrome is an ordinary macOS dark sheet, not the instrument
    /// cluster, so it gets its own two colours.
    static let settingsSurface = Color(hex: 0x1C1C1E)
    static let settingsSecondaryText = Color(hex: 0x8E8E93)

    /// The gauge ramp: a light tint of ember, through ember, to flare. Only
    /// the intensity climbs — the hue never does, so a full gauge reads as
    /// urgent without turning into a different colour.
    static let calmRGB = (red: 0xF2 / 255.0, green: 0xA2 / 255.0, blue: 0x5C / 255.0)
    static let emberRGB = (red: 0xE8 / 255.0, green: 0x81 / 255.0, blue: 0x3A / 255.0)
    static let flareRGB = (red: 0xF2 / 255.0, green: 0x6A / 255.0, blue: 0x46 / 255.0)

    /// Accent for ordinary controls (toggles, pickers, links).
    static let accent = Color(
        .sRGB, red: emberRGB.red, green: emberRGB.green, blue: emberRGB.blue, opacity: 1)

    /// Cost sparkline and spend bars. Derived from the ramp's top stop so the
    /// chrome can't drift away from the gauges.
    static let chartLine = Color(
        .sRGB, red: flareRGB.red, green: flareRGB.green, blue: flareRGB.blue, opacity: 1)

    /// Pace tick, punched to full opacity for 400ms as it is crossed.
    static let tickIdleOpacity: Double = 0.75
    static let tickPunchOpacity: Double = 1.0

    // sRGB→Oklab costs several pow/cbrt; the ramp stops never change.
    private static let calmLab = OklabColor(red: calmRGB.red, green: calmRGB.green, blue: calmRGB.blue)
    private static let emberLab = OklabColor(red: emberRGB.red, green: emberRGB.green, blue: emberRGB.blue)
    private static let flareLab = OklabColor(red: flareRGB.red, green: flareRGB.green, blue: flareRGB.blue)

    /// Interpolated in Oklab so the midpoint looks halfway to the eye rather
    /// than halfway in sRGB, which would band. `fraction` is 0–1 used.
    static func gaugeTint(used fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        let mixed = t <= 0.65
            ? OklabColor.lerp(calmLab, emberLab, t / 0.65)
            : OklabColor.lerp(emberLab, flareLab, (t - 0.65) / 0.35)
        return Color(oklab: mixed)
    }

    // MARK: Type

    static func numeral(size: CGFloat = 11) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced).monospacedDigit()
    }

    static let label = Font.system(size: 7, weight: .semibold)

    /// Countdown beside a gauge label, and inside the collapsed pill.
    static func countdown(size: CGFloat = 7) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced).monospacedDigit()
    }

    /// "NOT ON THIS PLAN" — a row the account doesn't have.
    static let unavailableLabel = Font.system(size: 7.5, weight: .regular, design: .monospaced)

    /// The settings window is ordinary chrome, so it gets its own ramp.
    enum SettingsFont {
        static let title = Font.system(size: 13)
        static let detail = Font.system(size: 11.5)
        static let version = Font.system(size: 11, design: .monospaced)
    }
}

/// Halved from a @2x design; keep the ratios if you change these.
enum Layout {
    /// Frozen at the width of "100%" so digits never move geometry.
    static let pillWidth: CGFloat = 42
    static let collapsedHeight: CGFloat = 33
    /// One radius for every state, matching the hardware notch's inner curve.
    /// Animating the radius between states stops it reading as one object.
    static let cornerRadius: CGFloat = 14

    static let panelWidth: CGFloat = 344
    static let panelPadding: CGFloat = 16
    static let panelTopPadding: CGFloat = 10
    static let rowGap: CGFloat = 14
    static let rowInnerGap: CGFloat = 6
    static let trackHeight: CGFloat = 3
    /// The tick has to stand proud of the track to read as a marker at all.
    static let tickHeight: CGFloat = 9
    static let tickWidth: CGFloat = 1.5
    static let chartHeight: CGFloat = 36
    static let chartTopMargin: CGFloat = 12
    /// First-frame guess at the panel's height below the notch, used for one
    /// frame until the panel reports what it actually measured.
    static let estimatedPanelBodyHeight: CGFloat = 150

    /// The host `NSWindow` is fixed at the maximum extent the island can ever
    /// reach; the drawn silhouette animates inside it. Not a layout metric of
    /// anything visible — see `IslandWindow` for why the window is oversized.
    static let hostWindowSize = CGSize(width: 620, height: 340)
}

/// Number and date formatting for the island. Anything that decides *what* to
/// show lives in the view model or in Core; this only decides how it reads.
enum Format {
    static func percentRemaining(_ window: LimitWindow?) -> String {
        guard let window else { return "–" }
        return "\(window.percentRemaining)%"
    }

    /// Bezel countdown: "1H50M", "2D21H", "45M". `spaced` is for prose.
    static func compactCountdown(to date: Date?, from now: Date, spaced: Bool = false) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "NOW" }
        let gap = spaced ? " " : ""
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 { return String(format: "%dD\(gap)%02dH", days, hours) }
        if hours > 0 { return String(format: "%dH\(gap)%02dM", hours, minutes) }
        return String(format: "%dM", max(minutes, 1))
    }

    /// Sentence case; the island applies its uppercase styling at the view layer.
    static func ago(_ date: Date?, from now: Date) -> String {
        guard let date else { return "Never synced" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "Synced just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "Synced \(minutes)m ago" }
        let hours = minutes / 60
        if hours < 48 { return "Synced \(hours)h ago" }
        return "Synced \(hours / 24)d ago"
    }

    static func tokens(_ count: Int64) -> String {
        let value = Double(count)
        switch value {
        case ..<1_000: return "\(count)"
        case ..<1_000_000: return String(format: "%.1fK", value / 1_000)
        case ..<1_000_000_000: return String(format: "%.1fM", value / 1_000_000)
        default: return String(format: "%.2fB", value / 1_000_000_000)
        }
    }

    /// Costs are computed and shown in USD. Above 100 the cents stop
    /// carrying information, so they are dropped.
    static func dollars(_ value: Double) -> String {
        "$" + String(format: value >= 100 ? "%.0f" : "%.2f", value)
    }

    static func multiple(_ value: Double) -> String {
        String(format: "%.1f×", value)
    }

    static func ordinalDay(_ day: DayKey) -> String {
        let suffix: String
        switch day.day {
        case 11, 12, 13: suffix = "th"
        default:
            switch day.day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day.day)\(suffix)"
    }

    /// The API returns model names already capitalised ("Fable"); a name that
    /// arrives lowercase gets its first letter raised. One casing policy, at
    /// the view layer, which is the only place that should have one.
    static func modelLabel(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}
