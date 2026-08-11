//
//  KVLocked.swift
//  KVDIKit
//

import Foundation

/// Minimal lock-guarded box.
///
/// Dependency resolution happens from any isolation domain — a `@MainActor` view
/// model, a detached `Task`, a background actor — so the little global state this
/// package keeps (the app layer, the session layer, the warn-once set) lives behind
/// a plain lock rather than an actor. Reads stay synchronous, which is what a
/// property getter needs.
final class KVLocked<Value>: @unchecked Sendable {

    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
