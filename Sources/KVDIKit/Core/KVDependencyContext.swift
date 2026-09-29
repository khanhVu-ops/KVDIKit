//
//  KVDependencyContext.swift
//  KVDIKit
//

import Foundation

/// Which flavour of a dependency to hand out when nothing has overridden it.
///
/// The context is detected once at launch and rarely needs setting by hand —
/// running under XCTest or Swift Testing gives ``test``, an Xcode preview gives
/// ``preview``, everything else gives ``live``. The `KVDI_CONTEXT` environment
/// variable overrides the guess — see ``detected``.
public enum KVDependencyContext: String, Sendable, CaseIterable {

    /// The real thing: network calls, StoreKit, the file system.
    case live

    /// Xcode previews. Defaults to the live value unless a key opts out.
    case preview

    /// Unit tests. A key without a `testValue` falls back to its live value and is
    /// reported — a warning or a test failure, per ``KVDependencies/testValuePolicy`` —
    /// so an unstubbed dependency shows up instead of silently hitting the network.
    case test
}

public extension KVDependencyContext {

    /// The context inferred from the running process.
    ///
    /// Computed once — process identity does not change mid-run, and resolving a
    /// dependency happens often enough that re-reading the environment would show up.
    ///
    /// Set the `KVDI_CONTEXT` environment variable to `live`, `preview` or `test` (in
    /// the scheme's Run or Test action) to skip detection entirely — for instance to
    /// run UI tests against live values. For a single set of values, pass the context
    /// directly: `KVDependencyValues(context: .live)`, or `$0.context = .live` inside
    /// `prepare` / `withKVDependencies`.
    static let detected: KVDependencyContext = detect(
        environment: ProcessInfo.processInfo.environment,
        arguments: ProcessInfo.processInfo.arguments,
        isTestFrameworkLoaded: isTestFrameworkLoaded()
    )

    /// The environment variable that overrides detection.
    static let overrideEnvironmentKey = "KVDI_CONTEXT"
}

extension KVDependencyContext {

    /// Pure so it can be tested against made-up processes.
    static func detect(
        environment: [String: String],
        arguments: [String],
        isTestFrameworkLoaded: Bool
    ) -> KVDependencyContext {
        // An explicit choice always wins.
        if let raw = environment[overrideEnvironmentKey]?.lowercased(),
           let chosen = KVDependencyContext(rawValue: raw) {
            return chosen
        }

        // XCTest exports these before the bundle is loaded, so they are set even
        // for the very first dependency resolved in a test — including a hosted test
        // whose app resolves dependencies during launch. Xcode runs Swift Testing
        // through the same runner, so they cover `@Test` too.
        let testMarkers = ["XCTestBundlePath", "XCTestConfigurationFilePath", "XCTestSessionIdentifier"]
        if testMarkers.contains(where: { environment[$0] != nil }) {
            return .test
        }
        // `swift test` on the command line sets none of the above. It runs either the
        // `xctest` helper with the bundle path as an argument, or — for Swift Testing —
        // `swiftpm-testing-helper --test-bundle-path …/Foo.xctest/Contents/MacOS/Foo`.
        let pointsAtTestBundle = arguments.contains { argument in
            argument.hasSuffix(".xctest") || argument.contains(".xctest/")
        }
        if pointsAtTestBundle || arguments.first?.hasSuffix("swiftpm-testing-helper") == true {
            return .test
        }
        if environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            return .preview
        }
        // Last resort: a test framework is already loaded into this process (a test
        // runner that sets none of the markers above). Set `KVDI_CONTEXT=live` if an
        // app deliberately ships with XCTest loaded.
        if isTestFrameworkLoaded {
            return .test
        }
        return .live
    }

    /// `true` when XCTest or Swift Testing is loaded. A shipping app loads neither.
    private static func isTestFrameworkLoaded() -> Bool {
        if NSClassFromString("XCTestCase") != nil {
            return true
        }
        guard let process = dlopen(nil, RTLD_LAZY) else { return false }
        // `Testing.Test`'s type metadata accessor — present whenever Swift Testing is.
        return dlsym(process, "$s7Testing4TestVMa") != nil
    }
}
