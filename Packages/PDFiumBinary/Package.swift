// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PDFiumBinary",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PDFium", targets: ["PDFium"])
    ],
    targets: [
        .binaryTarget(
            name: "PDFium",
            url: "https://github.com/espresso3389/pdfium-xcframework/releases/download/v144.0.7811.0-20260502-190206/PDFium-chromium-7811-20260502-190206.xcframework.zip",
            checksum: "948d9257f53f01cbed74b81bb8adc8758e52ac9390751772de7889026d32d5a1"
        )
    ]
)
