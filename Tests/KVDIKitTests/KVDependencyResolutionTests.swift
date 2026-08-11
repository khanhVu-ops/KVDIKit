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
