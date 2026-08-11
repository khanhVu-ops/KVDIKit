//
//  Analytics.swift
//  KVDIKitExample
//

import Foundation
import KVDIKit

struct Analytics: Sendable {

    var label: String
    var track: @Sendable (String) -> Void

    /// The app layer. A real one would forward to Firebase or similar.
    static let recording = Analytics(label: "recording") { event in
        Task { @MainActor in ExampleTelemetry.shared.record(event) }
    }

    /// Previews should not send events anywhere.
    static let noop = Analytics(label: "noop") { _ in }

    /// The session layer stamps the signed-in user onto every event, by wrapping
    /// whatever the app layer configured.
    static func tagged(_ user: String, wrapping base: Analytics) -> Analytics {
        Analytics(label: "tagged(\(user)) → \(base.label)") { event in
            base.track("[\(user)] \(event)")
        }
    }
}

enum AnalyticsKey: KVDependencyKey {
    static let liveValue = Analytics.recording
    static let previewValue = Analytics.noop
    static let testValue = Analytics.noop
}

extension KVDependencyValues {
    var analytics: Analytics {
        get { self[AnalyticsKey.self] }
        set { self[AnalyticsKey.self] = newValue }
    }
}
