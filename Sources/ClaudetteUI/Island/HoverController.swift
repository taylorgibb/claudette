import AppKit

@MainActor
final class HoverController {
    private weak var window: NSWindow?
    private var silhouetteSize: @MainActor () -> CGSize
    private let onHoverChange: @MainActor (Bool) -> Void
    private let onDismiss: @MainActor () -> Void

    private let mouseMonitors = RegistrationBag.eventMonitors()
    private let dismissMonitors = RegistrationBag.eventMonitors()
    private var watchdog: Timer?
    private var lastInside = false
    private var lastLocation: NSPoint?
    private var sawMouseEvent = false

    init(
        window: NSWindow,
        silhouetteSize: @escaping @MainActor () -> CGSize,
        onHoverChange: @escaping @MainActor (Bool) -> Void,
        onDismiss: @escaping @MainActor () -> Void
    ) {
        self.window = window
        self.silhouetteSize = silhouetteSize
        self.onHoverChange = onHoverChange
        self.onDismiss = onDismiss
        startHoverMonitoring()
        startLaunchPolling()
    }

    private func startHoverMonitoring() {
        let globalHandler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sawMouseEvent = true
                self?.evaluatePointer()
            }
        }
        mouseMonitors.add(
            NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: globalHandler))
        let localHandler: @Sendable (NSEvent) -> NSEvent? = { [weak self] event in
            MainActor.assumeIsolated {
                self?.sawMouseEvent = true
                self?.evaluatePointer()
            }
            return event
        }
        mouseMonitors.add(
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: localHandler))
    }

    private func startLaunchPolling() {
        watchdog?.invalidate()
        var ticksLeft = 20
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.evaluatePointer()
                ticksLeft -= 1
                if self.sawMouseEvent || ticksLeft <= 0 {
                    self.watchdog?.invalidate()
                    self.watchdog = nil
                }
            }
        }
    }

    private func evaluatePointer() {
        guard let window else { return }
        let size = silhouetteSize()
        let frame = window.frame
        let rect = NSRect(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height,
            width: size.width,
            height: size.height)
        let location = NSEvent.mouseLocation
        guard location != lastLocation else { return }
        lastLocation = location
        let inside = rect.contains(location)

        guard inside != lastInside else { return }
        lastInside = inside
        window.ignoresMouseEvents = !inside
        onHoverChange(inside)
    }

    func setPanelDismissMonitoring(_ enabled: Bool) {
        dismissMonitors.removeAll()
        guard enabled else { return }

        let outsideHandler: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onDismiss()
            }
        }
        dismissMonitors.add(NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown], handler: outsideHandler))
        let escapeHandler: @Sendable (NSEvent) -> NSEvent? = { [weak self] event in
            guard event.keyCode == 53 else { return event }
            MainActor.assumeIsolated {
                self?.onDismiss()
            }
            return nil
        }
        dismissMonitors.add(
            NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: escapeHandler))
    }
}
