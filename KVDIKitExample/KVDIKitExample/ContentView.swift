//
//  ContentView.swift
//  KVDIKitExample
//

import SwiftUI
import KVDIKit

struct ContentView: View {

    @StateObject private var session = SessionController()
    @StateObject private var feed = FeedViewModel()
    @StateObject private var telemetry = ExampleTelemetry.shared

    var body: some View {
        NavigationStack {
            List {
                resolvedSection
                sessionSection
                feedSection
                flagsSection
                eventsSection
            }
            .navigationTitle("KVDIKit")
            .task { await feed.load() }
        }
    }

    // MARK: - What the layers resolved to

    /// Read fresh on every render, so the labels track sign-in and sign-out.
    private var current: KVDependencyValues { KVDependencies.current }

    private var resolvedSection: some View {
        Section {
            row("context", KVDependencyContext.detected.rawValue)
            row("session", session.signedInAs ?? "signed out")
            row("apiClient", current.apiClient.label)
            row("analytics", current.analytics.label)
            row("userStore", current.userStore.userID)
            row("per-user stores alive", "\(telemetry.liveUserStores)")
        } header: {
            Text("Resolved right now")
        } footer: {
            Text("Nothing was registered anywhere. Each row is a key resolving through the scope, session and app layers in turn.")
        }
    }

    // MARK: - Session layer

    private var sessionSection: some View {
        Section {
            if session.signedInAs == nil {
                Button("Sign in as Alice") { session.signIn(as: "alice") }
                Button("Sign in as Bob") { session.signIn(as: "bob") }
            } else {
                Button("Switch account") {
                    session.signIn(as: session.signedInAs == "alice" ? "bob" : "alice")
                }
                Button("Sign out", role: .destructive) { session.signOut() }
            }
        } header: {
            Text("Session layer")
        } footer: {
            Text("Signing in wraps the anonymous client instead of replacing it. Signing out releases the session's objects — watch the store counter drop to zero.")
        }
    }

    // MARK: - Feed

    private var feedSection: some View {
        Section {
            HStack {
                Text("served by")
                Spacer()
                Text(feed.servedBy)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            if feed.isLoading {
                HStack { ProgressView(); Text("Loading…").foregroundStyle(.secondary) }
            }

            ForEach(feed.posts) { post in
                VStack(alignment: .leading, spacing: 2) {
                    Text(post.author).font(.subheadline.weight(.semibold))
                    Text(post.body).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Button("Reload") {
                Task { await feed.load() }
            }
            Button("Reload with a scoped stub") {
                Task { await feed.loadWithStub() }
            }
        } header: {
            Text("Feed")
        } footer: {
            Text("The same FeedViewModel instance serves all of these. It is never rebuilt — @KVDependency resolves on read, not at init.")
        }
    }

    // MARK: - Reading in a view body

    private var flagsSection: some View {
        Section {
            ExperimentalBanner()
        } header: {
            Text("Feature flags")
        } footer: {
            Text("Read with @KVViewDependency, so the previews at the bottom of this file can override it with .kvDependencies { }.")
        }
    }

    // MARK: - Analytics

    private var eventsSection: some View {
        Section {
            if telemetry.events.isEmpty {
                Text("No events yet").foregroundStyle(.secondary)
            }
            ForEach(telemetry.events, id: \.self) { event in
                Text(event).font(.footnote.monospaced())
            }
        } header: {
            Text("Analytics events")
        } footer: {
            Text("Tagged with the signed-in user once a session is open — the session analytics wraps the app one.")
        }
    }

    private func row(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(name)
            Spacer(minLength: 12)
            Text(value)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - A view that reads a dependency itself

/// SwiftUI evaluates a body outside the task that built it, so a task-local override
/// cannot reach here. ``KVViewDependency`` reads through the environment instead, which
/// is what makes the second preview below work.
struct ExperimentalBanner: View {

    @KVViewDependency(\.featureFlags) private var flags

    var body: some View {
        if flags.showsExperimentalBanner {
            Label("Experimental features are on", systemImage: "flask")
                .foregroundStyle(.orange)
        } else {
            Text("Hidden — flags: \(flags.label)")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Live values") {
    ContentView()
}

// Only `ExperimentalBanner` changes here: `.kvDependencies { }` reaches views, not the
// models they build. To stub the feed for a preview, give `APIClientKey` a
// `previewValue` — or call `KVDependencies.prepare { }` from the preview body.
#Preview("Flags on") {
    ContentView()
        .kvDependencies {
            $0.featureFlags = .allEnabled
        }
}
