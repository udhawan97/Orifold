import AppKit
import Darwin
import Foundation
import Network
import PDFKit
import UniformTypeIdentifiers
import XCTest
@testable import Orifold

final class HTMLImportSecurityTests: XCTestCase {
    func testResourcePolicyConfinesRelativeAssetsToCanonicalSourceRoot() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-policy-\(UUID().uuidString)", isDirectory: true)
        let root = scratch.appendingPathComponent("source", isDirectory: true)
        let outside = scratch.appendingPathComponent("outside.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let asset = root.appendingPathComponent("asset.txt")
        try Data("root asset".utf8).write(to: asset)
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("escape.txt"),
            withDestinationURL: outside
        )

        let policy = HTMLImportResourcePolicy(sourceRoot: root)
        let baseURL = policy.rendererDocumentURL
        let relativeAsset = try XCTUnwrap(URL(string: "asset.txt", relativeTo: baseURL)?.absoluteURL)
        let traversal = try XCTUnwrap(URL(string: "../outside.txt", relativeTo: baseURL)?.absoluteURL)
        let encodedTraversal = try XCTUnwrap(URL(string: "\(HTMLImportResourcePolicy.localScheme)://source/root/%2e%2e/outside.txt"))
        let symlinkEscape = try XCTUnwrap(URL(string: "escape.txt", relativeTo: baseURL)?.absoluteURL)

        XCTAssertEqual(policy.localAsset(for: relativeAsset)?.data, Data("root asset".utf8))
        XCTAssertNil(policy.localAsset(for: traversal))
        XCTAssertNil(policy.localAsset(for: encodedTraversal))
        XCTAssertNil(policy.localAsset(for: symlinkEscape))
        XCTAssertFalse(HTMLImportResourcePolicy.allowsNavigation(to: nil))
        XCTAssertFalse(HTMLImportResourcePolicy.allowsNavigation(to: URL(string: "https://example.invalid/probe")))
        XCTAssertFalse(HTMLImportResourcePolicy.allowsNavigation(to: URL(string: "http://localhost/probe")))
        XCTAssertFalse(HTMLImportResourcePolicy.allowsNavigation(to: outside))
        XCTAssertTrue(HTMLImportResourcePolicy.allowsNavigation(to: URL(string: "data:text/plain,local")))
    }

    func testDescriptorRelativeReadsNeverFollowAFileSwappedToOutsideSymlink() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-swap-\(UUID().uuidString)", isDirectory: true)
        let root = scratch.appendingPathComponent("source", isDirectory: true)
        let target = root.appendingPathComponent("asset.txt")
        let outside = scratch.appendingPathComponent("outside.txt")
        let insideData = Data("inside bytes".utf8)
        let outsideData = Data("OUTSIDE SECRET".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try insideData.write(to: target)
        try outsideData.write(to: outside)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let policy = HTMLImportResourcePolicy(sourceRoot: root)
        let request = try XCTUnwrap(URL(string: "asset.txt", relativeTo: policy.rendererDocumentURL)?.absoluteURL)
        XCTAssertEqual(policy.localAsset(for: request)?.data, insideData)

        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        XCTAssertNil(policy.localAsset(for: request), "a final symlink must be rejected deterministically")

        let swapProbe = AssetSwapProbe()
        let swapGroup = DispatchGroup()
        swapGroup.enter()
        DispatchQueue(label: "OrifoldTests.HTMLAssetSwap").async {
            defer { swapGroup.leave() }
            for iteration in 0..<2_000 {
                try? FileManager.default.removeItem(at: target)
                if iteration.isMultiple(of: 2) {
                    try? insideData.write(to: target, options: .atomic)
                } else {
                    try? FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
                }
            }
        }
        for _ in 0..<2_000 {
            if let data = policy.localAsset(for: request)?.data {
                swapProbe.record(data: data, expected: insideData)
            }
        }
        swapGroup.wait()
        XCTAssertFalse(swapProbe.sawUnexpectedBytes, "descriptor-relative no-follow reads must never return outside bytes")
    }

    func testRetainedRootAndIntermediateDescriptorsSurvivePathSwapsWithoutEscape() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-root-swap-\(UUID().uuidString)", isDirectory: true)
        let source = scratch.appendingPathComponent("source", isDirectory: true)
        let heldSource = scratch.appendingPathComponent("source-held", isDirectory: true)
        let nested = source.appendingPathComponent("assets", isDirectory: true)
        let outside = scratch.appendingPathComponent("outside", isDirectory: true)
        let insideData = Data("retained root bytes".utf8)
        let outsideData = Data("OUTSIDE ROOT SECRET".utf8)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try insideData.write(to: nested.appendingPathComponent("asset.txt"))
        try outsideData.write(to: outside.appendingPathComponent("assets/asset.txt"))
        defer { try? FileManager.default.removeItem(at: scratch) }

        let retainedRootPolicy = HTMLImportResourcePolicy(sourceRoot: source)
        let request = try XCTUnwrap(
            URL(string: "assets/asset.txt", relativeTo: retainedRootPolicy.rendererDocumentURL)?.absoluteURL
        )
        try FileManager.default.moveItem(at: source, to: heldSource)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)

        XCTAssertEqual(
            retainedRootPolicy.localAsset(for: request)?.data,
            insideData,
            "a root-path replacement must not retarget the retained descriptor"
        )

        try FileManager.default.removeItem(at: source)
        try FileManager.default.moveItem(at: heldSource, to: source)
        let intermediatePolicy = HTMLImportResourcePolicy(sourceRoot: source)
        let heldNested = source.appendingPathComponent("assets-held", isDirectory: true)
        try FileManager.default.moveItem(at: nested, to: heldNested)
        try FileManager.default.createSymbolicLink(
            at: nested,
            withDestinationURL: outside.appendingPathComponent("assets")
        )

        XCTAssertNil(
            intermediatePolicy.localAsset(for: request),
            "an intermediate directory replaced by a symlink must fail closed"
        )
    }

    func testMainDocumentAndAssetsRemainBoundToOneRetainedSourceRoot() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-bound-source-\(UUID().uuidString)", isDirectory: true)
        let source = scratch.appendingPathComponent("source", isDirectory: true)
        let heldSource = scratch.appendingPathComponent("source-held", isDirectory: true)
        let outside = scratch.appendingPathComponent("outside", isDirectory: true)
        let insideHTML = Data("<p>INSIDE DOCUMENT</p>".utf8)
        let insideAsset = Data("inside asset".utf8)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try insideHTML.write(to: source.appendingPathComponent("document.html"))
        try insideAsset.write(to: source.appendingPathComponent("asset.txt"))
        try Data("OUTSIDE DOCUMENT".utf8).write(to: outside.appendingPathComponent("document.html"))
        try Data("OUTSIDE ASSET".utf8).write(to: outside.appendingPathComponent("asset.txt"))
        defer { try? FileManager.default.removeItem(at: scratch) }

        let bound = try XCTUnwrap(HTMLImportResourcePolicy.boundSourceFile(
            at: source.appendingPathComponent("document.html"),
            maxBytes: 1_024
        ))
        try FileManager.default.moveItem(at: source, to: heldSource)
        try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
        let assetRequest = try XCTUnwrap(
            URL(string: "asset.txt", relativeTo: bound.resourcePolicy.rendererDocumentURL)?.absoluteURL
        )

        XCTAssertEqual(bound.data, insideHTML)
        XCTAssertEqual(bound.resourcePolicy.localAsset(for: assetRequest)?.data, insideAsset)
    }

    func testDescriptorRelativeReadsRejectFIFOsWithoutBlocking() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-fifo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let fifo = scratch.appendingPathComponent("asset.png")
        XCTAssertEqual(Darwin.mkfifo(fifo.path, mode_t(S_IRUSR | S_IWUSR)), 0)
        let policy = HTMLImportResourcePolicy(sourceRoot: scratch)
        let request = try XCTUnwrap(URL(string: "asset.png", relativeTo: policy.rendererDocumentURL)?.absoluteURL)
        let finished = expectation(description: "special-file read returns")
        let probe = SpecialAssetReadProbe()

        DispatchQueue(label: "OrifoldTests.HTMLFIFOSpecialFile").async {
            probe.record(assetWasReturned: policy.localAsset(for: request) != nil)
            finished.fulfill()
        }

        let waitResult = XCTWaiter.wait(for: [finished], timeout: 1)
        if waitResult != .completed {
            // Unblock an older blocking implementation so a failing regression does not
            // strand the test process after the timeout assertion.
            let writer = Darwin.open(fifo.path, O_WRONLY | O_NONBLOCK)
            if writer >= 0 { Darwin.close(writer) }
        }
        XCTAssertEqual(waitResult, .completed, "special-file references must fail closed promptly")
        XCTAssertFalse(probe.assetWasReturned)
    }

    func testBlockAllRulePrecedesOnlyExplicitNonNetworkAllowances() throws {
        let data = Data(HTMLImportResourcePolicy.blockedSchemeRuleList.utf8)
        let rules = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [[String: [String: String]]]
        )
        XCTAssertEqual(rules.first?["trigger"]?["url-filter"], ".*")
        XCTAssertEqual(rules.first?["action"]?["type"], "block")

        let allowedFilters = Set(rules.dropFirst().compactMap { rule -> String? in
            guard rule["action"]?["type"] == "ignore-previous-rules" else { return nil }
            return rule["trigger"]?["url-filter"]
        })
        XCTAssertEqual(allowedFilters, ["^about:", "^data:", "^orifold-html-resource:"])
        XCTAssertFalse(allowedFilters.contains(where: { $0.contains("http") }))
        XCTAssertFalse(HTMLImportResourcePolicy.allowsNavigation(to: URL(string: "https://dns-prefetch.invalid")))
        XCTAssertFalse(HTMLImportResourcePolicy.allowsNavigation(to: URL(string: "https://preconnect.invalid")))
    }

    @MainActor
    func testHTMLImportMakesNoHTTPRequestsForRemoteSubresources() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        let ready = expectation(description: "loopback listener ready")
        let probe = ConnectionProbe()
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.fulfill()
            case .failed(let error):
                probe.recordFailure(error)
                ready.fulfill()
            default:
                break
            }
        }
        listener.newConnectionHandler = { connection in
            probe.recordConnection()
            connection.cancel()
        }
        listener.start(queue: DispatchQueue(label: "OrifoldTests.HTMLImportLoopback"))
        defer { listener.cancel() }

        await fulfillment(of: [ready], timeout: 3)
        if let failure = probe.failure {
            throw failure
        }
        let port = try XCTUnwrap(listener.port)
        let origin = "http://127.0.0.1:\(port.rawValue)"
        let localhostOrigin = "http://localhost:\(port.rawValue)"
        let dnsOrigin = "https://orifold-html-import.invalid"
        let html = """
        <!doctype html>
        <html>
          <head>
            <meta http-equiv="refresh" content="0;url=\(origin)/meta-refresh">
            <link rel="dns-prefetch" href="//orifold-dns-prefetch.invalid">
            <link rel="preconnect" href="\(dnsOrigin)" crossorigin>
            <link rel="stylesheet" href="\(origin)/redirect?to=style">
            <style>
              @import url('\(localhostOrigin)/review-import.css');
              @font-face { font-family: Probe; src: url('\(origin)/review-font.woff2'); }
              body { background-image: url('\(origin)/review-css-image.png'); }
            </style>
          </head>
          <body>
            <p>Secure HTML import</p>
            <img src="\(origin)/review-image.png"
                 srcset="\(origin)/review-1x.png 1x, \(localhostOrigin)/review-2x.png 2x" alt="probe">
            <picture><source srcset="\(origin)/review-picture.webp"><img src="\(dnsOrigin)/picture.png"></picture>
            <svg><image href="\(origin)/review-svg-image.png" /></svg>
            <iframe src="\(origin)/review-frame.html"></iframe>
            <audio src="\(origin)/review-audio.mp3"><source src="\(origin)/review-audio.ogg"></audio>
            <video src="\(origin)/review-video.mp4" poster="\(origin)/review-poster.png"><source src="\(origin)/review-video.webm"></video>
            <object data="\(origin)/review-object"></object>
            <embed src="\(origin)/review-embed">
          </body>
        </html>
        """

        // The synchronous compatibility route must also stay inert rather than invoking
        // NSAttributedString's network-capable HTML importer.
        let synchronous = try DocumentImportConverter.importedDocument(
            from: Data(html.utf8),
            contentType: .html,
            filename: "network-probe.html",
            baseURL: nil
        )
        XCTAssertTrue(extractedText(from: synchronous.pdfDocument).contains("Secure HTML import"))

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: Data(html.utf8),
            contentType: .html,
            filename: "network-probe.html",
            baseURL: nil
        )
        XCTAssertTrue(extractedText(from: imported.pdfDocument).contains("Secure HTML import"))

        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(probe.connectionCount, 0, "HTML import must block requests before they reach URL loading")
    }

    @MainActor
    func testReferenceDocumentDirectOpenPreservesInlineFormattingWithoutAnHTMLEngine() throws {
        let html = """
        <!doctype html><html><body>
          <h1>Direct Open</h1>
          <p>Plain <strong>Bold</strong> <em>Italic</em> <u>Underline</u> <code>Code</code></p>
          <ul><li>First item</li><li>Second item</li></ul>
          <img src="https://example.invalid/must-not-load.png">
        </body></html>
        """
        let document = try WorkspaceDocument(
            testingFile: FileWrapper(regularFileWithContents: Data(html.utf8)),
            contentType: .html,
            filename: "direct-open.html"
        )
        let payload = try XCTUnwrap(document.sourcePayloads.values.first)
        let attributed = try XCTUnwrap(payload.attributedString())

        XCTAssertTrue(attributed.string.contains("Direct Open"))
        XCTAssertTrue(attributed.string.contains("• First item"))
        XCTAssertTrue(fontTraits(in: attributed, substring: "Bold").contains(.boldFontMask))
        XCTAssertTrue(fontTraits(in: attributed, substring: "Italic").contains(.italicFontMask))
        XCTAssertEqual(attribute(.underlineStyle, in: attributed, substring: "Underline") as? Int, NSUnderlineStyle.single.rawValue)
        let codeFont = try XCTUnwrap(attribute(.font, in: attributed, substring: "Code") as? NSFont)
        XCTAssertTrue(codeFont.isFixedPitch)
    }

    @MainActor
    func testReferenceDocumentDirectOpenUsesFixedInkAndReopenableFontsInDarkAppearance() throws {
        let appearance = try XCTUnwrap(NSAppearance(named: .darkAqua))
        var parseResult: Result<NSAttributedString, Error>?

        appearance.performAsCurrentDrawingAppearance {
            parseResult = Result {
                let html = "<p>Dark appearance body</p><code>Stable mono</code>"
                let document = try WorkspaceDocument(
                    testingFile: FileWrapper(regularFileWithContents: Data(html.utf8)),
                    contentType: .html,
                    filename: "dark-appearance.html"
                )
                let payload = try XCTUnwrap(document.sourcePayloads.values.first)
                return try XCTUnwrap(payload.attributedString())
            }
        }

        let attributed = try XCTUnwrap(parseResult).get()
        let bodyColor = try XCTUnwrap(
            attribute(.foregroundColor, in: attributed, substring: "Dark appearance body") as? NSColor
        )
        let bodyRGB = try XCTUnwrap(bodyColor.usingColorSpace(.deviceRGB))
        XCTAssertEqual(bodyRGB.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(bodyRGB.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(bodyRGB.blueComponent, 0, accuracy: 0.001)

        let bodyFont = try XCTUnwrap(attribute(.font, in: attributed, substring: "Dark appearance body") as? NSFont)
        let codeFont = try XCTUnwrap(attribute(.font, in: attributed, substring: "Stable mono") as? NSFont)
        XCTAssertEqual(bodyFont.fontName, "Georgia")
        XCTAssertEqual(codeFont.fontName, "Menlo-Regular")
        XCTAssertFalse(bodyFont.fontName.hasPrefix("."))
        XCTAssertFalse(codeFont.fontName.hasPrefix("."))
    }

    @MainActor
    func testReferenceDocumentDirectOpenPreservesInlineRootAndDataCSS() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-direct-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try Data(".from-local { color: #1256a0; font-weight: bold; }".utf8)
            .write(to: scratch.appendingPathComponent("local.css"))

        let html = """
        <!doctype html><html><head>
          <style>.inline-css { text-decoration: underline; }</style>
          <link rel="stylesheet" href="local.css">
          <link rel="stylesheet" href="data:text/css,.from-data%20%7B%20font-style%3A%20italic%3B%20%7D">
          <link rel="stylesheet" href="https://example.invalid/must-not-load.css">
        </head><body>
          <p class="inline-css">INLINE CSS</p>
          <p class="from-local">ROOT CSS</p>
          <p class="from-data">DATA CSS</p>
        </body></html>
        """
        let htmlURL = scratch.appendingPathComponent("direct-assets.html")
        try Data(html.utf8).write(to: htmlURL)
        let imported = try DocumentImportConverter.importedDocument(from: htmlURL)
        let attributed = try XCTUnwrap(imported.sourcePayload?.attributedString())

        XCTAssertEqual(
            attribute(.underlineStyle, in: attributed, substring: "INLINE CSS") as? Int,
            NSUnderlineStyle.single.rawValue
        )
        XCTAssertTrue(fontTraits(in: attributed, substring: "ROOT CSS").contains(.boldFontMask))
        let rootColor = try XCTUnwrap(attribute(.foregroundColor, in: attributed, substring: "ROOT CSS") as? NSColor)
        let rootRGB = try XCTUnwrap(rootColor.usingColorSpace(.deviceRGB))
        XCTAssertGreaterThan(rootRGB.blueComponent, rootRGB.redComponent)
        XCTAssertTrue(fontTraits(in: attributed, substring: "DATA CSS").contains(.italicFontMask))
    }

    func testPreCancelledHTMLImportThrowsInsteadOfReturningFallbackSuccess() async {
        let result = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                let imported = try await DocumentImportConverter.importedDocumentAsync(
                    from: Data("<p>must not succeed</p>".utf8),
                    contentType: .html,
                    filename: "cancelled.html",
                    baseURL: nil
                )
                return Result<DocumentImportConverter.ImportedDocument, Error>.success(imported)
            } catch {
                return Result<DocumentImportConverter.ImportedDocument, Error>.failure(error)
            }
        }.value

        switch result {
        case .success:
            XCTFail("a cancelled HTML renderer must not return its inert fallback as success")
        case .failure(let error):
            XCTAssertTrue(error is CancellationError, "unexpected cancellation error: \(error)")
        }
    }

    @MainActor
    func testHTMLImportRendersAuthorizedRootScopedAndDataStylesheets() async throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("orifold-html-assets-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        try Data(".from-local { display: block !important; }".utf8)
            .write(to: scratch.appendingPathComponent("local.css"))

        let html = """
        <!doctype html>
        <html>
          <head>
            <link rel="stylesheet" href="local.css">
            <link rel="stylesheet" href="data:text/css,.from-data%20%7B%20display%3A%20block%20!important%3B%20%7D">
          </head>
          <body>
            <p class="from-local" style="display: none">LOCAL CSS</p>
            <p class="from-data" style="display: none">DATA CSS</p>
          </body>
        </html>
        """

        let imported = try await DocumentImportConverter.importedDocumentAsync(
            from: Data(html.utf8),
            contentType: .html,
            filename: "assets.html",
            baseURL: scratch
        )
        let text = extractedText(from: imported.pdfDocument)
        XCTAssertTrue(text.contains("LOCAL CSS"), "root-scoped stylesheet should render through the local scheme handler")
        XCTAssertTrue(text.contains("DATA CSS"), "data stylesheet should remain intentionally supported")
    }

    private func extractedText(from document: PDFDocument) -> String {
        guard let data = document.dataRepresentation() else { return "" }
        return (0..<document.pageCount)
            .map { PDFTextAnalysisEngine.readingOrderText(data: data, pageIndex: $0) }
            .joined(separator: "\n")
    }

    private func attribute(
        _ key: NSAttributedString.Key,
        in attributed: NSAttributedString,
        substring: String
    ) -> Any? {
        let range = (attributed.string as NSString).range(of: substring)
        guard range.location != NSNotFound else { return nil }
        return attributed.attribute(key, at: range.location, effectiveRange: nil)
    }

    private func fontTraits(in attributed: NSAttributedString, substring: String) -> NSFontTraitMask {
        guard let font = attribute(.font, in: attributed, substring: substring) as? NSFont else { return [] }
        return NSFontManager.shared.traits(of: font)
    }
}

private final class ConnectionProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedConnectionCount = 0
    private var storedFailure: NWError?

    var connectionCount: Int {
        lock.withLock { storedConnectionCount }
    }

    var failure: NWError? {
        lock.withLock { storedFailure }
    }

    func recordConnection() {
        lock.withLock { storedConnectionCount += 1 }
    }

    func recordFailure(_ error: NWError) {
        lock.withLock { storedFailure = error }
    }
}

private final class AssetSwapProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedUnexpectedBytes = false

    var sawUnexpectedBytes: Bool {
        lock.withLock { storedUnexpectedBytes }
    }

    func record(data: Data, expected: Data) {
        lock.withLock {
            if data != expected { storedUnexpectedBytes = true }
        }
    }
}

private final class SpecialAssetReadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var storedAssetWasReturned = false

    var assetWasReturned: Bool {
        lock.withLock { storedAssetWasReturned }
    }

    func record(assetWasReturned: Bool) {
        lock.withLock { storedAssetWasReturned = assetWasReturned }
    }
}
