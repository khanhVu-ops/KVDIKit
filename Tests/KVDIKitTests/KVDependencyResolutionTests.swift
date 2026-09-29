//
//  KVDependencyResolutionTests.swift
//  KVDIKitTests
//

import XCTest
@testable import KVDIKit

final class KVDependencyResolutionTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KVDependencies.resetForTesting()
    }

    override func tearDown() {
        KVDependencies.resetForTesting()
        super.tearDown()
    }

    // MARK: - Context

    func testContextSelectsTheMatchingValue() {
        var values = KVDependencyValues(context: .live)
        XCTAssertEqual(values.greeter.greet("kv"), "live:kv")

        values.context = .preview
        XCTAssertEqual(values.greeter.greet("kv"), "preview:kv")

        values.context = .test
        XCTAssertEqual(values.greeter.greet("kv"), "test:kv")
    }

    func testDetectedContextIsTestWhileRunningTests() {
        XCTAssertEqual(KVDependencyContext.detected, .test)
        // Which means an un-overridden dependency resolves to its testValue by default.
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "test:kv")
    }

    func testOverrideWinsOverContext() {
        var values = KVDependencyValues(context: .live)
        values.greeter = .shouting
        XCTAssertEqual(values.greeter.greet("kv"), "SHOUT:KV")

        values.reset(GreeterKey.self)
        XCTAssertEqual(values.greeter.greet("kv"), "live:kv")
    }

    // MARK: - Missing testValue

    func testMissingTestValueWarnsOnceAndFallsBack() {
        let reported = KVLocked<[String]>([])
        let original = KVIssueReporter.handler
        KVIssueReporter.handler = { message in reported.withLock { $0.append(message) } }
        KVIssueReporter.resetReportedIssues()
        defer {
            KVIssueReporter.handler = original
            KVIssueReporter.resetReportedIssues()
        }

        let values = KVDependencyValues(context: .test)
        XCTAssertEqual(values.unstubbedGreeter.greet("kv"), "live:kv")
        XCTAssertEqual(values.unstubbedGreeter.greet("kv"), "live:kv")

        let messages = reported.withLock { $0 }
        XCTAssertEqual(messages.count, 1, "the warning should not repeat for the same key")
        XCTAssertTrue(messages[0].contains("UnstubbedGreeterKey"))
    }

    func testWarnIsTheDefaultPolicy() {
        XCTAssertEqual(KVDependencies.testValuePolicy, .warn)
    }

    func testFailPolicyReportsEveryAccessAsAFailure() {
        let warnings = KVLocked<[String]>([])
        let failures = KVLocked<[String]>([])
        let originalHandler = KVIssueReporter.handler
        let originalFailureHandler = KVIssueReporter.failureHandler
        KVIssueReporter.handler = { message in warnings.withLock { $0.append(message) } }
        KVIssueReporter.failureHandler = { message in failures.withLock { $0.append(message) } }
        KVDependencies.testValuePolicy = .fail
        defer {
            KVIssueReporter.handler = originalHandler
            KVIssueReporter.failureHandler = originalFailureHandler
            KVDependencies.testValuePolicy = .warn
        }

        let values = KVDependencyValues(context: .test)
        XCTAssertEqual(values.unstubbedGreeter.greet("kv"), "live:kv", "still falls back")
        XCTAssertEqual(values.unstubbedGreeter.greet("kv"), "live:kv")

        let messages = failures.withLock { $0 }
        XCTAssertEqual(messages.count, 2, "every access fails, so every test that touches it fails")
        XCTAssertTrue(messages.allSatisfy { $0.contains("UnstubbedGreeterKey") })
        XCTAssertTrue(warnings.withLock { $0 }.isEmpty, "failures do not also go to the warning handler")
    }

    func testFailPolicyIgnoresKeysWithATestValueAndOverriddenKeys() {
        let failures = KVLocked<[String]>([])
        let original = KVIssueReporter.failureHandler
        KVIssueReporter.failureHandler = { message in failures.withLock { $0.append(message) } }
        KVDependencies.testValuePolicy = .fail
        defer {
            KVIssueReporter.failureHandler = original
            KVDependencies.testValuePolicy = .warn
        }

        var values = KVDependencyValues(context: .test)
        _ = values.greeter
        XCTAssertEqual(values.liveInTests.greet("kv"), "live:kv", "`testValue { liveValue }` opts out")
        values.unstubbedGreeter = .shouting
        XCTAssertEqual(values.unstubbedGreeter.greet("kv"), "SHOUT:KV")

        XCTAssertTrue(failures.withLock { $0 }.isEmpty)
    }

    func testDefaultFailureHandlerFailsTheRunningXCTest() {
        KVDependencies.testValuePolicy = .fail
        defer { KVDependencies.testValuePolicy = .warn }

        XCTExpectFailure("an unstubbed key under .fail must fail the test") {
            _ = KVDependencyValues(context: .test).unstubbedGreeter
        }
    }

    // MARK: - Context detection

    func testDetectionRecognisesTestRunners() {
        func detect(_ environment: [String: String] = [:], _ arguments: [String] = ["/bin/App"], loaded: Bool = false) -> KVDependencyContext {
            KVDependencyContext.detect(environment: environment, arguments: arguments, isTestFrameworkLoaded: loaded)
        }

        XCTAssertEqual(detect(), .live)
        XCTAssertEqual(detect(["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]), .test)
        XCTAssertEqual(detect(["XCTestBundlePath": "/tmp/Foo.xctest"]), .test)
        XCTAssertEqual(detect(["XCTestSessionIdentifier": "abc"]), .test)
        XCTAssertEqual(detect([:], ["/usr/bin/xctest", "/build/FooPackageTests.xctest"]), .test)
        XCTAssertEqual(
            detect([:], ["/usr/bin/swiftpm-testing-helper", "--test-bundle-path", "/build/Foo.xctest/Contents/MacOS/Foo"]),
            .test,
            "swift test running Swift Testing"
        )
        XCTAssertEqual(detect([:], ["/usr/bin/swiftpm-testing-helper"]), .test)
        XCTAssertEqual(detect(loaded: true), .test, "XCTest or Swift Testing loaded in-process")
        XCTAssertEqual(detect(["XCODE_RUNNING_FOR_PREVIEWS": "1"]), .preview)
    }

    func testDetectionHonoursTheExplicitOverride() {
        func detect(_ environment: [String: String]) -> KVDependencyContext {
            KVDependencyContext.detect(environment: environment, arguments: ["/usr/bin/xctest"], isTestFrameworkLoaded: true)
        }

        XCTAssertEqual(detect(["KVDI_CONTEXT": "live", "XCTestConfigurationFilePath": "/tmp/x"]), .live)
        XCTAssertEqual(detect(["KVDI_CONTEXT": "Preview"]), .preview, "case-insensitive")
        XCTAssertEqual(detect(["KVDI_CONTEXT": "nonsense"]), .test, "an unknown value falls back to detection")
    }

    // MARK: - Scopes

    func testScopeOverridesForTheDurationOfTheOperation() {
        let model = GreetingModel()

        withKVDependencies {
            $0.greeter = .shouting
        } operation: {
            XCTAssertEqual(model.greet("kv"), "SHOUT:KV")
        }

        XCTAssertEqual(model.greet("kv"), "test:kv", "the scope should not outlive the call")
    }

    func testScopesNestAndInnerWins() {
        withKVDependencies {
            $0.greeter = .shouting
        } operation: {
            withKVDependencies {
                $0.greeter = Greeter { "inner:\($0)" }
            } operation: {
                XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "inner:kv")
            }
            XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
        }
    }

    func testScopeCanWrapTheValueItReplaces() {
        withKVDependencies { values in
            let base = values.greeter
            values.greeter = Greeter { "wrapped(\(base.greet($0)))" }
        } operation: {
            XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "wrapped(test:kv)")
        }
    }

    func testObjectBuiltInsideAScopeKeepsItAfterwards() {
        var model: GreetingModel?

        withKVDependencies {
            $0.greeter = .shouting
        } operation: {
            model = GreetingModel()
        }

        XCTAssertEqual(model?.greet("kv"), "SHOUT:KV", "the model should still see the override")
    }

    // MARK: - Concurrency

    func testAsyncScopeReachesChildTasks() async {
        let result = await withKVDependencies {
            $0.greeter = .shouting
        } operation: {
            await withTaskGroup(of: String.self) { group in
                group.addTask { KVDependencies.current.greeter.greet("child") }
                return await group.reduce(into: "") { $0 += $1 }
            }
        }

        XCTAssertEqual(result, "SHOUT:CHILD")
        XCTAssertEqual(KVDependencies.current.greeter.greet("after"), "test:after")
    }

    func testConcurrentScopesDoNotLeakIntoEachOther() async {
        await withTaskGroup(of: String.self) { group in
            for index in 0..<8 {
                group.addTask {
                    await withKVDependencies {
                        $0.greeter = Greeter { _ in "task\(index)" }
                    } operation: {
                        // Yield so the scopes genuinely interleave.
                        await Task.yield()
                        return KVDependencies.current.greeter.greet("")
                    }
                }
            }

            var seen: Set<String> = []
            for await value in group { seen.insert(value) }
            XCTAssertEqual(seen, Set((0..<8).map { "task\($0)" }))
        }
    }
}
