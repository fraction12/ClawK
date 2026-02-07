// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClawK",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "ClawK",
            targets: ["ClawK"]
        )
    ],
    targets: [
        .executableTarget(
            name: "ClawK",
            path: "ClawK",
            exclude: ["ClawK.entitlements", "Info.plist"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
