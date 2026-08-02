import Foundation

/// Random UUID minted on first launch and stored in Application Support.
/// Never derived from hardware serials, MAC addresses, or the Anthropic
/// account; deleting app data resets it, which is the correct behaviour.
enum InstallID {
    static func get(appSupportDirectory: URL) -> String {
        let url = appSupportDirectory.appendingPathComponent("install-id")
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if UUID(uuidString: trimmed) != nil {
                return trimmed
            }
        }
        let fresh = UUID().uuidString
        try? FileManager.default.createDirectory(at: appSupportDirectory, withIntermediateDirectories: true)
        try? Data(fresh.utf8).write(to: url, options: .atomic)
        return fresh
    }
}
