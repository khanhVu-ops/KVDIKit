//
//  KVDependency.swift
//  KVDIKit
//

import Foundation

/// Reads a dependency by key path.
///
/// ```swift
/// @MainActor
/// final class LoginViewModel: ObservableObject {
///     @KVDependency(\.authClient) private var auth
///     @KVDependency(\.analytics) private var analytics
///
///     func signIn(email: String, password: String) async { … }
/// }
/// ```
///
/// The dependency is looked up when the property is *read*, not when the object is
/// built, so a value the session layer replaces at sign-in is picked up by objects
/// that already exist.
///
/// The one exception is a scope: if the property wrapper is created inside
/// `withKVDependencies(_:operation:)`, it holds on to that scope. Without this, a
/// view model built inside a test's override would quietly fall back to live values
/// the moment the test touched it outside the `operation` closure.
///
/// Resolution order, then:
/// 1. the `withKVDependencies` scope open on the current task,
/// 2. else the scope this wrapper was created in,
/// 3. else the session layer, then the app layer, then the key's own value.
///
/// Reading in a SwiftUI `body` works too, but overrides applied with
/// `.kvDependencies { … }` are only visible to ``KVViewDependency`` — a task local
/// cannot reach into a view body. Prefer keeping dependencies in the model.
@propertyWrapper
public struct KVDependency<Value>: Sendable {

    private let keyPath: KeyPath<KVDependencyValues, Value> & Sendable
    /// The scope in force at `init`, if any. Nil in normal app code — which is what
    /// lets app code see later session changes.
    private let captured: KVDependencyValues?

    public init(_ keyPath: KeyPath<KVDependencyValues, Value> & Sendable) {
        self.keyPath = keyPath
        self.captured = KVDependencyValues.scoped
    }

    public var wrappedValue: Value {
        let values = KVDependencyValues.scoped ?? captured ?? KVDependencies.effective
        return values[keyPath: keyPath]
    }
}
