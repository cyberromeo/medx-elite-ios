// swift-tools-version: 5.9

// WARNING:
// This file is configured for Swift Playgrounds on iPadOS / iOS and Xcode.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "MedxElite",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "MedxElite",
            targets: ["MedxElite"],
            bundleIdentifier: "quest.srihari.medxelite",
            displayVersion: "1.0.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .book),
            accentColor: .presetColor(.blue),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceBasedOn: .pad))
            ],
            capabilities: [
                .outgoingNetworkConnections()
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "MedxElite",
            path: "MedxElite",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
