# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - Unreleased

Every change below is additive or a bug fix; no public API was removed, and no default
behaviour changed.

### Fixed

- **Deadlock in `prepare(_:)` and `startSession(id:_:)`.** Both ran the caller's closure
  while holding the package's (non-recursive) lock, so a closure that resolved any
  dependency — `KVDependencies.current`, a `@KVDependency` read, an object whose `init`
  reads one, or a key whose lazy `liveValue` resolves another key — hung the app. The
  closure now runs on a copy outside the lock and the result is published in one step
  when it returns, so all values set in one call still become visible together.
  `prepare` / `startSession` calls are serialised by a separate recursive gate; a nested
  call no longer hangs and is reported instead.
- Dependencies released by `startSession(id:_:)`, `endSession()`, `prepare(_:)` and
  `resetForTesting()` are now deallocated after the lock is released, so a `deinit` that
  resolves a dependency cannot deadlock either.
- Session observers are notified under the lock, so concurrent sign-in / sign-out
  deliver boundaries in the order they happened.
- Test-context detection under `swift test` with Swift Testing: the
  `swiftpm-testing-helper` runner passes a path *inside* the `.xctest` bundle, which the
  `hasSuffix(".xctest")` check missed. Detection now also recognises that runner and,
  as a last resort, an XCTest or Swift Testing framework loaded in the process.

### Added

- `KVDependencies.testValuePolicy` (`KVTestValuePolicy.warn` / `.fail`). `.fail` fails the
  running test on every access to a key without a `testValue`, through the new
  `KVIssueReporter.failureHandler` (defaults to `XCTFail`, resolved dynamically so the
  library still does not link XCTest). **The default stays `.warn`**, matching 1.0.0.
- `KVIssueReporter.failureHandler` and `KVIssueReporter.fail(_:)`.
- `KVDependencies.sessionChanges(includingCurrent:)` — a stream that starts with the
  current `sessionID` (atomically with subscribing) before delivering boundaries.
  The existing `sessionChanges` property is unchanged and still delivers changes only.
- `KVDI_CONTEXT` environment variable (`live` / `preview` / `test`) to override context
  detection (`KVDependencyContext.overrideEnvironmentKey`).
- README section on apps built with default `MainActor` isolation (Xcode 26) — the
  exact `nonisolated` placement keys and `KVDependencyValues` extensions need — and a
  `KVDIKitMainActorTests` test target that builds that way, so the pattern stays valid.

## [1.0.0]

- Initial release: key-based dependency injection with an app, session and scope layer.

[1.1.0]: https://github.com/khanhVu-ops/KVDIKit/compare/1.0.0...HEAD
[1.0.0]: https://github.com/khanhVu-ops/KVDIKit/releases/tag/1.0.0
