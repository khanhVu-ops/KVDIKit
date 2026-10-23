//
//  KVMainActorIsolationTests.swift
//  KVDIKitMainActorTests
//
//  This target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, like a new
//  Xcode 26 app. Everything below is written the way the README tells such an app to
//  write it: `nonisolated` on each key, and on the `KVDependencyValues` extension.
//

import XCTest
import KVDIKit

// MARK: - Declared as an app with default MainActor isolation would

struct Clock: Sendable {
    var now: @Sendable () -> String
}

/// Without `nonisolated` the conformance would be inferred main actor-isolated, and the
/// nonisolated extension below could not use it.
nonisolated enum ClockKey: KVDependencyKey {
    static let liveValue = Clock { "live" }
    static let testValue = Clock { "test" }
}

/// A `@MainActor` reference type as a dependency.
final class Session {
    var userName = "signed-out"
}

nonisolated enum SessionKey: KVDependencyKey {
    static let liveValue = Session()
    static var testValue: Session { liveValue }
}

/// Key paths handed to `@KVDependency` must be `Sendable`, which a key path to a main
/// actor-isolated property is not.
nonisolated extension KVDependencyValues {
    var clock: Clock {
        get { self[ClockKey.self] }
        set { self[ClockKey.self] = newValue }
    }

    var session: Session {
        get { self[SessionKey.self] }
        set { self[SessionKey.self] = newValue }
    }
}

/// A struct, not a class: with a macOS 13 deployment target, the Swift 6.2 runtime
/// crashes releasing *any* class instance from a default-MainActor test target
/// (`swift_task_deinitOnExecutorMainActorBackDeploy`), KVDIKit or not.
struct ClockModel {
    @KVDependency(\.clock) private var clock
    @KVDependency(\.session) private var session

    var reading: String { "\(clock.now())/\(session.userName)" }
}

// MARK: - Tests

/// `nonisolated` only because `XCTestCase`'s initialisers are — nothing to do with KVDIKit.
nonisolated final class KVMainActorIsolationTests: XCTestCase {

    @MainActor
    func testKeysResolveOnTheMainActor() {
        XCTAssertEqual(ClockModel().reading, "test/signed-out")
    }

    func testKeysResolveOffTheMainActor() async {
        let now = await Task.detached { KVDependencies.current.clock.now() }.value
        XCTAssertEqual(now, "test")
    }

    @MainActor
    func testOverridesWork() {
        withKVDependencies {
            $0.clock = Clock { "scoped" }
        } operation: {
            XCTAssertEqual(ClockModel().reading, "scoped/signed-out")
        }
    }
}
