import Foundation

/// The single scrubber on the telemetry egress path. Anything free-form
/// (error messages, stack traces) passes through here before leaving the
/// process. Tokens, emails, org UUIDs, home paths, and project directory
/// names must not survive.
public enum Redactor {
    public static let maxUTF8ByteCount = 2048

    private static let tokenRegex =
        try! NSRegularExpression(pattern: #"sk-ant-[A-Za-z0-9_\-]+"#)
    private static let emailRegex =
        try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"#)
    private static let uuidRegex =
        try! NSRegularExpression(
            pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#)
    private static let projectsRegex =
        try! NSRegularExpression(pattern: #"(projects/)[^\s"']+"#)
    private static let usersHomeRegex =
        try! NSRegularExpression(pattern: #"/Users/[^/\s"']+"#)

    public static func scrub(_ input: String) -> String {
        var text = input

        // Home directory → "~", both the current process home and any
        // /Users/<name> path that leaks in from another context.
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if home.count > 1 {
            text = text.replacingOccurrences(of: home, with: "~")
        }
        text = replace(usersHomeRegex, in: text, with: "~")

        // Strip everything below projects/ — those path components encode
        // the user's real project directory names.
        text = replace(projectsRegex, in: text, with: "$1…")

        text = replace(tokenRegex, in: text, with: "[token]")
        text = replace(emailRegex, in: text, with: "[email]")
        text = replace(uuidRegex, in: text, with: "[uuid]")

        if text.utf8.count > maxUTF8ByteCount {
            var clipped = String(decoding: Array(text.utf8.prefix(maxUTF8ByteCount)), as: UTF8.self)
            // Drop a possibly-split trailing scalar artifact.
            if clipped.unicodeScalars.last == "\u{FFFD}" {
                clipped.removeLast()
            }
            text = clipped + "…"
        }
        return text
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: template)
    }
}
