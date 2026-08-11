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
public protocol KVDependencyKey {

    /// The dependency itself. A protocol existential works, but a struct of closures
    /// is usually easier to stub one method at a time.
    associatedtype Value: Sendable

    /// The real implementation.
    static var liveValue: Value { get }

    /// Used inside Xcode previews. Defaults to ``liveValue``.
    static var previewValue: Value { get }

    /// Used inside tests. Defaults to ``previewValue``, with a warning — see below.
    static var testValue: Value { get }
}

public extension KVDependencyKey {

    static var previewValue: Value { liveValue }

    static var testValue: Value {
        KVIssueReporter.reportOnce(
            id: String(reflecting: Self.self),
            """
            KVDIKit: "\(String(reflecting: Self.self))" has no testValue, so a test just \
            resolved its live value. Add `static let testValue` to the key, or override it \
            for this test with `withKVDependencies { $0.… = … }`.
            """
        )
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
