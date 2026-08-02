import AppKit

@main
enum ClaudetteMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
        // `delegate` is kept alive by this frame for the app's lifetime
        // (NSApplication.delegate is not retained).
        withExtendedLifetime(delegate) {}
    }
}
