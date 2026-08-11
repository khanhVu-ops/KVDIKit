//
//  FeatureFlags.swift
//  KVDIKitExample
//

import Foundation
import KVDIKit

/// A dependency a *view* reads directly, which is the one case where `@KVDependency`
/// is not enough — see ``ExperimentalBanner``.
struct FeatureFlags: Sendable {

    var label: String
    var showsExperimentalBanner: Bool

    static let production = FeatureFlags(label: "production", showsExperimentalBanner: false)
    static let allEnabled = FeatureFlags(label: "all enabled", showsExperimentalBanner: true)
}

enum FeatureFlagsKey: KVDependencyKey {
    static let liveValue = FeatureFlags.production
}

extension KVDependencyValues {
    var featureFlags: FeatureFlags {
        get { self[FeatureFlagsKey.self] }
        set { self[FeatureFlagsKey.self] = newValue }
    }
}
