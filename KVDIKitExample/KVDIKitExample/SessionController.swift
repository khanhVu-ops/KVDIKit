//
//  SessionController.swift
//  KVDIKitExample
//

import Foundation
import KVDIKit

/// Opens and closes the session layer. In a real app this is the only place that calls
/// `startSession`/`endSession` — everything else just reads its dependencies and gets
/// whichever user is signed in.
@MainActor
final class SessionController: ObservableObject {

    @Published private(set) var signedInAs: String?
    @Published private(set) var sessionID: KVSessionID?

    func signIn(as user: String) {
        // The closure starts from the app layer, so each override can wrap the value it
        // replaces instead of having to rebuild it.
        let id = KVDependencies.startSession { values in
            values.apiClient = .authenticated(wrapping: values.apiClient, as: user)
            values.analytics = .tagged(user, wrapping: values.analytics)
            values.userStore = UserStore(userID: user)
        }

        signedInAs = user
        sessionID = id
    }

    func signOut() {
        // Everything the session built is released here — including the UserStore, which
        // the screen's "per-user stores alive" counter is watching.
        KVDependencies.endSession()
        signedInAs = nil
        sessionID = nil
    }
}
