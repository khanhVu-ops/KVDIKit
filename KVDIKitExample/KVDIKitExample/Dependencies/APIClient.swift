//
//  APIClient.swift
//  KVDIKitExample
//

import Foundation
import KVDIKit

struct Post: Identifiable, Sendable {
    let id = UUID()
    let author: String
    let body: String
}

/// The usual shape for a dependency: a struct of closures, so a test or a preview can
/// replace one call without implementing a whole protocol.
///
/// `label` is example-only — the screen prints it to show which implementation the
/// layers resolved to.
struct APIClient: Sendable {

    var label: String
    var fetchFeed: @Sendable () async throws -> [Post]

    /// The app layer: what a signed-out visitor sees.
    static let anonymous = APIClient(label: "anonymous") {
        try await Task.sleep(nanoseconds: 400_000_000)
        return [
            Post(author: "KVToastKit", body: "Toasts that survive a sheet."),
            Post(author: "KVRouterKit", body: "Interactive pop, done properly.")
        ]
    }

    /// The session layer, built by wrapping whatever the app layer provided — the same
    /// composition you would do with a real token-signing client.
    static func authenticated(wrapping base: APIClient, as user: String) -> APIClient {
        APIClient(label: "authenticated(\(user)) → \(base.label)") {
            let publicPosts = try await base.fetchFeed()
            return [Post(author: user, body: "Your private draft, only visible to you.")] + publicPosts
        }
    }

    /// A scope-layer stub: instant, deterministic, no network.
    static let stubbed = APIClient(label: "stubbed") {
        [Post(author: "stub", body: "Served from withKVDependencies, no waiting.")]
    }
}

enum APIClientKey: KVDependencyKey {
    static let liveValue = APIClient.anonymous
    static let testValue = APIClient.stubbed
}

extension KVDependencyValues {
    var apiClient: APIClient {
        get { self[APIClientKey.self] }
        set { self[APIClientKey.self] = newValue }
    }
}
