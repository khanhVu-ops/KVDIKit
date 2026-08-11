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

// MARK: - A reference-type dependency

/// Stands in for a per-user store: created at sign-in, expected to die at sign-out.
final class UserStore: @unchecked Sendable {
    let userID: String

    init(userID: String) {
        self.userID = userID
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

    var userStore: UserStore {
        get { self[UserStoreKey.self] }
        set { self[UserStoreKey.self] = newValue }
    }
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
