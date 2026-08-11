//
//  View+KVDependencies.swift
//  KVDIKit
//

import SwiftUI

// MARK: - Environment bridge

private struct KVDependenciesEnvironmentKey: EnvironmentKey {
    static let defaultValue: KVDependencyValues? = nil
}

public extension EnvironmentValues {

    /// Dependency overrides installed by ``SwiftUI/View/kvDependencies(_:)``, or `nil`
    /// when the hierarchy has none.
    var kvDependencies: KVDependencyValues? {
        get { self[KVDependenciesEnvironmentKey.self] }
        set { self[KVDependenciesEnvironmentKey.self] = newValue }
    }
}

public extension View {

    /// Override dependencies for this part of the view tree.
    ///
    /// ```swift
    /// #Preview {
    ///     PostsView()
    ///         .kvDependencies {
    ///             $0.apiClient = .stubbed(posts: .sample)
    ///         }
    /// }
    /// ```
    ///
    /// This is the preview and view-body counterpart of
    /// `withKVDependencies(_:operation:)`: SwiftUI evaluates a body outside the task
    /// that built it, so a task-local override cannot reach it — the environment can.
    ///
    /// Only ``KVViewDependency`` reads these. A model constructed in the body still
    /// resolves through the session and app layers.
    func kvDependencies(_ mutate: @escaping (inout KVDependencyValues) -> Void) -> some View {
        modifier(KVDependenciesModifier(mutate: mutate))
    }
}

private struct KVDependenciesModifier: ViewModifier {

    @Environment(\.kvDependencies) private var inherited

    let mutate: (inout KVDependencyValues) -> Void

    func body(content: Content) -> some View {
        // Nested modifiers compose: start from whatever an ancestor installed.
        var values = inherited ?? KVDependencies.current
        mutate(&values)
        return content.environment(\.kvDependencies, values)
    }
}

// MARK: - Reading inside a view

/// Reads a dependency inside a SwiftUI view body, honouring ``SwiftUI/View/kvDependencies(_:)``.
///
/// ```swift
/// struct FeatureFlagBadge: View {
///     @KVViewDependency(\.featureFlags) private var flags
///
///     var body: some View {
///         if flags.isEnabled(.newBadge) { … }
///     }
/// }
/// ```
///
/// Use ``KVDependency`` everywhere else. This exists for the cases where a view genuinely
/// needs the dependency itself — mostly so previews can stub it.
@propertyWrapper
public struct KVViewDependency<Value>: DynamicProperty {

    @Environment(\.kvDependencies) private var scoped

    private let keyPath: KeyPath<KVDependencyValues, Value> & Sendable

    public init(_ keyPath: KeyPath<KVDependencyValues, Value> & Sendable) {
        self.keyPath = keyPath
    }

    public var wrappedValue: Value {
        (scoped ?? KVDependencies.current)[keyPath: keyPath]
    }
}
