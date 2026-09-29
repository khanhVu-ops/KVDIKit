//
//  KVReentrancyTests.swift
//  KVDIKitTests
//

import XCTest
@testable import KVDIKit

/// `prepare` and `startSession` run caller code. That code is allowed to resolve
/// dependencies — directly, or through a key whose `liveValue` resolves another key —
/// without hanging the app.
final class KVReentrancyTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KVDependencies.resetForTesting()
    }

    override func tearDown() {
        KVDependencies.resetForTesting()
        super.tearDown()
    }

    // MARK: - Resolving inside the closures

    func testPrepareClosureCanResolveDependencies() {
        assertCompletes {
            KVDependencies.prepare { values in
                let base = KVDependencies.current.greeter
                values.greeter = Greeter { "prepared(\(base.greet($0)))" }
            }
        }
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "prepared(test:kv)")
    }

    func testStartSessionClosureCanResolveDependencies() {
        assertCompletes {
            KVDependencies.startSession { values in
                // A dependency built at sign-in that reads another one while it is built.
                values.userStore = UserStore(userID: GreetingModel().greet("u1"))
            }
        }
        XCTAssertEqual(KVDependencies.current.userStore.userID, "test:u1")
    }

    func testStartSessionClosureCanReadSessionState() {
        assertCompletes {
            KVDependencies.startSession { values in
                values.userStore = UserStore(userID: "active=\(KVDependencies.isSessionActive)")
            }
        }
        XCTAssertEqual(KVDependencies.current.userStore.userID, "active=false")
    }

    func testLazyLiveValueThatResolvesAnotherKeyInsideStartSession() {
        // `ChainedKey.liveValue` is first touched inside the closure, and its initialiser
        // resolves `GreeterKey` through `KVDependencies.current`.
        assertCompletes {
            KVDependencies.startSession { values in
                values.userStore = UserStore(userID: values.chained.greet("kv"))
            }
        }
        XCTAssertEqual(KVDependencies.current.userStore.userID, "chained(test:kv)")
    }

    func testReleasedSessionObjectsCanResolveDependenciesInDeinit() {
        let flushed = KVLocked<[String]>([])
        KVDependencies.startSession { values in
            values.userStore = FlushingUserStore(userID: "u1") { line in
                flushed.withLock { $0.append(line) }
            }
        }

        assertCompletes {
            // Replacing the session releases u1's store…
            KVDependencies.startSession { $0.userStore = UserStore(userID: "u2") }
            // …and ending it releases nothing that flushes, but must not hang either.
            KVDependencies.endSession()
        }
        XCTAssertEqual(flushed.withLock { $0 }, ["test:u1"])
    }

    // MARK: - Atomic publish

    func testValuesSetInOneClosureArePublishedTogether() {
        KVDependencies.prepare { $0.greeter = .live }

        let seenInsideClosure = KVLocked<String?>(nil)
        KVDependencies.startSession { values in
            values.greeter = .shouting
            // Not published yet: other readers still see the previous layer.
            seenInsideClosure.withLock { $0 = KVDependencies.current.greeter.greet("kv") }
            values.userStore = UserStore(userID: "u1")
        }

        XCTAssertEqual(seenInsideClosure.withLock { $0 }, "live:kv")
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
        XCTAssertEqual(KVDependencies.current.userStore.userID, "u1")
    }

    func testConcurrentPreparesDoNotLoseUpdates() {
        let iterations = 200
        DispatchQueue.concurrentPerform(iterations: iterations) { index in
            if index.isMultiple(of: 2) {
                KVDependencies.prepare { $0.greeter = .shouting }
            } else {
                KVDependencies.prepare { $0.userStore = UserStore(userID: "u\(index)") }
            }
        }
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
        XCTAssertNotEqual(KVDependencies.current.userStore.userID, "signed-out")
    }

    // MARK: - Nesting

    func testNestedPrepareIsReportedInsteadOfDeadlocking() {
        let reported = KVLocked<[String]>([])
        let original = KVIssueReporter.handler
        KVIssueReporter.handler = { message in reported.withLock { $0.append(message) } }
        defer { KVIssueReporter.handler = original }

        assertCompletes {
            KVDependencies.prepare { outer in
                KVDependencies.prepare { $0.userStore = UserStore(userID: "inner") }
                outer.greeter = .shouting
            }
        }

        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
        XCTAssertTrue(reported.withLock { $0 }.contains { $0.contains("nested") })
    }

    // MARK: - Helpers

    /// Runs `body` on its own thread and fails if it has not returned in time.
    ///
    /// A deadlock here means the package lock is held forever, which would hang every
    /// test after this one — so a timeout stops the process instead of letting the
    /// suite spin until CI kills it.
    private func assertCompletes(
        within timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: @escaping @Sendable () -> Void
    ) {
        let finished = expectation(description: "operation returned")
        let thread = Thread {
            body()
            finished.fulfill()
        }
        thread.start()

        let result = XCTWaiter().wait(for: [finished], timeout: timeout)
        guard result == .completed else {
            XCTFail("deadlocked: the operation did not return within \(timeout)s", file: file, line: line)
            fatalError("KVDIKit deadlocked in \(name); aborting so the remaining tests do not hang.")
        }
    }
}
