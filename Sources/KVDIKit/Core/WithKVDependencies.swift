//
//  WithKVDependencies.swift
//  KVDIKit
//

import Foundation

public extension KVDependencyValues {

    /// The scope opened by `withKVDependencies(_:operation:)`, if any.
    ///
    /// A task local rather than a global: the override reaches every child task of the
    /// caller and nothing else, so tests that override the same dependency in different
    /// ways still run in parallel without stepping on each other.
    @TaskLocal internal static var scoped: KVDependencyValues?
}

/// Run `operation` with some dependencies replaced.
///
/// ```swift
/// func testSignInFailure() {
///     withKVDependencies {
///         $0.authClient = .alwaysFailing
///     } operation: {
///         let model = LoginViewModel()
///         model.signIn()
///         XCTAssertEqual(model.error, .invalidCredentials)
///     }
/// }
/// ```
///
/// Overrides nest: an inner call sees the outer one's values and can replace more of
/// them. Nothing global is mutated, so there is no teardown to forget.
///
/// An object created inside the scope keeps it — see ``KVDependency`` — which is what
/// makes the pattern above work even when the model is used after `operation` returns.
@discardableResult
public func withKVDependencies<Result>(
    _ mutate: (inout KVDependencyValues) -> Void,
    operation: () throws -> Result
) rethrows -> Result {
    var values = KVDependencies.current
    mutate(&values)
    return try KVDependencyValues.$scoped.withValue(values, operation: operation)
}

/// Run an async `operation` with some dependencies replaced.
///
/// The override follows structured concurrency: child tasks spawned inside
/// `operation` inherit it, a detached task does not.
@discardableResult
public func withKVDependencies<Result>(
    _ mutate: (inout KVDependencyValues) -> Void,
    isolation: isolated (any Actor)? = #isolation,
    operation: () async throws -> Result
) async rethrows -> Result {
    var values = KVDependencies.current
    mutate(&values)
    return try await KVDependencyValues.$scoped.withValue(values) {
        try await operation()
    }
}
