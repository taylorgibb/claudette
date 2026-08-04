import Foundation
import ClaudetteCore

enum ExceptionReporter {
    nonisolated(unsafe) private static var reporter: (any AnalyticsReporting)?

    static func install(_ analytics: any AnalyticsReporting) {
        reporter = analytics
        NSSetUncaughtExceptionHandler { exception in
            ExceptionReporter.reporter?.captureError(
                type: exception.name.rawValue,
                message: exception.reason ?? "uncaught exception",
                stack: exception.callStackSymbols.joined(separator: "\n"))
            ExceptionReporter.reporter?.flush()
        }
    }
}
