import Foundation
import AppKit

// =============================================================================
// Object Editing — canonical data model (docs/OBJECT_EDITING_PLAN.md §3, §4, §8).
//
// Reuses PDFTextEditingModels.swift primitives (CodableColor, PDFTextTransform,
// PDFTextEditConfidence) rather than inventing parallels. Bounds/geometry are in RAW,
// UNROTATED content-stream space (the space PDFium's FPDFPageObj_GetBounds/GetMatrix and
// PDFView.convert(_:to:page) both use). The object MAP is a read-only detection index and is
// never the source of truth for bytes — only entries in the operation list mutate the file.
// =============================================================================

// MARK: - §3.1 Classification enums

enum PDFObjectType: String, Codable {
    case annotation, imageXObject, vectorPath, line, rectangle, ellipse,
         filledShape, strokedShape, tableGrid, formWidget, formXObject,
         shading, decorativeArtifact, flattenedRaster
}

enum PDFObjectSource: String, Codable {
    case pdfiumPageObject, pdfKitAnnotation, orifoldDecoration, orifoldPlacement, inferred
}

enum PDFObjectGroupSource: Codable, Equatable {
    case none
    case inferredCluster            // Tier-B spatial cluster (table/grid)
    case formXObject(name: String)  // PDF-declared /Form XObject instance
}

// Ranking helper on the REUSED text-confidence enum (do not invent a parallel enum).
extension PDFTextEditConfidence {
    var rank: Int { self == .high ? 2 : (self == .medium ? 1 : 0) }
}

// MARK: - §3.2 Style + payload value types

struct PDFObjectStyle: Codable, Equatable {
    var strokeColor: CodableColor?         // FPDFPageObj_GetStrokeColor
    var fillColor: CodableColor?           // FPDFPageObj_GetFillColor
    var opacity: CGFloat = 1.0             // color alpha / SMask
    var lineWidth: CGFloat = 0             // FPDFPageObj_GetStrokeWidth
    var dashPattern: [CGFloat] = []        // FPDFPageObj_GetDashArray + GetDashCount
    var dashPhase: CGFloat = 0
    var lineCap: Int = 0
    var lineJoin: Int = 0

    init(strokeColor: CodableColor? = nil, fillColor: CodableColor? = nil, opacity: CGFloat = 1.0,
         lineWidth: CGFloat = 0, dashPattern: [CGFloat] = [], dashPhase: CGFloat = 0,
         lineCap: Int = 0, lineJoin: Int = 0) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.opacity = opacity
        self.lineWidth = lineWidth
        self.dashPattern = dashPattern
        self.dashPhase = dashPhase
        self.lineCap = lineCap
        self.lineJoin = lineJoin
    }
}

enum PDFPathSegmentKind: String, Codable { case moveTo, lineTo, bezierTo, close }

struct PDFPathSegment: Codable, Equatable {
    var kind: PDFPathSegmentKind
    var point: CGPoint
    var control1: CGPoint?
    var control2: CGPoint?
    var isClosed: Bool = false             // FPDFPathSegment_GetClose

    init(kind: PDFPathSegmentKind, point: CGPoint, control1: CGPoint? = nil,
         control2: CGPoint? = nil, isClosed: Bool = false) {
        self.kind = kind
        self.point = point
        self.control1 = control1
        self.control2 = control2
        self.isClosed = isClosed
    }
}

/// Path geometry in the object's OWN pre-matrix space.
struct PDFPathData: Codable, Equatable {
    var segments: [PDFPathSegment]
    var fillRule: Int                      // FPDFPath_GetDrawMode
    var isStroked: Bool
    var isFilled: Bool
    /// Beziers pre-flattened HERE (in detection) so §5's distance-to-segment hit-test stays
    /// allocation-free and O(#segments).
    var flattenedStroke: [CGPoint] = []

    init(segments: [PDFPathSegment], fillRule: Int, isStroked: Bool, isFilled: Bool,
         flattenedStroke: [CGPoint] = []) {
        self.segments = segments
        self.fillRule = fillRule
        self.isStroked = isStroked
        self.isFilled = isFilled
        self.flattenedStroke = flattenedStroke
    }
}

struct PDFObjectImageMetadata: Codable, Equatable {
    var pixelWidth: Int
    var pixelHeight: Int                   // FPDFImageObj_GetImagePixelSize
    var bitsPerPixel: Int?                 // FPDFImageObj_GetImageMetadata
    var colorSpace: Int?
    var filter: String?                    // FPDFImageObj_GetImageFilter
    var hasSoftMask: Bool = false
    var pixelDigest: UInt64 = 0            // FNV-1a of decoded pixels → structuralDigest

    init(pixelWidth: Int, pixelHeight: Int, bitsPerPixel: Int? = nil, colorSpace: Int? = nil,
         filter: String? = nil, hasSoftMask: Bool = false, pixelDigest: UInt64 = 0) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bitsPerPixel = bitsPerPixel
        self.colorSpace = colorSpace
        self.filter = filter
        self.hasSoftMask = hasSoftMask
        self.pixelDigest = pixelDigest
    }
}

struct PDFObjectClipInfo: Codable, Equatable {
    var hasClip: Bool = false              // FPDFPageObj_GetClipPath != nil
    var clipBounds: CGRect?
    var hasSoftMask: Bool = false

    init(hasClip: Bool = false, clipBounds: CGRect? = nil, hasSoftMask: Bool = false) {
        self.hasClip = hasClip
        self.clipBounds = clipBounds
        self.hasSoftMask = hasSoftMask
    }
}

// MARK: - §3.6 Durable identity

/// Durable cross-reopen identity. `FPDFPage_GetObject` is index-based and every commit
/// re-serializes+reloads the document (renumbering objects), so identity hashes ONLY
/// mutation-invariant intrinsic content, recomputed from a fresh detection pass each load —
/// NEVER a persisted cross-serialization byte digest (GenerateContent re-emits the whole
/// stream, so raw byte digests of untouched objects legitimately change). Phase 0 proved this
/// digest is translation-invariant and survives the round-trip.
struct PDFObjectStableKey: Codable, Equatable, Hashable {
    var pageRefID: UUID
    /// Mutation-INVARIANT structural digest — THE ONLY field in == / hashValue.
    var structuralDigest: UInt64

    // Ranked disambiguators — NOT part of == / hashValue:
    var quantizedBoundsHint: [Int] = []    // boundsPdf at detection, rounded to 1pt [x,y,w,h]
    var zOrderHint: Int = 0
    var typeHint: String = ""              // objectType.rawValue at detection
    var sourceXObjectName: String?         // Form XObject placements

    init(pageRefID: UUID, structuralDigest: UInt64, quantizedBoundsHint: [Int] = [],
         zOrderHint: Int = 0, typeHint: String = "", sourceXObjectName: String? = nil) {
        self.pageRefID = pageRefID
        self.structuralDigest = structuralDigest
        self.quantizedBoundsHint = quantizedBoundsHint
        self.zOrderHint = zOrderHint
        self.typeHint = typeHint
        self.sourceXObjectName = sourceXObjectName
    }

    static func == (l: Self, r: Self) -> Bool {
        l.pageRefID == r.pageRefID && l.structuralDigest == r.structuralDigest
    }
    func hash(into h: inout Hasher) {
        h.combine(pageRefID)
        h.combine(structuralDigest)
    }

    /// Full identity used while replaying and coalescing operations. The public stable-key
    /// equality remains mutation-invariant for selection continuity, while this identity keeps
    /// visually identical twins distinct through their original disambiguators.
    var replayIdentity: PDFObjectReplayIdentity {
        PDFObjectReplayIdentity(
            pageRefID: pageRefID,
            structuralDigest: structuralDigest,
            quantizedBoundsHint: quantizedBoundsHint,
            zOrderHint: zOrderHint,
            typeHint: typeHint,
            sourceXObjectName: sourceXObjectName
        )
    }

    func identifiesSameReplayTarget(as other: Self) -> Bool {
        replayIdentity == other.replayIdentity
    }
}

struct PDFObjectReplayIdentity: Hashable {
    var pageRefID: UUID
    var structuralDigest: UInt64
    var quantizedBoundsHint: [Int]
    var zOrderHint: Int
    var typeHint: String
    var sourceXObjectName: String?
}

/// Overflow-safe distance for untrusted persisted replay hints. These values rank candidates;
/// they never need signed arithmetic, and malformed extremes must not trap document replay.
enum PDFObjectReplayHintDistance {
    static func scalar(_ lhs: Int, _ rhs: Int) -> UInt {
        let lhsMagnitude = lhs.magnitude
        let rhsMagnitude = rhs.magnitude
        if (lhs < 0) == (rhs < 0) {
            return lhsMagnitude >= rhsMagnitude
                ? lhsMagnitude - rhsMagnitude
                : rhsMagnitude - lhsMagnitude
        }
        let (sum, overflow) = lhsMagnitude.addingReportingOverflow(rhsMagnitude)
        return overflow ? .max : sum
    }

    static func bounds(_ lhs: [Int], _ rhs: [Int]) -> UInt {
        guard lhs.count == 4, rhs.count == 4 else { return .max }
        return zip(lhs, rhs).reduce(into: UInt(0)) { total, pair in
            let (sum, overflow) = total.addingReportingOverflow(scalar(pair.0, pair.1))
            total = overflow ? .max : sum
        }
    }
}

// MARK: - §3.3 DetectedObject

struct DetectedObject: Codable, Identifiable {
    // identity
    var id: UUID = UUID()                  // fresh per detection pass; dies with the cache
    var stableKey: PDFObjectStableKey      // durable cross-reopen identity
    var markedContentId: Int?              // FPDFPageObj_AddMark hint (Phase-0-PROVEN durable)
    var pageRefID: UUID?                    // PageRef.id join key

    // classification
    var objectType: PDFObjectType
    var sourceType: PDFObjectSource
    var confidence: PDFTextEditConfidence
    var editability: PDFObjectEditability

    // geometry (raw content-stream space)
    var boundsPdf: CGRect                   // FPDFPageObj_GetBounds — POST-matrix AABB; a hit-test
                                            // hint, NOT the thing move/resize edits.
    var transform: PDFTextTransform         // FPDFPageObj_GetMatrix. Move/resize mutate THIS.
    var pageRotation: CGFloat               // page /Rotate, verbatim
    var zOrder: Int                         // FPDFPage_GetObject index at detection

    // style + typed payloads
    var style: PDFObjectStyle
    var pathData: PDFPathData?
    var imageMetadata: PDFObjectImageMetadata?
    var clipInfo: PDFObjectClipInfo = .init()

    // grouping
    var groupSource: PDFObjectGroupSource = .none
    var children: [UUID] = []
    var isGroupChild: Bool = false
    var formXObjectName: String?
    var isBackgroundLike: Bool = false      // ≥92% crop-box area / full-bleed / decorative

    // session-only (excluded from CodingKeys and ==)
    var boundsViewport: CGRect?             // pdfView.convert result; recomputed, never persisted
    var detectedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, stableKey, markedContentId, pageRefID, objectType, sourceType, confidence, editability
        case boundsPdf, transform, pageRotation, zOrder, style, pathData, imageMetadata, clipInfo
        case groupSource, children, isGroupChild, formXObjectName, isBackgroundLike, detectedAt
        // boundsViewport deliberately omitted
    }

    init(id: UUID = UUID(), stableKey: PDFObjectStableKey, markedContentId: Int? = nil,
         pageRefID: UUID?, objectType: PDFObjectType, sourceType: PDFObjectSource,
         confidence: PDFTextEditConfidence, editability: PDFObjectEditability,
         boundsPdf: CGRect, transform: PDFTextTransform, pageRotation: CGFloat, zOrder: Int,
         style: PDFObjectStyle, pathData: PDFPathData? = nil, imageMetadata: PDFObjectImageMetadata? = nil,
         clipInfo: PDFObjectClipInfo = .init(), groupSource: PDFObjectGroupSource = .none,
         children: [UUID] = [], isGroupChild: Bool = false, formXObjectName: String? = nil,
         isBackgroundLike: Bool = false, boundsViewport: CGRect? = nil, detectedAt: Date = Date()) {
        self.id = id
        self.stableKey = stableKey
        self.markedContentId = markedContentId
        self.pageRefID = pageRefID
        self.objectType = objectType
        self.sourceType = sourceType
        self.confidence = confidence
        self.editability = editability
        self.boundsPdf = boundsPdf
        self.transform = transform
        self.pageRotation = pageRotation
        self.zOrder = zOrder
        self.style = style
        self.pathData = pathData
        self.imageMetadata = imageMetadata
        self.clipInfo = clipInfo
        self.groupSource = groupSource
        self.children = children
        self.isGroupChild = isGroupChild
        self.formXObjectName = formXObjectName
        self.isBackgroundLike = isBackgroundLike
        self.boundsViewport = boundsViewport
        self.detectedAt = detectedAt
    }

    var capabilities: ObjectCapabilities { editability.capabilities }
}

extension DetectedObject: Equatable {
    /// Excludes the session-only `boundsViewport`/`detectedAt` and the per-pass random `id`
    /// (two objects re-detected across passes should compare equal on their intrinsic content).
    static func == (l: DetectedObject, r: DetectedObject) -> Bool {
        l.stableKey == r.stableKey && l.markedContentId == r.markedContentId
            && l.pageRefID == r.pageRefID && l.objectType == r.objectType
            && l.sourceType == r.sourceType && l.confidence == r.confidence
            && l.editability == r.editability && l.boundsPdf == r.boundsPdf
            && l.transform == r.transform && l.pageRotation == r.pageRotation
            && l.zOrder == r.zOrder && l.style == r.style && l.pathData == r.pathData
            && l.imageMetadata == r.imageMetadata && l.clipInfo == r.clipInfo
            && l.groupSource == r.groupSource && l.children == r.children
            && l.isGroupChild == r.isGroupChild && l.formXObjectName == r.formXObjectName
            && l.isBackgroundLike == r.isBackgroundLike
    }
}

// MARK: - §3.4 PageObjectMap (transient per-page index)

struct PageObjectMap: Equatable {          // NOT Codable — never serialized
    var pageRefID: UUID
    var objects: [DetectedObject]           // ascending zOrder
    var analysisRevision: Int = 0           // debug/telemetry only
    /// True when the object scan hit its safety cap (mirrors PageGraphicsIndex.didTruncateScan).
    var didTruncateScan: Bool = false
    /// Total PDFium page-object count INCLUDING text objects (which detection skips). The
    /// absolute top draw index is `rawObjectCount - 1`; z-order "front"/"back" operate on this
    /// absolute space, so callers must compare against it — NOT against the detected subset,
    /// whose extremes exclude text and would make "bring to front" appear to no-op on an image
    /// sitting under a text layer.
    var rawObjectCount: Int = 0

    init(pageRefID: UUID, objects: [DetectedObject], analysisRevision: Int = 0,
         didTruncateScan: Bool = false, rawObjectCount: Int = 0) {
        self.pageRefID = pageRefID
        self.objects = objects
        self.analysisRevision = analysisRevision
        self.didTruncateScan = didTruncateScan
        self.rawObjectCount = rawObjectCount
    }

    static let empty = PageObjectMap(pageRefID: UUID(), objects: [])
}

// MARK: - §4 Editability classification

enum PDFObjectEditability: String, Codable {
    case directAnnotationEdit          // annotation-backed (ink/note/stamp/Orifold signature)
    case directVectorEdit              // high-confidence path/line/rect/ellipse, no clip
    case directImageEdit               // high-confidence image XObject, no soft mask, no clip
    case formWidgetEdit                // PDFKit widget
    case formXObjectInstanceEdit       // one placed instance of a reused /Form XObject (ships v1)
    case formXObjectSourceEdit         // editing the shared /Form stream (v1-DEFERRED → message)
    case groupedObjectEdit             // inferred tableGrid cluster
    case inferredArtifactEdit          // medium/low-confidence decorative rule/divider/tint
    case rasterRegionReplace           // clipped/masked/flattened soup; cover/replace only
    case lockedOrPermissionRestricted  // !allowsContentModification / crypto-signed
    case unsupported                   // shading/gradient, unclassifiable
}

/// The UI / hit-test / export dispatch key off THIS derived set, not a second enum (§4.1).
struct ObjectCapabilities: Equatable {
    var canMove = false
    var canResize = false
    var canRotate = false
    var canRestyle = false
    var canReplaceImage = false
    var canDeleteStructurally = false
    var canDuplicate = false
    var canLayer = false
    var isOverlayBacked = false     // Orifold annotation/decoration → baked, never a content write
    var isReadOnly = false
}

extension PDFObjectEditability {
    var capabilities: ObjectCapabilities {
        switch self {
        case .directAnnotationEdit:
            return ObjectCapabilities(canMove: true, canResize: true, canRotate: true, canRestyle: true,
                                      canDeleteStructurally: true, canDuplicate: true, canLayer: true,
                                      isOverlayBacked: true)
        case .directVectorEdit:
            return ObjectCapabilities(canMove: true, canResize: true, canRotate: true, canRestyle: true,
                                      canDeleteStructurally: true, canDuplicate: true, canLayer: true)
        case .directImageEdit:
            return ObjectCapabilities(canMove: true, canResize: true, canRotate: true, canReplaceImage: true,
                                      canDeleteStructurally: true, canDuplicate: true, canLayer: true)
        case .formWidgetEdit:
            // Reposition/remove only; duplication breaks AcroForm names; content managed in form tools.
            return ObjectCapabilities(canMove: true, canResize: true, canDeleteStructurally: true, canLayer: true)
        case .formXObjectInstanceEdit:
            return ObjectCapabilities(canMove: true, canResize: true, canRotate: true,
                                      canDeleteStructurally: true, canDuplicate: true, canLayer: true)
        case .groupedObjectEdit:
            return ObjectCapabilities(canMove: true, canResize: true, canRestyle: true,
                                      canDeleteStructurally: true, canDuplicate: true, canLayer: true)
        case .inferredArtifactEdit:
            // Not default-selectable; move/delete/restyle/opacity/layer once explicitly picked.
            return ObjectCapabilities(canMove: true, canRestyle: true, canDeleteStructurally: true, canLayer: true)
        case .rasterRegionReplace:
            // Cover/replace a region only; true removal via the gated qpdf redaction path (not here).
            return ObjectCapabilities(canReplaceImage: true)
        case .formXObjectSourceEdit, .lockedOrPermissionRestricted, .unsupported:
            // formXObjectSourceEdit is v1-deferred: select + inspect only (no safe per-page write).
            return ObjectCapabilities(isReadOnly: true)
        }
    }

    /// Localized fallback/disclosure message key (nil when the type is fully editable). English
    /// values live in Localizable.xcstrings (§4 table, added in the UX phase).
    var fallbackMessageKey: String? {
        switch self {
        case .directAnnotationEdit, .directVectorEdit: return nil
        case .directImageEdit: return "object.editability.image.styleUnsupported"
        case .formWidgetEdit: return "object.editability.formWidget.restricted"
        case .formXObjectInstanceEdit: return "object.editability.formXObject.instanceOnly"
        case .formXObjectSourceEdit: return "object.editability.formXObject.sourceDeferred"
        case .groupedObjectEdit: return "object.editability.group.hint"
        case .inferredArtifactEdit: return "object.editability.artifact.lowConfidence"
        case .rasterRegionReplace: return "object.editability.raster.regionOnly"
        case .lockedOrPermissionRestricted: return "object.editability.locked"
        case .unsupported: return "object.editability.unsupported"
        }
    }
}

// MARK: - §8.1 Operation model

enum ObjectEditType: String, Codable {
    case objectTransform, objectDelete, objectReplace, objectStyleChange, objectReorder
}

enum ObjectReplacementStrategy: String, Codable {
    case pdfiumStructural   // SetMatrix/Transform/Set*Color + RemoveObject/InsertObjectAtIndex (leak-free)
    case overlayComposite   // Orifold overlay baked on export; never a content-stream write
    case coverPatch         // visual-only cover (rasterRegionReplace ONLY; disclosed; DOES leak)
    case qpdfRedact         // gated explicit "true removal" fallback
}

enum ObjectCommitState: String, Codable { case preview, committed, reverted }

struct ObjectStylePayload: Codable, Equatable {   // absent key = unchanged; CodableColor reused
    var strokeColor: CodableColor?
    var fillColor: CodableColor?
    var opacity: CGFloat?
    var lineWidth: CGFloat?
    var dashArray: [CGFloat]?
    var dashPhase: CGFloat?

    init(strokeColor: CodableColor? = nil, fillColor: CodableColor? = nil, opacity: CGFloat? = nil,
         lineWidth: CGFloat? = nil, dashArray: [CGFloat]? = nil, dashPhase: CGFloat? = nil) {
        self.strokeColor = strokeColor
        self.fillColor = fillColor
        self.opacity = opacity
        self.lineWidth = lineWidth
        self.dashArray = dashArray
        self.dashPhase = dashPhase
    }

    /// The PDFium structural lane currently supports only direct fill, stroke, and width
    /// setters. Keep projection and byte replay on one fail-closed contract so a persisted
    /// unsupported payload can never look applied in the canvas while bytes stay unchanged.
    var isSupportedForStructuralReplay: Bool {
        opacity == nil
            && dashArray == nil
            && dashPhase == nil
            && (strokeColor != nil || fillColor != nil || lineWidth != nil)
    }
}

struct ObjectEditOperation: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var type: ObjectEditType
    var documentID: UUID            // MemberDocument.id
    var pageRefID: UUID             // PageRef.id — durable join key
    var sourceObjectKey: PDFObjectStableKey   // canonical durable identity
    var markedContentId: Int?       // FPDFPageObj_AddMark hint (Phase-0-proven durable)
    var objectType: PDFObjectType
    var editability: PDFObjectEditability
    // geometry — RAW, UNROTATED content-stream space
    var originalBoundsPdf: CGRect
    var newBoundsPdf: CGRect
    var originalTransform: PDFTextTransform
    var newTransform: PDFTextTransform
    var pageRotation: Int
    // style
    var originalStylePayload: ObjectStylePayload?
    var newStylePayload: ObjectStylePayload?
    // z-order (PDFium object-index order); realized by RemoveObject + InsertObjectAtIndex
    var originalZIndex: Int
    var newZIndex: Int
    var replacementStrategy: ObjectReplacementStrategy
    var replacementImageData: Data?   // objectReplace only; keep to the RESAMPLED image
    var committedState: ObjectCommitState
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    enum CodingKeys: String, CodingKey {
        case id, type, documentID, pageRefID, sourceObjectKey, markedContentId, objectType, editability
        case originalBoundsPdf, newBoundsPdf, originalTransform, newTransform, pageRotation
        case originalStylePayload, newStylePayload, originalZIndex, newZIndex
        case replacementStrategy, replacementImageData, committedState, createdAt, updatedAt
    }

    init(id: UUID = UUID(), type: ObjectEditType, documentID: UUID, pageRefID: UUID,
         sourceObjectKey: PDFObjectStableKey, markedContentId: Int? = nil, objectType: PDFObjectType,
         editability: PDFObjectEditability, originalBoundsPdf: CGRect, newBoundsPdf: CGRect,
         originalTransform: PDFTextTransform, newTransform: PDFTextTransform, pageRotation: Int,
         originalStylePayload: ObjectStylePayload? = nil, newStylePayload: ObjectStylePayload? = nil,
         originalZIndex: Int, newZIndex: Int, replacementStrategy: ObjectReplacementStrategy,
         replacementImageData: Data? = nil, committedState: ObjectCommitState = .committed,
         createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.type = type
        self.documentID = documentID
        self.pageRefID = pageRefID
        self.sourceObjectKey = sourceObjectKey
        self.markedContentId = markedContentId
        self.objectType = objectType
        self.editability = editability
        self.originalBoundsPdf = originalBoundsPdf
        self.newBoundsPdf = newBoundsPdf
        self.originalTransform = originalTransform
        self.newTransform = newTransform
        self.pageRotation = pageRotation
        self.originalStylePayload = originalStylePayload
        self.newStylePayload = newStylePayload
        self.originalZIndex = originalZIndex
        self.newZIndex = newZIndex
        self.replacementStrategy = replacementStrategy
        self.replacementImageData = replacementImageData
        self.committedState = committedState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(ObjectEditType.self, forKey: .type)
        documentID = try c.decode(UUID.self, forKey: .documentID)
        pageRefID = try c.decode(UUID.self, forKey: .pageRefID)
        sourceObjectKey = try c.decode(PDFObjectStableKey.self, forKey: .sourceObjectKey)
        markedContentId = try c.decodeIfPresent(Int.self, forKey: .markedContentId)
        objectType = try c.decode(PDFObjectType.self, forKey: .objectType)
        editability = try c.decode(PDFObjectEditability.self, forKey: .editability)
        originalBoundsPdf = try c.decode(CGRect.self, forKey: .originalBoundsPdf)
        newBoundsPdf = try c.decode(CGRect.self, forKey: .newBoundsPdf)
        originalTransform = try c.decodeIfPresent(PDFTextTransform.self, forKey: .originalTransform) ?? .identity
        newTransform = try c.decodeIfPresent(PDFTextTransform.self, forKey: .newTransform) ?? .identity
        pageRotation = try c.decodeIfPresent(Int.self, forKey: .pageRotation) ?? 0
        originalStylePayload = try c.decodeIfPresent(ObjectStylePayload.self, forKey: .originalStylePayload)
        newStylePayload = try c.decodeIfPresent(ObjectStylePayload.self, forKey: .newStylePayload)
        originalZIndex = try c.decodeIfPresent(Int.self, forKey: .originalZIndex) ?? 0
        newZIndex = try c.decodeIfPresent(Int.self, forKey: .newZIndex) ?? 0
        replacementStrategy = try c.decodeIfPresent(ObjectReplacementStrategy.self, forKey: .replacementStrategy) ?? .pdfiumStructural
        replacementImageData = try c.decodeIfPresent(Data.self, forKey: .replacementImageData)
        committedState = try c.decodeIfPresent(ObjectCommitState.self, forKey: .committedState) ?? .committed
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    }
}

// MARK: - §8.2 Per-page operation state

struct PageObjectEditState: Codable, Identifiable, Equatable {
    var pageRefID: UUID
    var operations: [ObjectEditOperation] = []
    var id: UUID { pageRefID }

    init(pageRefID: UUID, operations: [ObjectEditOperation] = []) {
        self.pageRefID = pageRefID
        self.operations = operations
    }
}
