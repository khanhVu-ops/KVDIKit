//
//  KVIssueReporter.swift
//  KVDIKit
//

import Foundation
import os

/// Surfaces "you probably did not mean this" situations without killing the process.
///
/// The default handler logs a fault to the `com.apple.runtime-issues` subsystem,
/// which Xcode renders as a purple runtime issue on the offending line. A test that
/// forgets to stub a dependency therefore *shows*, but still runs to completion —
/// trapping would take the whole test bundle down with it.
public enum KVIssueReporter {

    /// Replace to route warnings somewhere else (assert in CI, collect in a test, …).
    ///
    /// Set to `nil` to silence them entirely.
    public static var handler: (@Sendable (String) -> Void)? {
        get { handlerBox.withLock { $0 } }
        set { handlerBox.withLock { $0 = newValue } }
    }

    private static let handlerBox = KVLocked<(@Sendable (String) -> Void)?>(defaultHandler)
    private static let alreadyReported = KVLocked<Set<String>>([])

    private static let defaultHandler: @Sendable (String) -> Void = { message in
        os_log(
            .fault,
            log: OSLog(subsystem: "com.apple.runtime-issues", category: "KVDIKit"),
            "%{public}@",
            message
        )
    }

    /// Receives test failures raised by KVDIKit — today, an unstubbed key under
    /// ``KVTestValuePolicy/fail``.
    ///
    /// The default calls `XCTFail` when XCTest is loaded in the process, and otherwise
    /// falls back to ``handler``. Under Swift Testing, route failures to the running
    /// test yourself:
    ///
    /// ```swift
    /// KVIssueReporter.failureHandler = { Issue.record(Comment(rawValue: $0)) }
    /// ```
    ///
    /// Set to `nil` to silence failures entirely.
    public static var failureHandler: (@Sendable (String) -> Void)? {
        get { failureHandlerBox.withLock { $0 } }
        set { failureHandlerBox.withLock { $0 = newValue } }
    }

    private static let failureHandlerBox = KVLocked<(@Sendable (String) -> Void)?>(defaultFailureHandler)

    private static let defaultFailureHandler: @Sendable (String) -> Void = { message in
        if let xctFail = KVXCTestBridge.fail {
            xctFail(message, #filePath, #line)
        } else {
            report(message)
        }
    }

    /// Fail the running test, every time.
    public static func fail(_ message: String) {
        failureHandlerBox.withLock { $0 }?(message)
    }

    /// Report an issue every time it happens.
    public static func report(_ message: String) {
        handlerBox.withLock { $0 }?(message)
    }

    /// Report an issue the first time only.
    ///
    /// A missing `testValue` is hit on every single access, and one warning per key
    /// is the useful signal — a hundred identical ones just bury the rest of the log.
    static func reportOnce(id: String, _ message: @autoclosure () -> String) {
        let isNew = alreadyReported.withLock { $0.insert(id).inserted }
        guard isNew else { return }
        report(message())
    }

    /// Forget which issues have been reported. Used by the package's own tests.
    static func resetReportedIssues() {
        alreadyReported.withLock { $0.removeAll() }
    }
}

/// Reaches `XCTFail` without linking XCTest, so the library stays usable in an app
/// target. Resolved once; `nil` when XCTest is not loaded (a shipping app, or a
/// Swift Testing-only run that never loaded it).
private enum KVXCTestBridge {

    typealias XCTFail = @convention(thin) (String, StaticString, UInt) -> Void

    /// `XCTest.XCTFail(_:file:line:)`, which XCTest's Swift overlay has exported under
    /// this name since Swift 5.
    static let fail: XCTFail? = {
        guard
            let process = dlopen(nil, RTLD_LAZY),
            let symbol = dlsym(process, "$s6XCTest7XCTFail_4file4lineySS_s12StaticStringVSutF")
        else { return nil }
        return unsafeBitCast(symbol, to: XCTFail.self)
    }()
}
