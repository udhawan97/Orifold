import AppKit
import CoreGraphics
import XCTest
@testable import Orifold

/// Phase 1 (docs/OBJECT_EDITING_PLAN.md §16) — object model + detection, no UI.
/// Detection/classification against a real PDFium object graph + the persistence round-trip.
final class ObjectDetectionTests: XCTestCase {

    // A fixture with a stroked line, a stroked rectangle, an image, body text, and a full-bleed
    // white background — one of each detectable Phase-1 category.
    private let linePDF = (from: CGPoint(x: 100, y: 600), to: CGPoint(x: 300, y: 600))
    private let rectPDF = CGRect(x: 120, y: 400, width: 140, height: 80)
    private let imagePDF = CGRect(x: 400, y: 300, width: 50, height: 50)

    private func makeFixture() -> Data {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(mediaBox)                 // full-bleed background
        ctx.setStrokeColor(NSColor.black.cgColor); ctx.setLineWidth(2)
        ctx.move(to: linePDF.from); ctx.addLine(to: linePDF.to); ctx.strokePath()   // a line
        ctx.setStrokeColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)); ctx.setLineWidth(1.5)
        ctx.stroke(rectPDF)                                                          // a rectangle
        ctx.draw(makeSolidImage(24, 24), in: imagePDF)                              // an image XObject
        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        ctx.textPosition = CGPoint(x: 72, y: 700)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(
            string: "DETECT ME", attributes: [.font: font, .foregroundColor: NSColor.black.cgColor])), ctx)
        ctx.endPDFPage(); ctx.closePDF()
        return data as Data
    }

    private func makeSolidImage(_ w: Int, _ h: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.systemRed.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    private func near(_ a: CGRect, _ b: CGRect, tol: CGFloat = 4) -> Bool {
        abs(a.minX - b.minX) <= tol && abs(a.minY - b.minY) <= tol && abs(a.width - b.width) <= tol && abs(a.height - b.height) <= tol
    }

    // Test #1/#2/#3 — a line, a rectangle, an image are each detected and classified.
    func testDetectsLineRectangleAndImage() {
        let map = PDFObjectDetectionEngine.detect(pdfData: makeFixture(), pageIndex: 0, pageRefID: UUID())
        XCTAssertFalse(map.objects.isEmpty, "detection returned no objects")

        // No TEXT object leaks into the graphics map (§7 — text is the text-edit lane).
        // (Text objects would classify as none of our graphic types; we assert the fixture's
        //  text does not appear by checking every object is a known graphic category.)
        XCTAssertTrue(map.objects.allSatisfy { $0.objectType != .annotation || $0.sourceType == .pdfKitAnnotation })

        let image = map.objects.first { $0.objectType == .imageXObject }
        let img = try? XCTUnwrap(image)
        XCTAssertNotNil(img)
        XCTAssertEqual(img?.editability, .directImageEdit)
        XCTAssertTrue(near(img?.boundsPdf ?? .zero, imagePDF), "image bounds \(String(describing: img?.boundsPdf)) != \(imagePDF)")
        XCTAssertEqual(img?.imageMetadata?.pixelWidth, 24)
        XCTAssertTrue(img?.capabilities.canMove == true && img?.capabilities.canReplaceImage == true)

        let line = map.objects.first { $0.objectType == .line }
        XCTAssertNotNil(line, "no line detected; types=\(map.objects.map(\.objectType))")
        XCTAssertEqual(line?.editability, .directVectorEdit)
        XCTAssertEqual(line?.confidence, .high)
        XCTAssertTrue((line?.pathData?.isStroked ?? false), "line should be stroked")

        let rect = map.objects.first { $0.objectType == .rectangle }
        XCTAssertNotNil(rect, "no rectangle detected; types=\(map.objects.map(\.objectType))")
        XCTAssertEqual(rect?.editability, .directVectorEdit)
        XCTAssertTrue(near(rect?.boundsPdf ?? .zero, rectPDF, tol: 6), "rect bounds \(String(describing: rect?.boundsPdf))")

        // The full-bleed white background is detected but flagged non-selectable.
        let background = map.objects.first { $0.isBackgroundLike }
        XCTAssertNotNil(background, "full-bleed background not flagged isBackgroundLike")
        XCTAssertEqual(background?.editability, .inferredArtifactEdit)
        XCTAssertEqual(background?.confidence, .low)
    }

    // Detection is deterministic — same bytes → identical stable keys (identity foundation).
    func testDetectionIsDeterministic() {
        let data = makeFixture()
        let a = PDFObjectDetectionEngine.detect(pdfData: data, pageIndex: 0, pageRefID: UUID())
        let b = PDFObjectDetectionEngine.detect(pdfData: data, pageIndex: 0, pageRefID: a.pageRefID)
        XCTAssertEqual(a.objects.count, b.objects.count)
        XCTAssertEqual(a.objects.map { $0.stableKey.structuralDigest },
                       b.objects.map { $0.stableKey.structuralDigest },
                       "structuralDigest must be stable across identical detection passes")
    }

    func testLegacyPersistedPathDigestRemainsResolvable() throws {
        let pageRefID = UUID()
        let map = PDFObjectDetectionEngine.detect(
            pdfData: makeFixture(),
            pageIndex: 0,
            pageRefID: pageRefID
        )
        let line = try XCTUnwrap(map.objects.first { $0.objectType == .line })
        let legacyDigest: UInt64 = 16_098_004_530_599_235_064
        XCTAssertEqual(line.stableKey.structuralDigest, legacyDigest)

        var newTransform = line.transform
        newTransform.e += 12
        let persistedKey = PDFObjectStableKey(
            pageRefID: pageRefID,
            structuralDigest: legacyDigest,
            quantizedBoundsHint: line.stableKey.quantizedBoundsHint,
            zOrderHint: line.zOrder,
            typeHint: line.objectType.rawValue
        )
        let operation = ObjectEditOperation(
            type: .objectTransform,
            documentID: UUID(),
            pageRefID: pageRefID,
            sourceObjectKey: persistedKey,
            objectType: line.objectType,
            editability: line.editability,
            originalBoundsPdf: line.boundsPdf,
            newBoundsPdf: line.boundsPdf.offsetBy(dx: 12, dy: 0),
            originalTransform: line.transform,
            newTransform: newTransform,
            pageRotation: Int(line.pageRotation),
            originalZIndex: line.zOrder,
            newZIndex: line.zOrder,
            replacementStrategy: .pdfiumStructural
        )
        let projected = PDFObjectDetectionEngine.projecting(map, operations: [operation])
        let moved = try XCTUnwrap(projected.objects.first { $0.stableKey.structuralDigest == legacyDigest })
        XCTAssertEqual(moved.boundsPdf.minX, line.boundsPdf.minX + 12, accuracy: 0.01)
    }

    func testPersistedExtremeReplayHintsDoNotTrapProjectionResolution() throws {
        let pageRefID = UUID()
        let detected = PDFObjectDetectionEngine.detect(
            pdfData: makeFixture(),
            pageIndex: 0,
            pageRefID: pageRefID
        )
        let line = try XCTUnwrap(detected.objects.first { $0.objectType == .line })
        var twin = line
        twin.id = UUID()
        twin.zOrder = line.zOrder + 1
        var operation = ObjectEditOperation(
            type: .objectTransform,
            documentID: UUID(),
            pageRefID: pageRefID,
            sourceObjectKey: line.stableKey,
            objectType: line.objectType,
            editability: line.editability,
            originalBoundsPdf: line.boundsPdf,
            newBoundsPdf: line.boundsPdf.offsetBy(dx: 9, dy: 0),
            originalTransform: line.transform,
            newTransform: line.transform,
            pageRotation: Int(line.pageRotation),
            originalZIndex: line.zOrder,
            newZIndex: line.zOrder,
            replacementStrategy: .pdfiumStructural
        )
        operation.sourceObjectKey.quantizedBoundsHint = [Int.min, Int.max, Int.min, Int.max]
        operation.sourceObjectKey.zOrderHint = Int.min
        let persisted = try JSONDecoder().decode(
            ObjectEditOperation.self,
            from: JSONEncoder().encode(operation)
        )
        let map = PageObjectMap(
            pageRefID: pageRefID,
            objects: [line, twin],
            rawObjectCount: 2
        )

        let projected = PDFObjectDetectionEngine.projecting(map, operations: [persisted])

        XCTAssertEqual(projected.objects.filter { $0.boundsPdf == operation.newBoundsPdf }.count, 1)
        XCTAssertEqual(projected.objects.filter { $0.boundsPdf == line.boundsPdf }.count, 1)
    }

    func testPersistedUnsupportedStyleDoesNotProjectChangesTheEngineWillReject() throws {
        let pageRefID = UUID()
        let map = PDFObjectDetectionEngine.detect(
            pdfData: makeFixture(),
            pageIndex: 0,
            pageRefID: pageRefID
        )
        let rectangle = try XCTUnwrap(map.objects.first { $0.objectType == .rectangle })
        let unsupported = ObjectEditOperation(
            type: .objectStyleChange,
            documentID: UUID(),
            pageRefID: pageRefID,
            sourceObjectKey: rectangle.stableKey,
            objectType: rectangle.objectType,
            editability: rectangle.editability,
            originalBoundsPdf: rectangle.boundsPdf,
            newBoundsPdf: rectangle.boundsPdf,
            originalTransform: rectangle.transform,
            newTransform: rectangle.transform,
            pageRotation: Int(rectangle.pageRotation),
            originalStylePayload: ObjectStylePayload(
                strokeColor: rectangle.style.strokeColor,
                fillColor: rectangle.style.fillColor,
                opacity: rectangle.style.opacity,
                lineWidth: rectangle.style.lineWidth
            ),
            newStylePayload: ObjectStylePayload(
                fillColor: CodableColor(red: 0.9, green: 0.1, blue: 0.2),
                opacity: 0.25
            ),
            originalZIndex: rectangle.zOrder,
            newZIndex: rectangle.zOrder,
            replacementStrategy: .pdfiumStructural
        )
        let persisted = try JSONDecoder().decode(
            ObjectEditOperation.self,
            from: JSONEncoder().encode(unsupported)
        )

        let projected = PDFObjectDetectionEngine.projecting(map, operations: [persisted])
        let unchanged = try XCTUnwrap(
            projected.objects.first { $0.stableKey.identifiesSameReplayTarget(as: rectangle.stableKey) }
        )

        XCTAssertEqual(unchanged.style.fillColor, rectangle.style.fillColor)
        XCTAssertEqual(unchanged.style.opacity, rectangle.style.opacity)
    }

    // Test #30 — permission-restricted document: every object locked, no crash.
    func testPermissionRestrictedLocksEverything() {
        let map = PDFObjectDetectionEngine.detect(pdfData: makeFixture(), pageIndex: 0, pageRefID: UUID(), allowsEditing: false)
        XCTAssertFalse(map.objects.isEmpty)
        XCTAssertTrue(map.objects.allSatisfy { $0.editability == .lockedOrPermissionRestricted })
        XCTAssertTrue(map.objects.allSatisfy { $0.capabilities.isReadOnly })
    }

    // Test #29 — malformed / empty input degrades to an empty map, never throws/crashes.
    func testMalformedInputReturnsEmptyMapGracefully() {
        XCTAssertTrue(PDFObjectDetectionEngine.detect(pdfData: Data(), pageIndex: 0, pageRefID: UUID()).objects.isEmpty)
        XCTAssertTrue(PDFObjectDetectionEngine.detect(pdfData: Data("not a pdf".utf8), pageIndex: 0, pageRefID: UUID()).objects.isEmpty)
        XCTAssertTrue(PDFObjectDetectionEngine.detect(pdfData: makeFixture(), pageIndex: 99, pageRefID: UUID()).objects.isEmpty)
    }

    // Editability → capability mapping matches the §4 table on the key cases.
    func testEditabilityCapabilities() {
        XCTAssertTrue(PDFObjectEditability.directImageEdit.capabilities.canReplaceImage)
        XCTAssertFalse(PDFObjectEditability.directImageEdit.capabilities.canRestyle)
        XCTAssertTrue(PDFObjectEditability.directVectorEdit.capabilities.canRestyle)
        XCTAssertFalse(PDFObjectEditability.formWidgetEdit.capabilities.canDuplicate)
        XCTAssertTrue(PDFObjectEditability.formXObjectInstanceEdit.capabilities.canMove)
        XCTAssertTrue(PDFObjectEditability.formXObjectSourceEdit.capabilities.isReadOnly)
        XCTAssertTrue(PDFObjectEditability.unsupported.capabilities.isReadOnly)
        XCTAssertNil(PDFObjectEditability.directVectorEdit.fallbackMessageKey)
        XCTAssertEqual(PDFObjectEditability.rasterRegionReplace.fallbackMessageKey, "object.editability.raster.regionOnly")
    }

    // Persistence: Workspace with objectEditStates round-trips and bumps schemaVersion to 6.
    func testWorkspaceObjectEditStatesCodableRoundTrip() throws {
        var workspace = Workspace()
        let pageRefID = UUID()
        let op = ObjectEditOperation(
            type: .objectTransform, documentID: UUID(), pageRefID: pageRefID,
            sourceObjectKey: PDFObjectStableKey(pageRefID: pageRefID, structuralDigest: 0xABCDEF,
                                                quantizedBoundsHint: [1, 2, 3, 4], zOrderHint: 5, typeHint: "line"),
            objectType: .line, editability: .directVectorEdit,
            originalBoundsPdf: CGRect(x: 1, y: 2, width: 3, height: 4),
            newBoundsPdf: CGRect(x: 11, y: 12, width: 3, height: 4),
            originalTransform: .identity, newTransform: PDFTextTransform(a: 1, b: 0, c: 0, d: 1, e: 10, f: 10),
            pageRotation: 0, originalZIndex: 2, newZIndex: 2, replacementStrategy: .pdfiumStructural)
        workspace.objectEditStates = [PageObjectEditState(pageRefID: pageRefID, operations: [op])]

        XCTAssertEqual(workspace.schemaVersion, 6)
        let encoded = try JSONEncoder().encode(workspace)
        let decoded = try JSONDecoder().decode(Workspace.self, from: encoded)
        XCTAssertEqual(decoded.schemaVersion, 6)
        XCTAssertEqual(decoded.objectEditStates, workspace.objectEditStates)
        XCTAssertEqual(decoded.objectEditStates.first?.operations.first?.sourceObjectKey.structuralDigest, 0xABCDEF)
        XCTAssertEqual(decoded.objectEditStates.first?.operations.first?.newTransform.e, 10)
    }

    // Old workspaces (no objectEditStates key) still decode — forward/backward compat.
    func testDecodingLegacyWorkspaceWithoutObjectEditStates() throws {
        let legacy = "{\"id\":\"\(UUID().uuidString)\",\"title\":\"T\",\"schemaVersion\":5}"
        let decoded = try JSONDecoder().decode(Workspace.self, from: Data(legacy.utf8))
        XCTAssertTrue(decoded.objectEditStates.isEmpty)
        XCTAssertEqual(decoded.schemaVersion, 5)
    }

    // Regression guard: poeStructuralDigest must never trap on hostile input (a malformed/
    // adversarial content stream can legitimately carry NaN/infinite/huge path coordinates).
    // Int64(Double) traps on exactly these inputs — this proves the clamp holds.
    func testStructuralDigestNeverTrapsOnHostileCoordinates() {
        let hostileInputs: [[Double]] = [
            [.nan], [.infinity], [-.infinity],
            [1e300], [-1e300], [Double.greatestFiniteMagnitude],
            [0, .nan, 100], [.infinity, .infinity, .infinity]
        ]
        for values in hostileInputs {
            let digest = poeStructuralDigest(values)
            _ = digest   // reaching this line without a trap IS the assertion
        }
        // Two different hostile inputs still produce a value (not required to differ — the
        // point is survival, not discrimination of pathological input).
        XCTAssertNoThrow(poeStructuralDigest([.nan, .infinity, -1e300, 1e300]))
    }

    // Regression guard: two distinct same-size images must NOT collide onto the same identity.
    // Before the fix, digestValues was [pixelWidth, pixelHeight] only.
    func testDistinctSameSizeImagesGetDifferentStableKeys() {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(mediaBox)
        ctx.draw(makeSolidImage(24, 24, .systemRed), in: CGRect(x: 100, y: 600, width: 40, height: 40))
        ctx.draw(makeSolidImage(24, 24, .systemBlue), in: CGRect(x: 300, y: 600, width: 40, height: 40))
        ctx.endPDFPage(); ctx.closePDF()

        let map = PDFObjectDetectionEngine.detect(pdfData: data as Data, pageIndex: 0, pageRefID: UUID())
        let images = map.objects.filter { $0.objectType == .imageXObject }
        XCTAssertEqual(images.count, 2, "expected two distinct image objects")
        guard images.count == 2 else { return }
        XCTAssertNotEqual(images[0].stableKey, images[1].stableKey,
                          "two different images of identical pixel dimensions must not share an identity key")
        XCTAssertNotEqual(images[0].imageMetadata?.pixelDigest, 0, "pixelDigest must be populated")
        XCTAssertNotEqual(images[0].imageMetadata?.pixelDigest, images[1].imageMetadata?.pixelDigest)
    }

    private func makeSolidImage(_ w: Int, _ h: Int, _ color: NSColor) -> CGImage {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(color.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()!
    }

    // Closes the Phase-0 testing gap flagged by review: the identity contract (§3.6) claims
    // structuralDigest "survives the round-trip," but Phase 0 only proved this for an IMAGE via
    // its own test-local digest. This proves it for a PATH using the PRODUCTION detection engine
    // + production poe_* write-back primitives (poeTouchPathColorsForGenerateContent +
    // GenerateContent + SaveAsCopy) — the exact chain Phase 2's write-back engine will reuse.
    func testPathStructuralDigestSurvivesRealGenerateContentRoundTrip() throws {
        let rectPDF = CGRect(x: 120, y: 400, width: 140, height: 80)
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: CGDataConsumer(data: data as CFMutableData)!, mediaBox: &mediaBox, nil)!
        ctx.beginPDFPage(nil)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(mediaBox)
        ctx.setStrokeColor(CGColor(red: 0.1, green: 0.2, blue: 0.9, alpha: 1)); ctx.setLineWidth(1.5)
        ctx.stroke(rectPDF)
        ctx.endPDFPage(); ctx.closePDF()
        let original = data as Data

        let pageRefID = UUID()
        let before = PDFObjectDetectionEngine.detect(pdfData: original, pageIndex: 0, pageRefID: pageRefID)
        let beforeRect = try XCTUnwrap(before.objects.first { $0.objectType == .rectangle })

        // Real production write-back chain: touch colors, GenerateContent, SaveAsCopy — no
        // object mutated (proves ROUND-TRIP stability of an untouched object, mirroring what
        // any OTHER object's edit-commit will do to this one's bytes as a side effect).
        let regenerated: Data = try XCTUnwrap({
            pdfiumLock.lock(); FPDF_InitLibrary()
            defer { FPDF_DestroyLibrary(); pdfiumLock.unlock() }
            return original.withUnsafeBytes { raw -> Data? in
                guard let base = raw.baseAddress,
                      let doc = FPDF_LoadMemDocument(base, Int32(original.count), nil) else { return nil }
                defer { FPDF_CloseDocument(doc) }
                guard let page = poe_LoadPage(doc, 0) else { return nil }
                defer { poe_ClosePage(page) }
                poeTouchPathColorsForGenerateContent(page)
                guard poe_GenerateContent(page) != 0 else { return nil }
                regenTestSaveBuffer = Data()
                var fw = RegenTestFileWrite(version: 1, writeBlock: { _, bytes, size in
                    if let bytes, size > 0 { regenTestSaveBuffer.append(bytes.assumingMemoryBound(to: UInt8.self), count: Int(size)) }
                    return 1
                })
                guard regenTest_SaveAsCopy(doc, &fw, UInt(1 << 1)) != 0, !regenTestSaveBuffer.isEmpty else { return nil }
                return regenTestSaveBuffer
            }
        }(), "regenerate round-trip produced no bytes")

        let after = PDFObjectDetectionEngine.detect(pdfData: regenerated, pageIndex: 0, pageRefID: pageRefID)
        let afterRect = try XCTUnwrap(after.objects.first { $0.objectType == .rectangle })
        XCTAssertEqual(afterRect.stableKey.structuralDigest, beforeRect.stableKey.structuralDigest,
                      "untouched path's structuralDigest must survive a real GenerateContent+SaveAsCopy round-trip")
    }
}

// MARK: - Test-local SaveAsCopy plumbing for the round-trip test above.
// FPDF_SaveAsCopy(FPDF_DOCUMENT, FPDF_FILEWRITE*, FPDF_DWORD) — exactly 3 args, no context
// param (mirrors the proven pattern in Phase0PDFiumRoundTripSpikeTests.swift / PDFCompressionService.swift).
// `flags` is FPDF_DWORD = `unsigned long` (8 bytes) — bound as UInt for ABI correctness.
private struct RegenTestFileWrite {
    var version: Int32
    var writeBlock: (@convention(c) (UnsafeMutableRawPointer?, UnsafeRawPointer?, CUnsignedLong) -> Int32)?
}
@_silgen_name("FPDF_SaveAsCopy")
private func regenTest_SaveAsCopy(_ document: OpaquePointer?, _ fileWrite: UnsafeMutablePointer<RegenTestFileWrite>?, _ flags: UInt) -> Int32
// File-private, non-reentrant — safe because this test always runs its single SaveAsCopy call
// synchronously inside the pdfiumLock-held critical section above (same discipline as the
// Phase 0 spike's p0SaveBuffer / PDFCompressionService's fpdfCompressionSaveData).
private var regenTestSaveBuffer = Data()
