import SwiftUI
import ClaudetteCore

enum Theme {
    static let surface = Color(hex: 0x000000)
    static let primaryText = Color(hex: 0xF5F7FA)
    static let secondaryText = Color(hex: 0x7C8794)
    static let hairline = Color.white.opacity(0.08)

    static let settingsSurface = Color(hex: 0x1C1C1E)
    static let settingsSecondaryText = Color(hex: 0x8E8E93)

    // Calm is the chart orange, so gauges at rest match the cost page exactly;
    // the ramp only diverges from it as usage heats toward flare.
    static let calmRGB = (red: 0xF2 / 255.0, green: 0x6A / 255.0, blue: 0x46 / 255.0)
    static let emberRGB = (red: 0xF6 / 255.0, green: 0x5E / 255.0, blue: 0x4D / 255.0)
    static let flareRGB = (red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x5C / 255.0)

    static let accent = Color(
        .sRGB, red: calmRGB.red, green: calmRGB.green, blue: calmRGB.blue, opacity: 1)

    static let chartLine = Color(
        .sRGB, red: calmRGB.red, green: calmRGB.green, blue: calmRGB.blue, opacity: 1)

    // Charts share the gauges' hue and recede only through this one dim level;
    // any other opacity applied to chartLine reads as a different orange.
    static let chartDimOpacity: Double = 0.85

    static let tickIdleOpacity: Double = 0.75
    static let tickPunchOpacity: Double = 1.0

    static let pageDotActiveOpacity: Double = 0.85
    static let pageDotIdleOpacity: Double = 0.28

    private static let calmLab = OklabColor(red: calmRGB.red, green: calmRGB.green, blue: calmRGB.blue)
    private static let emberLab = OklabColor(red: emberRGB.red, green: emberRGB.green, blue: emberRGB.blue)
    private static let flareLab = OklabColor(red: flareRGB.red, green: flareRGB.green, blue: flareRGB.blue)

    static func gaugeTint(used fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        let mixed = t <= 0.65
            ? OklabColor.lerp(calmLab, emberLab, t / 0.65)
            : OklabColor.lerp(emberLab, flareLab, (t - 0.65) / 0.35)
        return Color(oklab: mixed)
    }

    static func numeral(size: CGFloat = 11) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced).monospacedDigit()
    }

    static let label = Font.system(size: 8.5, weight: .semibold)

    static func countdown(size: CGFloat = 8.5) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced).monospacedDigit()
    }

    static let unavailableLabel = Font.system(size: 9, weight: .regular, design: .monospaced)

    enum SettingsFont {
        static let title = Font.system(size: 13)
        static let detail = Font.system(size: 11.5)
        static let version = Font.system(size: 11, design: .monospaced)
    }
}

enum Layout {
    static let pillWidth: CGFloat = 42
    static let collapsedHeight: CGFloat = 33
    static let cornerRadius: CGFloat = 14

    static let panelWidth: CGFloat = 344
    static let panelPadding: CGFloat = 16
    static let panelTopPadding: CGFloat = 10
    static let rowGap: CGFloat = 14
    static let rowInnerGap: CGFloat = 6
    static let trackHeight: CGFloat = 3
    static let tickHeight: CGFloat = 9
    static let tickWidth: CGFloat = 1.5
    static let chartHeight: CGFloat = 36
    static let chartTopMargin: CGFloat = 12
    static let pageDotSize: CGFloat = 4.5
    static let pageDotGap: CGFloat = 0
    static let pageDotHitSize: CGFloat = 11
    static let pageDotVerticalPadding: CGFloat = 3
    static let estimatedPanelBodyHeight: CGFloat = 150

    static let hostWindowSize = CGSize(width: 620, height: 340)
}

enum Format {
    static func percentRemaining(_ window: LimitWindow?) -> String {
        guard let window else { return "–" }
        return "\(window.percentRemaining)%"
    }

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

    static func modelLabel(_ name: String) -> String {
        guard let first = name.first else { return name }
        return first.uppercased() + name.dropFirst()
    }
}
