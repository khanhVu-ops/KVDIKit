//
//  KVDependencies.swift
//  KVDIKit
//

import Foundation

/// Identifies one run of the session scope.
///
/// Handy for tagging cached work so anything produced under a previous sign-in can
/// be recognised — and dropped — after the user switches account.
public struct KVSessionID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// The two long-lived dependency layers: app and session.
///
/// - **App layer** — configured once at launch with ``prepare(_:)``. Everything
///   that lives as long as the process does.
/// - **Session layer** — opened at sign-in with ``startSession(id:_:)`` and dropped
///   at sign-out with ``endSession()``. Dependencies that belong to *one signed-in
///   user* (a token-carrying API client, a per-user store) go here, so signing out
///   releases them instead of leaving a stale object holding the previous user's data.
///
/// A third, shorter-lived layer exists on top of these: `withKVDependencies(_:operation:)`,
/// which shadows both for the duration of a call. That is the one tests use.
public enum KVDependencies {

    // MARK: Storage

    private struct Storage {
        var app = KVDependencyValues()
        /// Nil when signed out. Holds a full copy of the app layer plus the session's
        /// own overrides, so resolving never has to merge dictionaries.
        var session: KVDependencyValues?
        var sessionID: KVSessionID?

        var effective: KVDependencyValues { session ?? app }
    }

    private static let storage = KVLocked(Storage())
    private static let sessionObservers = KVLocked<[UUID: AsyncStream<KVSessionID?>.Continuation]>([:])

    // MARK: Resolving

    /// The values in force right now: the innermost `withKVDependencies` scope if one
    /// is open, otherwise the session layer, otherwise the app layer.
    public static var current: KVDependencyValues {
        KVDependencyValues.scoped ?? storage.withLock { $0.effective }
    }

    /// The long-lived layers only, ignoring any open scope. Used by ``KVDependency``
    /// so a value captured at `init` never pins a dependency the session has replaced.
    static var effective: KVDependencyValues {
        storage.withLock { $0.effective }
    }

    // MARK: App layer

    /// Configure the app layer. Call once, at launch, before anything resolves.
    ///
    /// ```swift
    /// @main
    /// struct MyApp: App {
    ///     init() {
    ///         KVDependencies.prepare {
    ///             $0.apiClient = .live(baseURL: .production)
    ///             $0.analytics = .firebase
    ///         }
    ///     }
    /// }
    /// ```
    ///
    /// Most dependencies need nothing here — a key's `liveValue` already is the app
    /// layer. Reach for `prepare` when the value depends on something only known at
    /// launch, like a build configuration or a launch argument.
    public static func prepare(_ mutate: (inout KVDependencyValues) -> Void) {
        let hadSession: Bool = storage.withLock { storage in
            mutate(&storage.app)
            return storage.session != nil
        }
        if hadSession {
            KVIssueReporter.report(
                """
                KVDIKit: prepare(_:) ran while a session was open, so the change does not \
                reach the session layer — it applies from the next startSession(id:_:) on. \
                Call prepare(_:) at launch instead.
                """
            )
        }
    }

    // MARK: Session layer

    /// `true` while a session is open.
    public static var isSessionActive: Bool {
        storage.withLock { $0.session != nil }
    }

    /// The open session's id, or `nil` when signed out.
    public static var sessionID: KVSessionID? {
        storage.withLock { $0.sessionID }
    }

    /// Open the session scope, overriding dependencies for as long as the user stays
    /// signed in.
    ///
    /// ```swift
    /// KVDependencies.startSession {
    ///     $0.apiClient = .authenticated(token: token)
    ///     $0.userStore = UserStore(userID: user.id)
    /// }
    /// ```
    ///
    /// Values are built eagerly, here, and released by ``endSession()``. Calling this
    /// while a session is open replaces it — that is the account-switch path, and the
    /// previous session's objects are dropped in the process.
    @discardableResult
    public static func startSession(
        id: KVSessionID = KVSessionID(),
        _ configure: (inout KVDependencyValues) -> Void
    ) -> KVSessionID {
        storage.withLock { storage in
            // Start from the app layer so a session override can wrap what it replaces
            // (`$0.apiClient = .authenticated(wrapping: $0.apiClient, …)`).
            var values = storage.app
            configure(&values)
            storage.session = values
            storage.sessionID = id
        }
        notifySessionObservers(id)
        return id
    }

    /// Close the session scope and release everything it held.
    ///
    /// Dependencies fall back to the app layer. No-op when signed out.
    public static func endSession() {
        let wasActive: Bool = storage.withLock { storage in
            guard storage.session != nil else { return false }
            storage.session = nil
            storage.sessionID = nil
            return true
        }
        guard wasActive else { return }
        notifySessionObservers(nil)
    }

    /// Session boundaries as they happen: the new ``KVSessionID`` on sign-in, `nil`
    /// on sign-out.
    ///
    /// ```swift
    /// for await session in KVDependencies.sessionChanges {
    ///     if session == nil { await router.popToRoot() }
    /// }
    /// ```
    ///
    /// Each call returns its own stream, so several observers can watch at once.
    public static var sessionChanges: AsyncStream<KVSessionID?> {
        AsyncStream { continuation in
            let token = UUID()
            sessionObservers.withLock { $0[token] = continuation }
            continuation.onTermination = { _ in
                sessionObservers.withLock { _ = $0.removeValue(forKey: token) }
            }
        }
    }

    private static func notifySessionObservers(_ id: KVSessionID?) {
        let continuations = sessionObservers.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(id)
        }
    }

    // MARK: Testing

    /// Drop both long-lived layers. Used by the package's own tests; also useful in a
    /// host app's test `setUp` when a previous test called ``prepare(_:)``.
    public static func resetForTesting() {
        storage.withLock { $0 = Storage() }
    }
}
