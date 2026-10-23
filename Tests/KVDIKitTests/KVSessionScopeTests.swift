//
//  KVSessionScopeTests.swift
//  KVDIKitTests
//

import XCTest
@testable import KVDIKit

final class KVSessionScopeTests: XCTestCase {

    override func setUp() {
        super.setUp()
        KVDependencies.resetForTesting()
    }

    override func tearDown() {
        KVDependencies.resetForTesting()
        super.tearDown()
    }

    // MARK: - App layer

    func testPrepareConfiguresTheAppLayer() {
        KVDependencies.prepare { $0.greeter = .shouting }
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
    }

    func testScopeShadowsTheAppLayer() {
        KVDependencies.prepare { $0.greeter = .shouting }

        withKVDependencies {
            $0.greeter = Greeter { "scoped:\($0)" }
        } operation: {
            XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "scoped:kv")
        }

        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
    }

    // MARK: - Session layer

    func testSessionOverridesTheAppLayerAndEndSessionRestoresIt() {
        KVDependencies.prepare { $0.greeter = .live }
        XCTAssertFalse(KVDependencies.isSessionActive)

        KVDependencies.startSession { $0.greeter = .shouting }
        XCTAssertTrue(KVDependencies.isSessionActive)
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")

        KVDependencies.endSession()
        XCTAssertFalse(KVDependencies.isSessionActive)
        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "live:kv")
    }

    func testSessionInheritsUntouchedAppDependencies() {
        KVDependencies.prepare { $0.greeter = .shouting }
        KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }

        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "SHOUT:KV")
        XCTAssertEqual(KVDependencies.current.userStore.userID, "u1")
    }

    func testSessionCanWrapAnAppDependency() {
        KVDependencies.prepare { $0.greeter = .live }
        KVDependencies.startSession { values in
            let base = values.greeter
            values.greeter = Greeter { "u1(\(base.greet($0)))" }
        }

        XCTAssertEqual(KVDependencies.current.greeter.greet("kv"), "u1(live:kv)")
    }

    func testExistingObjectsSeeTheSessionChange() {
        let reader = UserStoreReader()
        XCTAssertEqual(reader.userID, "signed-out")

        KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }
        XCTAssertEqual(reader.userID, "u1", "resolution happens per access, not at init")

        KVDependencies.endSession()
        XCTAssertEqual(reader.userID, "signed-out")
    }

    func testStartingASessionWhileOneIsOpenReplacesIt() {
        let first = KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }
        let second = KVDependencies.startSession { $0.userStore = UserStore(userID: "u2") }

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(KVDependencies.sessionID, second)
        XCTAssertEqual(KVDependencies.current.userStore.userID, "u2")
    }

    // MARK: - Lifetime

    func testEndSessionReleasesSessionDependencies() {
        weak var released: UserStore?

        func signIn() {
            let store = UserStore(userID: "u1")
            released = store
            KVDependencies.startSession { $0.userStore = store }
        }

        signIn()
        XCTAssertNotNil(released, "the session should hold the store while it is open")

        KVDependencies.endSession()
        XCTAssertNil(released, "signing out should drop the previous user's objects")
    }

    // MARK: - Observation

    func testSessionChangesAreObservable() async {
        let stream = KVDependencies.sessionChanges
        var iterator = stream.makeAsyncIterator()

        let id = KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }
        let opened = await iterator.next()
        XCTAssertEqual(opened, id)

        KVDependencies.endSession()
        let closed = await iterator.next()
        XCTAssertNotNil(closed, "the stream should yield on sign-out, not finish")
        XCTAssertNil(closed ?? nil, "sign-out yields nil")
    }

    func testSessionChangesWithoutReplayStillSkipsTheCurrentState() async {
        let id = KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }
        var iterator = KVDependencies.sessionChanges.makeAsyncIterator()

        KVDependencies.endSession()
        let first = await iterator.next()
        XCTAssertNotEqual(first ?? nil, id, "the plain stream does not replay the open session")
        XCTAssertNil(first ?? nil)
    }

    func testSessionChangesCanStartWithTheCurrentSession() async {
        let id = KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }
        var iterator = KVDependencies.sessionChanges(includingCurrent: true).makeAsyncIterator()

        let current = await iterator.next()
        XCTAssertEqual(current, id, "a late subscriber hears the session already open")

        KVDependencies.endSession()
        let closed = await iterator.next()
        XCTAssertEqual(closed, .some(nil))
    }

    func testSessionChangesReplaysSignedOutAsNil() async {
        var iterator = KVDependencies.sessionChanges(includingCurrent: true).makeAsyncIterator()
        let current = await iterator.next()
        XCTAssertEqual(current, .some(nil))

        let id = KVDependencies.startSession { $0.userStore = UserStore(userID: "u1") }
        let opened = await iterator.next()
        XCTAssertEqual(opened, id)
    }
}
