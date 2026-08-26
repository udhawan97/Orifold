import Foundation
import CoreGraphics

// =============================================================================
// PDFObjectDetectionEngine — the per-page PDFium page-object enumeration + classification pass
// (docs/OBJECT_EDITING_PLAN.md §2). Produces a read-only PageObjectMap for hit-testing/selection;
// it never mutates bytes. Runs under `pdfiumLock` against PRISTINE member bytes and never throws
// (returns an empty map on any failure — Test #29 malformed/graceful-degradation).
//
// Phase-1 scope: PDFium content-stream objects (image / vector path→line/rect/ellipse/shape /
// Form XObject instance / shading). TEXT objects are intentionally skipped — they belong to the
// inline text-edit lane (§7). PDFKit annotations/widgets and Tier-B table clustering (§2.2) layer
// on later; the model already carries the fields for them.
// =============================================================================

struct PDFObjectDetectionEngine {

    /// Safety cap mirroring PageGraphicsIndex — beyond it the map is marked `didTruncateScan`.
    static let maxObjectsScan = 4000

    /// An object whose AABB covers at least this fraction of the page area is treated as a
    /// full-bleed background/artifact (not default-selectable) rather than real content.
    static let backgroundAreaFractionThreshold = 0.92

    /// Detect page objects on `pageIndex` of pristine member `pdfData`. `allowsEditing == false`
    /// (permission-restricted / signed) forces every object to `lockedOrPermissionRestricted`.
    static func detect(pdfData: Data, pageIndex: Int, pageRefID: UUID,
                       allowsEditing: Bool = true) -> PageObjectMap {
        PDFPageObjectInspection.inspect(
            pdfData: pdfData,
            pageIndex: pageIndex,
            pageRefID: pageRefID,
            allowsEditing: allowsEditing
        ).objectMap
    }

    /// Projects committed absolute operations over a canonical inspection snapshot. Selection
    /// therefore sees live bounds/style/order without rescanning replayed bytes (whose text
    /// overlay Form XObjects are implementation details, not user-editable source objects).
    static func projecting(_ map: PageObjectMap, operations: [ObjectEditOperation]) -> PageObjectMap {
        guard !operations.isEmpty else { return map }
        var objects = map.objects
        var deletedIndexes = Set<Int>()
        var projectedRawObjectCount = map.rawObjectCount
        var resolvedIndexByTarget: [PDFObjectReplayIdentity: Int] = [:]

        for operation in operations.sorted(by: { projectionRank($0.type) < projectionRank($1.type) }) {
            let identity = operation.sourceObjectKey.replayIdentity
            let target = resolvedIndexByTarget[identity] ?? objects.indices
                .filter { index in
                    !deletedIndexes.contains(index)
                        && objects[index].stableKey.structuralDigest == identity.structuralDigest
                        && objects[index].objectType == operation.objectType
                        && (identity.typeHint.isEmpty || objects[index].objectType.rawValue == identity.typeHint)
                        && (identity.sourceXObjectName == nil
                            || objects[index].stableKey.sourceXObjectName == identity.sourceXObjectName)
                }
                .min { lhs, rhs in
                    // Resolve against the immutable canonical snapshot, not already-projected
                    // geometry. The persisted identity hints rank exactly as they do in byte
                    // replay; z-order breaks equal bounds distances.
                    let lhsDistance = PDFObjectReplayHintDistance.bounds(
                        map.objects[lhs].stableKey.quantizedBoundsHint,
                        identity.quantizedBoundsHint
                    )
                    let rhsDistance = PDFObjectReplayHintDistance.bounds(
                        map.objects[rhs].stableKey.quantizedBoundsHint,
                        identity.quantizedBoundsHint
                    )
                    if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
                    return PDFObjectReplayHintDistance.scalar(
                        map.objects[lhs].zOrder,
                        identity.zOrderHint
                    ) < PDFObjectReplayHintDistance.scalar(
                        map.objects[rhs].zOrder,
                        identity.zOrderHint
                    )
                }
            guard let target else { continue }
            resolvedIndexByTarget[identity] = target

            switch operation.type {
            case .objectTransform:
                objects[target].boundsPdf = operation.newBoundsPdf
                objects[target].transform = operation.newTransform
            case .objectStyleChange:
                if let payload = operation.newStylePayload,
                   payload.isSupportedForStructuralReplay {
                    if let fill = payload.fillColor { objects[target].style.fillColor = fill }
                    if let stroke = payload.strokeColor { objects[target].style.strokeColor = stroke }
                    if let width = payload.lineWidth { objects[target].style.lineWidth = max(0, width) }
                }
            case .objectReorder:
                let oldIndex = objects[target].zOrder
                let newIndex = min(
                    max(0, operation.newZIndex),
                    max(0, projectedRawObjectCount - 1)
                )
                if newIndex > oldIndex {
                    for peer in objects.indices where peer != target && !deletedIndexes.contains(peer) &&
                        objects[peer].zOrder > oldIndex && objects[peer].zOrder <= newIndex {
                        objects[peer].zOrder -= 1
                    }
                } else if newIndex < oldIndex {
                    for peer in objects.indices where peer != target && !deletedIndexes.contains(peer) &&
                        objects[peer].zOrder >= newIndex && objects[peer].zOrder < oldIndex {
                        objects[peer].zOrder += 1
                    }
                }
                objects[target].zOrder = newIndex
            case .objectDelete:
                deletedIndexes.insert(target)
                let deletedZOrder = objects[target].zOrder
                for peer in objects.indices where !deletedIndexes.contains(peer) &&
                    objects[peer].zOrder > deletedZOrder {
                    objects[peer].zOrder -= 1
                }
                projectedRawObjectCount = max(0, projectedRawObjectCount - 1)
            case .objectReplace:
                // Replacement is not part of the current structural implementation; keep the
                // canonical detected object until that operation gains a typed projection.
                break
            }
        }

        let projected = objects.enumerated().compactMap { index, object in
            deletedIndexes.contains(index) ? nil : object
        }.sorted { $0.zOrder < $1.zOrder }
        return PageObjectMap(
            pageRefID: map.pageRefID,
            objects: projected,
            analysisRevision: map.analysisRevision,
            didTruncateScan: map.didTruncateScan,
            rawObjectCount: projectedRawObjectCount
        )
    }

    static func applyingEditingPermission(_ allowsEditing: Bool, to map: PageObjectMap) -> PageObjectMap {
        guard !allowsEditing else { return map }
        var locked = map
        for index in locked.objects.indices {
            locked.objects[index].editability = .lockedOrPermissionRestricted
        }
        return locked
    }

    /// Canonical inspection uses canonical bytes, while page rotation remains live PDFKit state.
    /// Project it explicitly so reselecting after a rotation cannot bypass the rotated-page edit
    /// guard merely because the shared inspection snapshot predates that rotation.
    static func applyingPageRotation(_ rotation: CGFloat, to map: PageObjectMap) -> PageObjectMap {
        var rotated = map
        for index in rotated.objects.indices {
            rotated.objects[index].pageRotation = rotation
        }
        return rotated
    }

    private static func projectionRank(_ type: ObjectEditType) -> Int {
        switch type {
        case .objectStyleChange: return 0
        case .objectTransform: return 1
        case .objectReorder: return 2
        case .objectReplace: return 3
        case .objectDelete: return 4
        }
    }

    // MARK: - Per-object inspection (shared with PDFObjectEditEngine's resolver)

    /// Everything read from a single live PDFium page object EXCEPT the per-detection-pass
    /// wrapping (pageRefID / zOrder / editability / stableKey). Shared so the write-back engine
    /// resolves an op's target by computing the IDENTICAL `structuralDigest` this produces.
    struct InspectedObject {
        var type: Int32
        var objectType: PDFObjectType
        var confidence: PDFTextEditConfidence
        var bounds: CGRect
        var transform: PDFTextTransform
        var clip: PDFObjectClipInfo
        var style: PDFObjectStyle
        var pathData: PDFPathData?
        var imageMeta: PDFObjectImageMetadata?
        var formName: String?
        var childCount: Int
        var isBackgroundLike: Bool
        var structuralDigest: UInt64
        var boundsHint: [Int]
    }

    /// Read + classify + digest a single live object handle. Returns nil for a degenerate object
    /// (non-finite bounds). MUST stay the single source of truth for `structuralDigest`.
    static func inspect(obj: OpaquePointer?, pageArea: Double) -> InspectedObject? {
        let type = poe_GetType(obj)
        var l: Float = 0, b: Float = 0, r: Float = 0, t: Float = 0
        guard poe_GetBounds(obj, &l, &b, &r, &t) != 0,
              l.isFinite, b.isFinite, r.isFinite, t.isFinite else { return nil }
        let bounds = CGRect(x: CGFloat(min(l, r)), y: CGFloat(min(b, t)),
                            width: CGFloat(abs(r - l)), height: CGFloat(abs(t - b)))
        guard bounds.width.isFinite, bounds.height.isFinite else { return nil }

        var m = POEFSMatrix()
        _ = poe_GetMatrix(obj, &m)
        let transform = m.textTransform

        var clip = PDFObjectClipInfo()
        if poe_GetClipPath(obj) != nil { clip.hasClip = true }

        let areaFraction = Double(bounds.width * bounds.height) / max(pageArea, 1)
        let isBackgroundLike = areaFraction >= backgroundAreaFractionThreshold

        var style = PDFObjectStyle()
        var pathData: PDFPathData?
        var imageMeta: PDFObjectImageMetadata?
        var formName: String?
        var childCount = 0

        var objectType: PDFObjectType
        var confidence: PDFTextEditConfidence
        var digestValues: [Double]
        var digestSalt: UInt64 = 0   // for content hashes too wide-range for the geometry clamp

        switch type {
        case POEObjType.image:
            objectType = .imageXObject
            confidence = .high
            var pw: UInt32 = 0, ph: UInt32 = 0
            _ = poe_ImageGetPixelSize(obj, &pw, &ph)
            // Sampled pixel content, not just dimensions — two different images that happen to
            // share pixel dimensions must NOT collide onto the same PDFObjectStableKey (identity
            // is keyed on structuralDigest alone; dimensions-only would merge distinct images).
            // Fed in as `salt` (unclamped) — folding a full-range hash through the geometry
            // clamp would collapse every image's contribution to the same boundary constant.
            let pixelDigest = poeImagePixelDigest(obj, pixelWidth: Int(pw), pixelHeight: Int(ph))
            imageMeta = PDFObjectImageMetadata(pixelWidth: Int(pw), pixelHeight: Int(ph),
                                               hasSoftMask: clip.hasSoftMask, pixelDigest: pixelDigest)
            style.opacity = 1
            digestValues = [Double(pw), Double(ph)]
            digestSalt = pixelDigest

        case POEObjType.form:
            objectType = .formXObject
            confidence = .high
            childCount = Int(poe_FormCountObjects(obj))
            formName = nil   // source name not exposed via the declared surface in Phase 1
            digestValues = [Double(childCount), Double(round(bounds.width)), Double(round(bounds.height))]

        case POEObjType.shading:
            objectType = .shading
            confidence = .medium
            digestValues = [Double(round(bounds.width)), Double(round(bounds.height))]

        case POEObjType.path:
            let extracted = extractPath(obj)
            pathData = extracted.data
            style = extracted.style
            (objectType, confidence) = classifyPath(extracted, isBackgroundLike: isBackgroundLike)
            // Intrinsic = segment topology in the path's own (matrix-independent) space.
            digestValues = extracted.data.segments.flatMap { [Double($0.kind.ordinal), Double($0.point.x), Double($0.point.y)] }
            if digestValues.isEmpty {
                digestValues = [Double(round(bounds.width)), Double(round(bounds.height))]
            }

        default:
            objectType = .vectorPath
            confidence = .low
            digestValues = [Double(round(bounds.width)), Double(round(bounds.height))]
        }

        let digest = poeStructuralDigest(digestValues + [Double(objectType.hashDiscriminator)], salt: digestSalt)
        let boundsHint = [Int(round(bounds.minX)), Int(round(bounds.minY)),
                          Int(round(bounds.width)), Int(round(bounds.height))]

        return InspectedObject(
            type: type, objectType: objectType, confidence: confidence, bounds: bounds,
            transform: transform, clip: clip, style: style, pathData: pathData, imageMeta: imageMeta,
            formName: formName, childCount: childCount, isBackgroundLike: isBackgroundLike,
            structuralDigest: digest, boundsHint: boundsHint)
    }

    // MARK: - Per-object build (detection-pass wrapping over `inspect`)

    static func build(obj: OpaquePointer?, zOrder: Int, type: Int32, pageRefID: UUID,
                      pageRotation: CGFloat, pageArea: Double, allowsEditing: Bool) -> DetectedObject? {
        guard let o = inspect(obj: obj, pageArea: pageArea) else { return nil }

        let stableKey = PDFObjectStableKey(
            pageRefID: pageRefID,
            structuralDigest: o.structuralDigest,
            quantizedBoundsHint: o.boundsHint,
            zOrderHint: zOrder,
            typeHint: o.objectType.rawValue,
            sourceXObjectName: o.formName)

        let editability = classifyEditability(objectType: o.objectType, confidence: o.confidence,
                                              clip: o.clip, isBackgroundLike: o.isBackgroundLike,
                                              allowsEditing: allowsEditing)

        // Path points are needed transiently for classification/digesting but no current object
        // editing consumer reads them after detection. Retain only the draw-mode summary so the
        // revision cache cannot multiply thousands of path points across hundreds of pages.
        let retainedPathData = o.pathData.map {
            PDFPathData(
                segments: [],
                fillRule: $0.fillRule,
                isStroked: $0.isStroked,
                isFilled: $0.isFilled,
                flattenedStroke: []
            )
        }
        return DetectedObject(
            stableKey: stableKey, pageRefID: pageRefID, objectType: o.objectType,
            sourceType: .pdfiumPageObject, confidence: o.confidence, editability: editability,
            boundsPdf: o.bounds, transform: o.transform, pageRotation: pageRotation, zOrder: zOrder,
            style: o.style, pathData: retainedPathData, imageMetadata: o.imageMeta, clipInfo: o.clip,
            groupSource: o.objectType == .formXObject && o.childCount > 0 ? .formXObject(name: o.formName ?? "") : .none,
            formXObjectName: o.formName, isBackgroundLike: o.isBackgroundLike)
    }

    // MARK: - Path extraction & classification

    private struct ExtractedPath {
        var data: PDFPathData
        var style: PDFObjectStyle
        var moveCount = 0
        var lineCount = 0
        var bezierCount = 0
        var isClosed = false
    }

    private static func extractPath(_ obj: OpaquePointer?) -> ExtractedPath {
        var fillMode: Int32 = 0, stroke: Int32 = 0
        _ = poe_PathGetDrawMode(obj, &fillMode, &stroke)
        let isFilled = fillMode != POEFillMode.none
        let isStroked = stroke != 0

        var style = PDFObjectStyle()
        style.fillColor = readColor { poe_GetFillColor(obj, $0, $1, $2, $3) }
        style.strokeColor = readColor { poe_GetStrokeColor(obj, $0, $1, $2, $3) }
        var width: Float = 0
        if poe_GetStrokeWidth(obj, &width) != 0 { style.lineWidth = CGFloat(width) }
        style.opacity = style.fillColor?.alpha ?? style.strokeColor?.alpha ?? 1

        var segments: [PDFPathSegment] = []
        var flattened: [CGPoint] = []
        var moveCount = 0, lineCount = 0, bezierCount = 0, closed = false
        let segmentCount = poe_PathCountSegments(obj)
        if segmentCount > 0 {
            for index in 0..<segmentCount {
                guard let seg = poe_PathGetSegment(obj, index) else { continue }
                var x: Float = 0, y: Float = 0
                _ = poe_SegGetPoint(seg, &x, &y)
                let point = CGPoint(x: CGFloat(x), y: CGFloat(y))
                let segClosed = poe_SegGetClose(seg) != 0
                if segClosed { closed = true }
                let kind: PDFPathSegmentKind
                switch poe_SegGetType(seg) {
                case POESeg.moveTo: kind = .moveTo; moveCount += 1
                case POESeg.lineTo: kind = .lineTo; lineCount += 1
                case POESeg.bezierTo: kind = .bezierTo; bezierCount += 1
                default: kind = .lineTo; lineCount += 1
                }
                segments.append(PDFPathSegment(kind: kind, point: point, isClosed: segClosed))
                flattened.append(point)   // Phase-1 flatten: on-/control-point polyline (conservative)
            }
        }
        let data = PDFPathData(segments: segments, fillRule: Int(fillMode),
                               isStroked: isStroked, isFilled: isFilled, flattenedStroke: flattened)
        return ExtractedPath(data: data, style: style, moveCount: moveCount,
                             lineCount: lineCount, bezierCount: bezierCount, isClosed: closed)
    }

    private static func classifyPath(_ p: ExtractedPath, isBackgroundLike: Bool)
        -> (PDFObjectType, PDFTextEditConfidence) {
        if isBackgroundLike { return (.filledShape, .low) }   // full-bleed → not default-selectable
        // Line: one move + one line, open, stroked.
        if p.moveCount == 1, p.lineCount == 1, p.bezierCount == 0, !p.isClosed {
            return (.line, .high)
        }
        // Rectangle: closed, no beziers, 3–4 line segments (Quartz emits rect as move+3 line+close).
        if p.isClosed, p.bezierCount == 0, (3...5).contains(p.lineCount) {
            return (.rectangle, .high)
        }
        // Ellipse: closed, ≥4 beziers, few/no straight edges.
        if p.isClosed, p.bezierCount >= 4, p.lineCount <= 1 {
            return (.ellipse, .medium)
        }
        if p.data.isFilled { return (.filledShape, .medium) }
        if p.data.isStroked { return (.strokedShape, .medium) }
        return (.vectorPath, .medium)
    }

    // MARK: - Editability

    private static func classifyEditability(objectType: PDFObjectType, confidence: PDFTextEditConfidence,
                                            clip: PDFObjectClipInfo, isBackgroundLike: Bool,
                                            allowsEditing: Bool) -> PDFObjectEditability {
        guard allowsEditing else { return .lockedOrPermissionRestricted }
        switch objectType {
        case .imageXObject, .flattenedRaster:
            // A soft-masked image can't be structurally replaced cleanly → raster fallback (§10).
            return clip.hasSoftMask ? .rasterRegionReplace : .directImageEdit
        case .line, .rectangle, .ellipse, .filledShape, .strokedShape, .vectorPath:
            // Clipped vectors stay movable (§10 "move preserves the clip") but low-confidence
            // full-bleed artifacts are surfaced as inferred artifacts (not default-selectable).
            if isBackgroundLike || confidence == .low { return .inferredArtifactEdit }
            return .directVectorEdit
        case .decorativeArtifact:
            return .inferredArtifactEdit
        case .tableGrid:
            return .groupedObjectEdit
        case .formXObject:
            return .formXObjectInstanceEdit
        case .formWidget:
            return .formWidgetEdit
        case .annotation:
            return .directAnnotationEdit
        case .shading:
            return .unsupported
        }
    }

    // MARK: - Small helpers

    private static func readColor(_ get: (UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32) -> CodableColor? {
        var r: UInt32 = 0, g: UInt32 = 0, b: UInt32 = 0, a: UInt32 = 0
        guard get(&r, &g, &b, &a) != 0 else { return nil }
        return CodableColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: CGFloat(a) / 255)
    }
}

private extension PDFPathSegmentKind {
    var ordinal: Int { switch self { case .moveTo: return 0; case .lineTo: return 1; case .bezierTo: return 2; case .close: return 3 } }
}

private extension PDFObjectType {
    /// Small stable per-type discriminator folded into the structural digest so a line and an
    /// image that happen to share a numeric footprint never collide.
    var hashDiscriminator: Int {
        switch self {
        case .annotation: return 1
        case .imageXObject: return 2
        case .vectorPath: return 3
        case .line: return 4
        case .rectangle: return 5
        case .ellipse: return 6
        case .filledShape: return 7
        case .strokedShape: return 8
        case .tableGrid: return 9
        case .formWidget: return 10
        case .formXObject: return 11
        case .shading: return 12
        case .decorativeArtifact: return 13
        case .flattenedRaster: return 14
        }
    }
}
