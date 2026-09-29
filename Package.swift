// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "KVDIKit",
    platforms: [
        .iOS(.v16),
        // Not a shipping target — it lets `swift test` build and run the suite on the
        // command line instead of only through an iOS simulator scheme.
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "KVDIKit",
            targets: ["KVDIKit"]
        )
    ],
    targets: [
        .target(
            name: "KVDIKit",
            path: "Sources/KVDIKit"
        ),
        .testTarget(
            name: "KVDIKitTests",
            dependencies: ["KVDIKit"],
            path: "Tests/KVDIKitTests"
        ),
        // Built the way a new Xcode 26 app target is: default MainActor isolation.
        // Compiling at all is most of what this target tests.
        .testTarget(
            name: "KVDIKitMainActorTests",
            dependencies: ["KVDIKit"],
            path: "Tests/KVDIKitMainActorTests",
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
