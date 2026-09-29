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

    /// Guards `Storage`. Never held while caller code runs — not a `prepare` or
    /// `startSession` closure, not a key's lazy `liveValue`, not the `deinit` of a
    /// dependency being released — so any of those can resolve dependencies freely.
    private static let storage = KVLocked(Storage())
    /// Serialises `prepare` and `startSession`, whose closures run outside `storage`.
    private static let writers = KVWriterGate()
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
    ///
    /// The closure runs on a copy of the app layer, outside the package's lock, so it
    /// may resolve dependencies (`KVDependencies.current`, `@KVDependency`, a key whose
    /// `liveValue` reads another key). Those reads see the layer as it was *before*
    /// this call; everything the closure sets is published together when it returns.
    public static func prepare(_ mutate: (inout KVDependencyValues) -> Void) {
        writers.run { isNested in
            if isNested { reportNestedConfiguration("prepare(_:)") }

            var app = storage.withLock { $0.app }
            mutate(&app)

            let (hadSession, replaced) = storage.withLock { storage in
                let replaced = storage.app
                storage.app = app
                return (storage.session != nil, replaced)
            }
            // Released here, after the lock, in case a `deinit` resolves a dependency.
            _ = replaced
            if hadSession { reportPrepareDuringSession() }
        }
    }

    private static func reportPrepareDuringSession() {
        KVIssueReporter.report(
            """
            KVDIKit: prepare(_:) ran while a session was open, so the change does not \
            reach the session layer — it applies from the next startSession(id:_:) on. \
            Call prepare(_:) at launch instead.
            """
        )
    }

    private static func reportNestedConfiguration(_ function: String) {
        KVIssueReporter.report(
            """
            KVDIKit: \(function) was called from inside another prepare(_:) or \
            startSession(id:_:) closure (nested). It runs, but the enclosing call publishes \
            its own copy when its closure returns, which replaces what the nested call set. \
            Set the value on the enclosing closure's `values` instead.
            """
        )
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
    ///
    /// Like ``prepare(_:)``, the closure runs outside the package's lock and may resolve
    /// dependencies; it sees the layers as they were before the call (the previous
    /// session, if one is open). The new session — every value the closure set, and
    /// its id — becomes visible in one step when the closure returns.
    @discardableResult
    public static func startSession(
        id: KVSessionID = KVSessionID(),
        _ configure: (inout KVDependencyValues) -> Void
    ) -> KVSessionID {
        writers.run { isNested in
            if isNested { reportNestedConfiguration("startSession(id:_:)") }

            // Start from the app layer so a session override can wrap what it replaces
            // (`$0.apiClient = .authenticated(wrapping: $0.apiClient, …)`).
            var values = storage.withLock { $0.app }
            configure(&values)

            let replaced = storage.withLock { storage in
                let replaced = storage.session
                storage.session = values
                storage.sessionID = id
                // Under the lock so observers see boundaries in the order they happened.
                notifySessionObservers(id)
                return replaced
            }
            // The previous session's objects die here, outside the lock.
            _ = replaced
        }
        return id
    }

    /// Close the session scope and release everything it held.
    ///
    /// Dependencies fall back to the app layer. No-op when signed out.
    public static func endSession() {
        let released = storage.withLock { storage -> KVDependencyValues? in
            guard let session = storage.session else { return nil }
            storage.session = nil
            storage.sessionID = nil
            notifySessionObservers(nil)
            return session
        }
        // The session's objects die here, outside the lock, so a `deinit` that
        // resolves a dependency cannot deadlock.
        _ = released
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
    ///
    /// Only *changes* are delivered — a subscriber that starts listening mid-session
    /// hears nothing until the next boundary. Use ``sessionChanges(includingCurrent:)``
    /// to receive the current state first, or read ``sessionID``.
    public static var sessionChanges: AsyncStream<KVSessionID?> {
        sessionChanges(includingCurrent: false)
    }

    /// Session boundaries, optionally starting with the state in force right now.
    ///
    /// ```swift
    /// for await session in KVDependencies.sessionChanges(includingCurrent: true) {
    ///     showSignedIn(session != nil)   // runs once immediately, then per boundary
    /// }
    /// ```
    ///
    /// With `includingCurrent: true` the first element is ``sessionID`` at the moment
    /// of the call (`nil` when signed out). Reading it and subscribing happen in one
    /// step, so no boundary can slip in between and none is delivered twice.
    public static func sessionChanges(includingCurrent: Bool) -> AsyncStream<KVSessionID?> {
        AsyncStream { continuation in
            let token = UUID()
            continuation.onTermination = { _ in
                sessionObservers.withLock { _ = $0.removeValue(forKey: token) }
            }
            if includingCurrent {
                storage.withLock { storage in
                    sessionObservers.withLock { $0[token] = continuation }
                    continuation.yield(storage.sessionID)
                }
            } else {
                sessionObservers.withLock { $0[token] = continuation }
            }
        }
    }

    /// Called with `storage` locked. `yield` only buffers — it never runs observer
    /// code synchronously — so this cannot re-enter the package.
    private static func notifySessionObservers(_ id: KVSessionID?) {
        let continuations = sessionObservers.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(id)
        }
    }

    // MARK: Testing

    /// How strictly a test treats a key that declares no `testValue`.
    ///
    /// Defaults to ``KVTestValuePolicy/warn``. Switch to ``KVTestValuePolicy/fail``
    /// once, before the tests run — in a test case's `class func setUp()`, or a test
    /// bundle's principal class:
    ///
    /// ```swift
    /// override class func setUp() {
    ///     super.setUp()
    ///     KVDependencies.testValuePolicy = .fail
    /// }
    /// ```
    public static var testValuePolicy: KVTestValuePolicy {
        get { testValuePolicyBox.withLock { $0 } }
        set { testValuePolicyBox.withLock { $0 = newValue } }
    }

    private static let testValuePolicyBox = KVLocked(KVTestValuePolicy.warn)

    /// Drop both long-lived layers. Used by the package's own tests; also useful in a
    /// host app's test `setUp` when a previous test called ``prepare(_:)``.
    public static func resetForTesting() {
        let released = storage.withLock { storage in
            let released = storage
            storage = Storage()
            return released
        }
        _ = released
    }
}
