// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orifold",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Orifold", targets: ["Orifold"])
    ],
    dependencies: [
        .package(path: "Packages/PDFiumBinary"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-asn1.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Orifold",
            dependencies: [
                .product(name: "PDFium", package: "PDFiumBinary"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates")
            ],
            path: "Orifold",
            exclude: [
                "Resources/Info.plist",
                "Resources/Orifold.entitlements"
            ],
            resources: [
                .process("Resources/Assets.xcassets"),
                .copy("Resources/CERTIFICATE_GUIDE.md"),
                .copy("Resources/THIRD-PARTY-NOTICES.md")
            ]
        ),
        .testTarget(
            name: "OrifoldTests",
            dependencies: ["Orifold"],
            path: "Tests/OrifoldTests"
        )
    ]
)
