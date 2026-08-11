//
//  FeedViewModel.swift
//  KVDIKitExample
//

import Foundation
import KVDIKit

/// A plain model with two dependencies and no initialiser parameters.
///
/// It is built once, on the first screen, and never rebuilt — yet it serves the
/// anonymous feed before sign-in and the authenticated one after, because
/// `@KVDependency` resolves when the property is read rather than at `init`.
@MainActor
final class FeedViewModel: ObservableObject {

    @KVDependency(\.apiClient) private var api
    @KVDependency(\.analytics) private var analytics

    @Published private(set) var posts: [Post] = []
    @Published private(set) var isLoading = false
    /// Which implementation served the last load — the whole point of the screen.
    @Published private(set) var servedBy = "—"

    func load() async {
        analytics.track("feed.load")
        isLoading = true
        defer { isLoading = false }

        servedBy = api.label
        posts = (try? await api.fetchFeed()) ?? []
    }

    /// Loads through a one-off override instead of the app or session layer.
    ///
    /// The model is not rebuilt and knows nothing about this: the override lives on the
    /// task, and `api` is read inside it.
    func loadWithStub() async {
        await withKVDependencies {
            $0.apiClient = .stubbed
        } operation: {
            await load()
        }
    }
}
