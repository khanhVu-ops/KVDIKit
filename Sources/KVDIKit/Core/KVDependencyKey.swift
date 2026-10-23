//
//  KVDependencyKey.swift
//  KVDIKit
//

import Foundation

/// Describes one dependency: its type, and what to hand out per context.
///
/// A key is the whole registration step — there is no container to populate and
/// nothing to remember to call at launch. Because ``liveValue`` is a static
/// requirement, a dependency that has no value simply does not compile; there is no
/// runtime "unregistered type" failure to hit in production.
///
/// ```swift
/// enum AuthClientKey: KVDependencyKey {
///     static let liveValue = AuthClient.live
///     static let testValue = AuthClient.mock
/// }
///
/// extension KVDependencyValues {
///     var authClient: AuthClient {
///         get { self[AuthClientKey.self] }
///         set { self[AuthClientKey.self] = newValue }
///     }
/// }
/// ```
///
/// `Value` must be `Sendable` — dependencies are resolved from any isolation domain.
/// In practice that means a struct of closures (the `AuthClient.live` shape above),
/// an `actor`, or a `@MainActor` class; all three satisfy it without ceremony.
///
/// In a target built with default `MainActor` isolation, declare keys (and their
/// `KVDependencyValues` extension) `nonisolated` — see "Default MainActor isolation"
/// in the README.
public protocol KVDependencyKey {

    /// The dependency itself. A protocol existential works, but a struct of closures
    /// is usually easier to stub one method at a time.
    associatedtype Value: Sendable

    /// The real implementation.
    static var liveValue: Value { get }

    /// Used inside Xcode previews. Defaults to ``liveValue``.
    static var previewValue: Value { get }

    /// Used inside tests. Defaults to ``previewValue``, and reports the key as
    /// unstubbed according to ``KVDependencies/testValuePolicy``.
    ///
    /// A key whose live value is genuinely safe in tests (a pure formatter, a clock
    /// wrapper you never stub) can say so and stay quiet under either policy:
    ///
    /// ```swift
    /// static var testValue: Value { liveValue }
    /// ```
    static var testValue: Value { get }
}

/// What happens when a test resolves a key that declares no `testValue`.
///
/// Set with ``KVDependencies/testValuePolicy``.
public enum KVTestValuePolicy: Sendable, Hashable, CaseIterable {

    /// Report a runtime issue through ``KVIssueReporter/handler``, once per key, and
    /// carry on with the live value. The default — this is how 1.0 behaved.
    case warn

    /// Fail the running test through ``KVIssueReporter/failureHandler`` on *every*
    /// access, then carry on with the live value. Use it to make an unstubbed
    /// dependency impossible to miss.
    case fail
}

public extension KVDependencyKey {

    static var previewValue: Value { liveValue }

    static var testValue: Value {
        let key = String(reflecting: Self.self)
        let message = """
            KVDIKit: "\(key)" has no testValue, so a test just resolved its live value. \
            Add `static let testValue` to the key, or override it for this test with \
            `withKVDependencies { $0.… = … }`.
            """
        switch KVDependencies.testValuePolicy {
        case .warn:
            KVIssueReporter.reportOnce(id: key, message)
        case .fail:
            KVIssueReporter.fail(message)
        }
        return previewValue
    }

    /// The value this key hands out in `context`, before any override is applied.
    static func value(for context: KVDependencyContext) -> Value {
        switch context {
        case .live: liveValue
        case .preview: previewValue
        case .test: testValue
        }
    }
}
