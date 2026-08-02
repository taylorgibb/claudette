import AppKit

/// Recomputed on screen-parameter changes and wake; synthetic if there's no notch.
struct NotchGeometry: Equatable {
    var screenFrame: NSRect
    var notchMinX: CGFloat
    var notchWidth: CGFloat
    var notchHeight: CGFloat

    var notchCenterX: CGFloat { notchMinX + notchWidth / 2 }

    static let syntheticStandardWidth: CGFloat = 180

    @MainActor
    static func detect(screen: NSScreen) -> NotchGeometry {
        let frame = screen.frame
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(
                screenFrame: frame,
                notchMinX: left.maxX,
                notchWidth: right.minX - left.maxX,
                notchHeight: screen.safeAreaInsets.top)
        }
        // Synthetic notch: menu-bar height, horizontally centred.
        let menuBarHeight = max(frame.maxY - screen.visibleFrame.maxY, 24)
        let width = syntheticStandardWidth
        return NotchGeometry(
            screenFrame: frame,
            notchMinX: frame.midX - width / 2,
            notchWidth: width,
            notchHeight: min(menuBarHeight, 40))
    }

    /// Always automatic: prefer a notched screen, else the main one.
    @MainActor
    static func selectScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        if let notched = screens.first(where: { $0.auxiliaryTopLeftArea != nil }) {
            return notched
        }
        return NSScreen.main ?? screens.first
    }

    /// The geometry to start with: the notched screen if there is one, else a
    /// synthetic notch on the main screen, else a placeholder for a machine
    /// with no screens at all.
    @MainActor
    static func current() -> NotchGeometry {
        guard let screen = selectScreen() else {
            return NotchGeometry(
                screenFrame: .zero,
                notchMinX: 0,
                notchWidth: syntheticStandardWidth,
                notchHeight: 24)
        }
        return detect(screen: screen)
    }

    @MainActor
    static var hasNotchedDisplay: Bool {
        NSScreen.screens.contains { $0.auxiliaryTopLeftArea != nil }
    }
}
