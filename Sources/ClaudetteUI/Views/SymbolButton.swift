import SwiftUI
import AppKit

struct SymbolButton: NSViewRepresentable {
    let symbolName: String
    let pointSize: CGFloat
    let tint: Color
    let help: String
    let action: () -> Void

    final class AppKitButton: NSButton {
        var onClick: (() -> Void)?

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        @objc func fire() { onClick?() }
    }

    func makeNSView(context: Context) -> AppKitButton {
        let button = AppKitButton()
        button.isBordered = false
        button.bezelStyle = .inline
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = help
        button.target = button
        button.action = #selector(AppKitButton.fire)
        apply(to: button)
        return button
    }

    func updateNSView(_ nsView: AppKitButton, context: Context) {
        apply(to: nsView)
    }

    private func apply(to button: AppKitButton) {
        button.onClick = action
        button.contentTintColor = NSColor(tint)
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: help)?
            .withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular))
    }
}
