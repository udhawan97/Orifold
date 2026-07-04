// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "QPDFBinary",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CQPDF", targets: ["CQPDF"])
    ],
    targets: [
        .binaryTarget(
            name: "CQPDF",
            path: "QPDF.xcframework"
        )
    ]
)
