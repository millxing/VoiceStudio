// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoiceStudio",
    platforms: [.macOS("26.0")],
    targets: [
        // Rules and data logic with no SwiftUI, so tests run without the app.
        .target(name: "VoiceStudioKit"),
        .executableTarget(
            name: "VoiceStudio",
            dependencies: ["VoiceStudioKit"],
            // App code runs on the main thread unless you say otherwise.
            swiftSettings: [.unsafeFlags(["-default-isolation", "MainActor"])]
        ),
        .executableTarget(name: "VoiceStudioChecks", dependencies: ["VoiceStudioKit"], path: "Tests/VoiceStudioKitTests"),
    ]
)
