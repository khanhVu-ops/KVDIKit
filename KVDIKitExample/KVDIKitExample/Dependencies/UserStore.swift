//
//  UserStore.swift
//  KVDIKitExample
//

import Foundation
import KVDIKit

/// A reference-type dependency that belongs to one signed-in user.
///
/// It reports its own birth and death to ``ExampleTelemetry`` so the screen can show
/// the thing that matters about the session layer: `endSession()` really does release
/// it, rather than leaving the previous user's data hanging around.
final class UserStore: @unchecked Sendable {

    let userID: String
    let isSignedOut: Bool

    private(set) var drafts: [String] = []

    init(userID: String, isSignedOut: Bool = false) {
        self.userID = userID
        self.isSignedOut = isSignedOut
        guard !isSignedOut else { return }
        Task { @MainActor in ExampleTelemetry.shared.userStoreCreated() }
    }

    deinit {
        guard !isSignedOut else { return }
        // No capture of `self` — a deinit may not escape one.
        Task { @MainActor in ExampleTelemetry.shared.userStoreReleased() }
    }
}

enum UserStoreKey: KVDependencyKey {
    /// The app layer has no user, so it gets a store that stands for "nobody".
    static let liveValue = UserStore(userID: "—", isSignedOut: true)
}

extension KVDependencyValues {
    var userStore: UserStore {
        get { self[UserStoreKey.self] }
        set { self[UserStoreKey.self] = newValue }
    }
}
