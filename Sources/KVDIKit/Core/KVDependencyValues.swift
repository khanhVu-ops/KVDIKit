//
//  KVDependencyValues.swift
//  KVDIKit
//

import Foundation

/// A set of dependency overrides, plus the context to fall back on.
///
/// Extend it with one computed property per dependency so the rest of the app can
/// refer to it by key path:
///
/// ```swift
/// extension KVDependencyValues {
///     var authClient: AuthClient {
///         get { self[AuthClientKey.self] }
///         set { self[AuthClientKey.self] = newValue }
///     }
/// }
/// ```
///
/// The struct only stores what has actually been set. Anything untouched resolves
/// through the key itself, so adding a dependency never means revisiting the places
/// that build a `KVDependencyValues`.
public struct KVDependencyValues: Sendable {

    /// Which flavour untouched keys resolve to. Defaults to ``KVDependencyContext/detected``.
    public var context: KVDependencyContext

    /// Explicit overrides, keyed by the key type's identity.
    private var overrides: [ObjectIdentifier: any Sendable]

    public init(context: KVDependencyContext = .detected) {
        self.context = context
        self.overrides = [:]
    }

    /// Read or override the value for `key`.
    public subscript<Key: KVDependencyKey>(key: Key.Type) -> Key.Value {
        get {
            if let overridden = overrides[ObjectIdentifier(key)] as? Key.Value {
                return overridden
            }
            return Key.value(for: context)
        }
        set {
            overrides[ObjectIdentifier(key)] = newValue
        }
    }

    /// Drop the override for `key`, so it resolves through the key again.
    public mutating func reset<Key: KVDependencyKey>(_ key: Key.Type) {
        overrides.removeValue(forKey: ObjectIdentifier(key))
    }

    /// Number of explicitly overridden dependencies. Diagnostics only.
    public var overrideCount: Int { overrides.count }
}
