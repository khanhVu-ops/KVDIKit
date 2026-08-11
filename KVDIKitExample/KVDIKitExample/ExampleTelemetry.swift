//
//  ExampleTelemetry.swift
//  KVDIKitExample
//

import SwiftUI

/// Example-only scaffolding: collects what the dependencies below do, so the screen
/// can show which implementation is actually in force. Not part of KVDIKit.
@MainActor
final class ExampleTelemetry: ObservableObject {

    static let shared = ExampleTelemetry()

    /// Newest first.
    @Published private(set) var events: [String] = []

    /// How many per-user stores are alive. The point of the session layer is that this
    /// drops back to zero on sign-out.
    @Published private(set) var liveUserStores = 0

    private init() {}

    func record(_ line: String) {
        events.insert(line, at: 0)
        if events.count > 12 { events.removeLast() }
    }

    func userStoreCreated() { liveUserStores += 1 }
    func userStoreReleased() { liveUserStores -= 1 }

    func clear() { events.removeAll() }
}
