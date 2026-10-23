//
//  TestDependencies.swift
//  KVDIKitTests
//

import Foundation
@testable import KVDIKit

// MARK: - A struct-of-closures dependency

/// The shape most dependencies take: a value type holding closures, so a test can
/// replace one endpoint without conforming to a whole protocol.
struct Greeter: Sendable {
    var greet: @Sendable (String) -> String

    static let live = Greeter { "live:\($0)" }
    static let preview = Greeter { "preview:\($0)" }
    static let test = Greeter { "test:\($0)" }
    static let shouting = Greeter { "SHOUT:\($0.uppercased())" }
}

enum GreeterKey: KVDependencyKey {
    static let liveValue = Greeter.live
    static let previewValue = Greeter.preview
    static let testValue = Greeter.test
}

/// Deliberately has no `testValue`, to exercise the warn-and-fall-back path.
enum UnstubbedGreeterKey: KVDependencyKey {
    static let liveValue = Greeter.live
}

/// A key whose value is built from another dependency the first time it is touched —
/// the shape that must not deadlock when first resolved inside `startSession`.
/// Only `testLazyLiveValueThatResolvesAnotherKeyInsideStartSession` reads it, so the
/// lazy initialiser really does run inside that test's closure.
enum ChainedKey: KVDependencyKey {
    static let liveValue: Greeter = {
        let base = KVDependencies.current.greeter
        return Greeter { "chained(\(base.greet($0)))" }
    }()
    static var testValue: Greeter { liveValue }
}

/// Declares that its live value is fine in tests — no report under either policy.
enum LiveInTestsKey: KVDependencyKey {
    static let liveValue = Greeter.live
    static var testValue: Greeter { liveValue }
}

// MARK: - A reference-type dependency

/// Stands in for a per-user store: created at sign-in, expected to die at sign-out.
class UserStore: @unchecked Sendable {
    let userID: String

    init(userID: String) {
        self.userID = userID
    }
}

/// A per-user store that flushes through another dependency when it is released —
/// its `deinit` runs while `endSession()` drops the session.
final class FlushingUserStore: UserStore, @unchecked Sendable {
    let onFlush: @Sendable (String) -> Void

    init(userID: String, onFlush: @escaping @Sendable (String) -> Void) {
        self.onFlush = onFlush
        super.init(userID: userID)
    }

    deinit {
        onFlush(KVDependencies.current.greeter.greet(userID))
    }
}

enum UserStoreKey: KVDependencyKey {
    static let liveValue = UserStore(userID: "signed-out")
}

extension KVDependencyValues {

    var greeter: Greeter {
        get { self[GreeterKey.self] }
        set { self[GreeterKey.self] = newValue }
    }

    var unstubbedGreeter: Greeter {
        get { self[UnstubbedGreeterKey.self] }
        set { self[UnstubbedGreeterKey.self] = newValue }
    }

    var chained: Greeter {
        get { self[ChainedKey.self] }
        set { self[ChainedKey.self] = newValue }
    }

    var liveInTests: Greeter {
        get { self[LiveInTestsKey.self] }
        set { self[LiveInTestsKey.self] = newValue }
    }

    var userStore: UserStore {
        get { self[UserStoreKey.self] }
        set { self[UserStoreKey.self] = newValue }
    }

    var optionalGreeter: Greeter? {
        get { self[OptionalGreeterKey.self] }
        set { self[OptionalGreeterKey.self] = newValue }
    }
}

// MARK: - An Optional dependency

/// "Feature off" modelled as `nil`: the key's own values are non-nil, so a `nil` read
/// can only come from an explicit override.
enum OptionalGreeterKey: KVDependencyKey {
    static let liveValue: Greeter? = .live
    static let testValue: Greeter? = .test
}

// MARK: - Consumers

/// Reads its dependency on every access, the way app code does.
final class GreetingModel: @unchecked Sendable {
    @KVDependency(\.greeter) private var greeter

    func greet(_ name: String) -> String {
        greeter.greet(name)
    }
}

final class UserStoreReader: @unchecked Sendable {
    @KVDependency(\.userStore) private var store

    var userID: String { store.userID }
}
