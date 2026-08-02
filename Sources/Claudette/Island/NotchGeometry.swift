import AppKit

/// Notch measurements for the chosen screen, recomputed on screen-parameter
/// changes and wake. Non-notched displays get a synthetic notch.
struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var notchMinX: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var isSynthetic: Bool

    var notchCenterX: CGFloat { notchMinX + notchWidth / 2 }

    static let syntheticStandardWidth: CGFloat = 180
    static let syntheticCompactWidth: CGFloat = 140

    @MainActor
    static func detect(screen: NSScreen, compactSynthetic: Bool) -> NotchGeometry {
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(
                screenFrame: frame,
                notchMinX: left.maxX,
                notchWidth: right.minX - left.maxX,
                notchHeight: screen.safeAreaInsets.top,
                isSynthetic: false)
        }
        // Synthetic notch: menu-bar height, horizontally centred.
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        let width = compactSynthetic ? syntheticCompactWidth : syntheticStandardWidth
        return NotchGeometry(
            screenFrame: frame,
            notchMinX: frame.midX - width / 2,
            notchWidth: width,
            notchHeight: min(menuBarHeight, 40),
            isSynthetic: true)
    }

    @MainActor
    static func screenID(for screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return screen.localizedName
        }
        return number.stringValue
    }

    /// Auto-detect prefers a notched screen; a pinned selection matches by
    /// display ID and falls back to auto when that display is gone.
    @MainActor
    static func selectScreen(selection: String) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if selection != "auto", let pinned = screens.first(where: { screenID(for: $0) == selection }) {
            return pinned
        }
        if let notched = screens.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            return notched
        }
        return NSScreen.main ?? screens.first
    }

    @MainActor
    static var hasNotchedDisplay: Bool {
        NSScreen.screens.contains { $0.auxiliaryTopLeftArea != nil }
    }
}
