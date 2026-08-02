import SwiftUI
import ClaudetteCore

/// The instrument-cluster palette. The surface is genuinely #000000 so the
/// silhouette fuses with the bezel; everything else is emissive.
enum Tokens {
    static let void = Color(hex: 0x000000)
    static let vapor = Color(hex: 0xF5F7FA)
    static let haze = Color(hex: 0x7C8794)
    static let hairline = Color.white.opacity(0.08)

    static let calmRGB = (red: 0x3D / 255.0, green: 0x6B / 255.0, blue: 0xE5 / 255.0)
    static let emberRGB = (red: 0xE8 / 255.0, green: 0x81 / 255.0, blue: 0x3A / 255.0)
    static let flareRGB = (red: 0xFF / 255.0, green: 0x3B / 255.0, blue: 0x5C / 255.0)

    /// Gauge tint as a continuous function of utilization, interpolated in
    /// Oklab: calm at 0, ember at ~65%, flare at 100%. Deliberately no
    /// traffic-light thresholds.
    static func gaugeTint(utilization fraction: Double) -> Color {
        let t = min(max(fraction, 0), 1)
        let calm = OklabColor(red: calmRGB.red, green: calmRGB.green, blue: calmRGB.blue)
        let ember = OklabColor(red: emberRGB.red, green: emberRGB.green, blue: emberRGB.blue)
        let flare = OklabColor(red: flareRGB.red, green: flareRGB.green, blue: flareRGB.blue)
        let mixed: OklabColor
        if t <= 0.65 {
            mixed = OklabColor.lerp(calm, ember, t / 0.65)
        } else {
            mixed = OklabColor.lerp(ember, flare, (t - 0.65) / 0.35)
        }
        return Color(oklab: mixed)
    }

    // MARK: Type

    static func numeral(_ size: CGFloat) -> Font {
        Font.system(size: size, weight: .medium, design: .monospaced).monospacedDigit()
    }

    static func label() -> Font {
        Font.system(size: 9, weight: .semibold)
    }

    static func countdown() -> Font {
        Font.system(size: 10, weight: .regular, design: .monospaced)
    }
}

enum Layout {
    static let pillWidth: CGFloat = 96
    static let collapsedDrop: CGFloat = 18
    static let peekWidth: CGFloat = 360
    static let peekDrop: CGFloat = 122
    static let panelWidth: CGFloat = 480
    static let panelDrop: CGFloat = 268
    static let cornerCollapsed: CGFloat = 10
    static let cornerExpanded: CGFloat = 18
    /// Host window is fixed at the max extent; the silhouette animates inside.
    static let windowSize = CGSize(width: 620, height: 340)
}

enum Format {
    static func percent(_ window: UsageWindow?, remaining: Bool) -> String {
        guard let window else { return "–" }
        let used = min(max(window.utilization, 0), 100)
        let value = remaining ? 100 - used : used
        return "\(Int(value.rounded()))%"
    }

    static func countdown(to date: Date?, from now: Date) -> String {
        guard let date else { return "" }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return "RESETS NOW" }
        let totalMinutes = Int(seconds / 60)
        let days = totalMinutes / (60 * 24)
        let hours = (totalMinutes / 60) % 24
        let minutes = totalMinutes % 60
        if days > 0 {
            return String(format: "RESETS %dD %02dH", days, hours)
        }
        if hours > 0 {
            return String(format: "RESETS %dH %02dM", hours, minutes)
        }
        return String(format: "RESETS %dM", max(minutes, 1))
    }

    static func ago(_ date: Date?, from now: Date) -> String {
        guard let date else { return "NEVER SYNCED" }
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "SYNCED NOW" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "SYNCED \(minutes)M AGO" }
        let hours = minutes / 60
        if hours < 48 { return "SYNCED \(hours)H AGO" }
        return "SYNCED \(hours / 24)D AGO"
    }

    static func dollars(_ value: Double) -> String {
        value >= 100 ? String(format: "$%.0f", value) : String(format: "$%.2f", value)
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

    static func multiple(_ value: Double) -> String {
        String(format: "%.1f×", value)
    }

    static func ordinalDay(_ dayKey: String) -> String? {
        guard let date = DayKey.date(from: dayKey) else { return nil }
        let day = Calendar.current.component(.day, from: date)
        let suffix: String
        switch day {
        case 11, 12, 13: suffix = "th"
        default:
            switch day % 10 {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(day)\(suffix)"
    }

    /// Short display name: "claude-opus-4-5-20260114" → "Opus 4.5".
    static func modelDisplayName(_ id: String) -> String {
        var name = id
        if let slash = name.lastIndex(of: "/") {
            name = String(name[name.index(after: slash)...])
        }
        var parts = name.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            parts.removeLast()
        }
        guard !parts.isEmpty else { return id }
        var family = parts.removeFirst()
        // "3-5-sonnet" style: family digits before the name.
        if family.allSatisfy(\.isNumber), let nameIndex = parts.firstIndex(where: { !$0.allSatisfy(\.isNumber) }) {
            let version = ([family] + parts[..<nameIndex]).joined(separator: ".")
            let familyName = parts[nameIndex].capitalized
            return "\(familyName) \(version)"
        }
        let version = parts.filter { $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        family = family.capitalized
        return version.isEmpty ? family : "\(family) \(version)"
    }
}
