//
//  KVDIKitExampleApp.swift
//  KVDIKitExample
//

import SwiftUI
import KVDIKit

@main
struct KVDIKitExampleApp: App {

    init() {
        // The app layer. Most dependencies need nothing here — a key's `liveValue` is
        // already the app layer — so this is for what is only known at launch.
        KVDependencies.prepare { values in
            if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
                values.apiClient = .stubbed
                values.analytics = .noop
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
