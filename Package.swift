// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFold",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PDFold",
            path: "PDFold",
            exclude: [
                "Resources/Info.plist",
                "Resources/PDFold.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        )
    ]
)
