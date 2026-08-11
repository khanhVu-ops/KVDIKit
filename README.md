# KVDIKit

Dependency injection for SwiftUI apps — iOS 16+, zero dependencies.

- ✅ **No registration step** — a dependency is a key with a value; there is nothing to remember to wire up at launch
- 🛡 **Fails at compile time, not at runtime** — a dependency with no value does not build. There is no "unregistered type" crash to ship
- 🧪 **Test overrides that don't leak** — `withKVDependencies { }` is task-local, so tests override the same dependency in parallel without resetting anything
- 👤 **Session scope** — open a layer at sign-in, drop it at sign-out; the previous user's objects are released, not left behind
- 🎛 **Live / preview / test values** — the context is detected, so previews and tests get the right one without a flag
- 🔒 **Swift 6 ready** — no global mutable state, no actor hops on the read path, compiles clean in Swift 6 language mode
- 🪶 **Small** — SwiftUI and Foundation, nothing else in the dependency graph

## Install

```swift
dependencies: [
    .package(url: "https://github.com/khanhVu-ops/KVDIKit.git", from: "1.0.0")
]
```

## Quick start

Declare the dependency as a key, then expose it on `KVDependencyValues`:

```swift
import KVDIKit

struct AuthClient: Sendable {
    var signIn: @Sendable (String, String) async throws -> User

    static let live = AuthClient { email, password in … }
    static let mock = AuthClient { _, _ in .preview }
}

enum AuthClientKey: KVDependencyKey {
    static let liveValue = AuthClient.live
    static let testValue = AuthClient.mock
}

extension KVDependencyValues {
    var authClient: AuthClient {
        get { self[AuthClientKey.self] }
        set { self[AuthClientKey.self] = newValue }
    }
}
```

Read it with `@KVDependency`:

```swift
@MainActor
final class LoginViewModel: ObservableObject {
    @KVDependency(\.authClient) private var auth

    func signIn(email: String, password: String) async {
        user = try? await auth.signIn(email, password)
    }
}
```

That is the whole loop. No container, no `register`, no composition root to keep in sync.

## Layers

Four of them, innermost first. The first one that has a value for a key wins.

| Layer | Set with | Lives for |
|---|---|---|
| Scope | `withKVDependencies { } operation: { }` | one call (and its child tasks) |
| Session | `KVDependencies.startSession { }` | one signed-in user |
| App | `KVDependencies.prepare { }` | the process |
| Key | `liveValue` / `previewValue` / `testValue` | always — the fallback |

### App layer

For values only known at launch:

```swift
@main
struct MyApp: App {
    init() {
        KVDependencies.prepare {
            $0.apiClient = .live(baseURL: AppConfig.current.baseURL)
        }
    }
}
```

Most dependencies need nothing here — `liveValue` already *is* the app layer.

### Session layer

Dependencies that belong to one signed-in user — a token-carrying client, a per-user
store, a per-user cache — go in the session layer, so signing out releases them:

```swift
func didSignIn(_ user: User, token: Token) {
    KVDependencies.startSession { values in
        values.apiClient = .authenticated(wrapping: values.apiClient, token: token)
        values.userStore = UserStore(userID: user.id)
    }
}

func didSignOut() {
    KVDependencies.endSession()      // the objects above are dropped here
}
```

The closure starts from the app layer, so a session dependency can wrap the one it
replaces (`wrapping: values.apiClient` above). Calling `startSession` while a session
is open replaces it — that's the account-switch path.

Objects that already exist pick the change up, because `@KVDependency` resolves on
read rather than at `init`. To react to the boundary itself:

```swift
for await session in KVDependencies.sessionChanges {
    if session == nil { router.popToRoot() }
}
```

### Scope

Used by tests, and by anything that needs a dependency swapped for one call:

```swift
func testSignInFailure() {
    withKVDependencies {
        $0.authClient = .alwaysFailing
    } operation: {
        let model = LoginViewModel()
        model.signIn()
        XCTAssertEqual(model.error, .invalidCredentials)
    }
}
```

Nothing global is mutated, so there is no teardown to forget and no ordering
dependency between tests. Overrides nest, and reach child tasks of the calling task
(but not a `Task.detached`).

A model built inside the scope keeps it after `operation` returns, so the assertion
above still holds if the model is used later.

## Live, preview and test values

A key can provide up to three values. `previewValue` defaults to `liveValue`, and
`testValue` defaults to `previewValue`:

```swift
enum AnalyticsKey: KVDependencyKey {
    static let liveValue = Analytics.firebase
    static let previewValue = Analytics.noop
    static let testValue = Analytics.recording
}
```

The context is detected from the process — XCTest gives `.test`, an Xcode preview
gives `.preview`. A key with **no** `testValue` still resolves in tests, but logs a
runtime issue the first time, so an unstubbed dependency shows up as a purple
warning in Xcode instead of quietly hitting the network. Route those elsewhere with
`KVIssueReporter.handler`.

## SwiftUI

`@KVDependency` works in a view body, but a task-local override cannot reach one —
SwiftUI evaluates bodies outside the task that built them. For previews, use the
environment-based pair:

```swift
struct FeatureFlagBadge: View {
    @KVViewDependency(\.featureFlags) private var flags

    var body: some View { … }
}

#Preview {
    FeatureFlagBadge()
        .kvDependencies { $0.featureFlags = .allEnabled }
}
```

Elsewhere, prefer keeping dependencies in the model and passing the model to the view.

## Example app

`KVDIKitExample/` is a small feed app that prints, on screen, which implementation each
key resolved to. Sign in and watch the API client become
`authenticated(alice) → anonymous` — wrapped, not replaced — and the per-user store
counter go to 1; sign out and watch it go back to zero, which is the session layer
releasing what it built.

The project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
cd KVDIKitExample && xcodegen generate && open KVDIKitExample.xcodeproj
```

## Notes

- **`Value` must be `Sendable`.** A struct of closures, an `actor`, or a `@MainActor`
  class all qualify. Under Swift 6 this is what makes resolving from any isolation
  domain safe without an `await`.
- **Libraries should not depend on this.** `KVToastKit`, `KVNetworkit`, `KVRouterKit`
  and friends expose their own seams (an `init` parameter, a SwiftUI environment
  value). KVDIKit is the app-side glue that wires them together — keeping it out of
  the libraries is what lets them stay usable on their own.
- **`prepare(_:)` is a launch-time call.** Changing the app layer while a session is
  open does not reach the session layer, and says so.

## License

MIT
