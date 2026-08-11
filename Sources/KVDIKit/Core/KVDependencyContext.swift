//
//  KVDependencyContext.swift
//  KVDIKit
//

import Foundation

/// Which flavour of a dependency to hand out when nothing has overridden it.
///
/// The context is detected once at launch and rarely needs setting by hand —
/// running under XCTest gives ``test``, an Xcode preview gives ``preview``,
/// everything else gives ``live``.
public enum KVDependencyContext: String, Sendable, CaseIterable {

    /// The real thing: network calls, StoreKit, the file system.
    case live

    /// Xcode previews. Defaults to the live value unless a key opts out.
    case preview

    /// Unit tests. Defaults to the live value *and warns*, so an unstubbed
    /// dependency shows up as a runtime issue instead of silently hitting the network.
    case test
}

public extension KVDependencyContext {

    /// The context inferred from the running process.
    ///
    /// Computed once — process identity does not change mid-run, and resolving a
    /// dependency happens often enough that re-reading the environment would show up.
    static let detected: KVDependencyContext = detect()

    private static func detect() -> KVDependencyContext {
        let process = ProcessInfo.processInfo
        let environment = process.environment

        // XCTest exports these before the bundle is loaded, so they are set even
        // for the very first dependency resolved in a test.
        let testMarkers = ["XCTestBundlePath", "XCTestConfigurationFilePath", "XCTestSessionIdentifier"]
        if testMarkers.contains(where: { environment[$0] != nil }) {
            return .test
        }
        // `swift test` on the command line runs the xctest helper directly and
        // sets none of the above.
        if process.arguments.contains(where: { $0.hasSuffix(".xctest") }) {
            return .test
        }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .preview
        }
        return .live
    }
}
