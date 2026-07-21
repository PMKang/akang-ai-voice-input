// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AkangVoiceInput",
    platforms: [.macOS(.v12)],
    products: [
        .executable(name: "AkangVoiceInput", targets: ["AkangVoiceInput"])
    ],
    targets: [
        .executableTarget(
            name: "AkangVoiceInput",
            path: "Sources/AkangVoiceInput"
        ),
        .testTarget(
            name: "AkangVoiceInputTests",
            dependencies: ["AkangVoiceInput"],
            path: "Tests/AkangVoiceInputTests"
        )
    ]
)
