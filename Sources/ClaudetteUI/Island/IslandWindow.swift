import AppKit
import SwiftUI

final class IslandWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class IslandHostingView: NSHostingView<IslandRootView> {
    var silhouetteSize: @MainActor () -> CGSize = { .zero }

    required init(rootView: IslandRootView) {
        super.init(rootView: rootView)
    }

    @MainActor @objc dynamic required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let size = silhouetteSize()
        let rect = NSRect(
            x: (bounds.width - size.width) / 2,
            y: isFlipped ? 0 : bounds.maxY - size.height,
            width: size.width,
            height: size.height)
        return rect.contains(local) ? super.hitTest(point) : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
