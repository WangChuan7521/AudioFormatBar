// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AudioFormatBar",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .executable(
            name: "AudioFormatBar",
            targets: ["AudioFormatBar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AudioFormatBar",
            path: "Sources/AudioFormatBar",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("SwiftUI")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
