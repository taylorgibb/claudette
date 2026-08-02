import Foundation
import ClaudetteCore

/// Routes uncaught Objective-C exceptions through the redactor.
///
/// Scope is narrow and worth being honest about: `NSSetUncaughtExceptionHandler`
/// only fires for `NSException`. Swift's own traps — `fatalError`, a failed
/// force-unwrap, an out-of-bounds index — terminate the process without ever
/// reaching here. Catching those needs a signal and Mach-exception handler,
/// which is a much larger thing to own and to get right; this covers the
/// AppKit-originated half and nothing more.
///
/// The handler is a bare C function pointer, so it can capture no context and
/// the reporter has to be reachable statically.
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
