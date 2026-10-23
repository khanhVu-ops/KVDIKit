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

/// Serialises the calls that run caller code — `prepare` and `startSession` — without
/// holding ``KVLocked`` while that code runs.
///
/// Recursive on purpose: caller code may itself call `prepare` or `startSession`,
/// and a plain lock would hang the app there instead of letting the call through and
/// reporting it. Reads never take this lock, so resolving a dependency from inside
/// the caller's closure is always safe.
final class KVWriterGate: @unchecked Sendable {

    private let lock = NSRecursiveLock()
    /// Only touched while `lock` is held, and only by the thread holding it.
    private var depth = 0

    /// Run `body` exclusively. `isNested` is `true` when the calling thread is already
    /// inside another `run`.
    func run<Result>(_ body: (_ isNested: Bool) throws -> Result) rethrows -> Result {
        lock.lock()
        defer { lock.unlock() }
        depth += 1
        defer { depth -= 1 }
        return try body(depth > 1)
    }
}
