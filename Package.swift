// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "pdFold",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "pdFold", targets: ["PDFold"])
    ],
    dependencies: [
        .package(path: "Packages/PDFiumBinary")
    ],
    targets: [
        .executableTarget(
            name: "PDFold",
            dependencies: [
                .product(name: "PDFium", package: "PDFiumBinary")
            ],
            path: "PDFold",
            exclude: [
                "Resources/Info.plist",
                "Resources/PDFold.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "PDFoldTests",
            dependencies: ["PDFold"],
            path: "Tests/PDFoldTests"
        )
    ]
)
