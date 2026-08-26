import Foundation
import CoreGraphics

// =============================================================================
// PDFObjectEditEngine — the STRUCTURAL write-back for object editing (docs/OBJECT_EDITING_PLAN.md
// §8.3/§9 Lane A). Applies committed ObjectEditOperations to a member PDF's pages via the PDFium
// page-object API (SetMatrix / RemoveObject / Set*Color / RemoveObject+InsertObjectAtIndex),
// then GenerateContent + SaveAsCopy → new member bytes. Leak-free and ghost-free by construction:
// a moved object's matrix is mutated in place and a deleted object is physically removed, so the
// regenerated stream contains exactly the post-edit objects — never a cover patch, never a copy.
//
// Object identity is resolved by the SAME `structuralDigest` the detection engine computes
// (PDFObjectDetectionEngine.inspect), so an op re-binds to its physical object after the
// index-renumbering that every reload causes. Runs under `pdfiumLock`.
//
// MANDATORY (Phase 0, §0.2): `poeTouchPathColorsForGenerateContent` runs before every
// GenerateContent, or parsed path fills re-emit as black.
// =============================================================================

// FPDF_SaveAsCopy plumbing (guarded by pdfiumLock in the entry point). Reuses the single
// FPDFCompression_SaveAsCopy / FPDFCompressionFileWrite binding from PDFCompressionService — a
// second @_silgen_name binding of the same C symbol with a different Swift type breaks the
// release (whole-module) build.
private var poeEditSaveBuffer = Data()

enum PDFObjectEditEngine {

    /// Result of a write-back: the new member bytes plus, per op id, whether the op's target was
    /// resolved and applied (so the caller can flag unresolved ops rather than silently dropping).
    struct Result {
        var data: Data
        var appliedOpIDs: Set<UUID>
        var unresolvedOpIDs: Set<UUID>
    }

    /// Apply object operations to `memberData`, grouped by page index. Loads the document once,
    /// mutates each edited page, and saves a single copy. Returns nil only on a hard PDFium
    /// failure (unloadable document / GenerateContent / SaveAsCopy) — an op whose target can't be
    /// resolved is skipped and reported in `unresolvedOpIDs`, not treated as a failure.
    static func apply(operationsByPage: [Int: [ObjectEditOperation]], toMember memberData: Data) -> Result? {
        guard !memberData.isEmpty, memberData.count <= Int(Int32.max), !operationsByPage.isEmpty else {
            return Result(data: memberData, appliedOpIDs: [], unresolvedOpIDs: [])
        }
        pdfiumLock.lock()
        defer { pdfiumLock.unlock() }
        FPDF_InitLibrary()
        defer { FPDF_DestroyLibrary() }

        return memberData.withUnsafeBytes { raw -> Result? in
            guard let base = raw.baseAddress,
                  let doc = FPDF_LoadMemDocument(base, Int32(memberData.count), nil) else { return nil }
            defer { FPDF_CloseDocument(doc) }
            let pageCount = Int(FPDF_GetPageCount(doc))

            var applied: Set<UUID> = []
            var unresolved: Set<UUID> = []

            for (pageIndex, ops) in operationsByPage where !ops.isEmpty {
                guard pageIndex >= 0, pageIndex < pageCount, let page = poe_LoadPage(doc, Int32(pageIndex)) else {
                    ops.forEach { unresolved.insert($0.id) }
                    continue
                }
                let (a, u) = applyOps(ops, to: page)
                applied.formUnion(a)
                unresolved.formUnion(u)
                // MANDATORY color-preservation pass, then regenerate this page's content stream.
                poeTouchPathColorsForGenerateContent(page)
                let generated = poe_GenerateContent(page) != 0
                poe_ClosePage(page)
                guard generated else { return nil }
            }

            let saved = saveAsCopy(doc)
            guard !saved.isEmpty else { return nil }
            return Result(data: saved, appliedOpIDs: applied, unresolvedOpIDs: unresolved)
        }
    }

    // MARK: - Per-page op application

    private struct LiveObject {
        let handle: OpaquePointer?
        let digest: UInt64
        let boundsHint: [Int]
        let objectType: PDFObjectType
        let zOrderHint: Int
        let sourceXObjectName: String?
    }

    private static func applyOps(_ ops: [ObjectEditOperation], to page: OpaquePointer?) -> (Set<UUID>, Set<UUID>) {
        // One enumeration: snapshot every live object with its digest. Handles stay valid across
        // mutations of OTHER objects until the page closes, so we resolve everything up front and
        // then mutate — safe even when an op deletes an object (which renumbers indices).
        var live: [LiveObject] = []
        let pageArea: Double = Double(poe_GetPageWidth(page) * poe_GetPageHeight(page))
        let count = poe_CountObjects(page)
        for i in 0..<count {
            guard let obj = poe_GetObject(page, i),
                  let ins = PDFObjectDetectionEngine.inspect(obj: obj, pageArea: pageArea) else { continue }
            live.append(LiveObject(
                handle: obj,
                digest: ins.structuralDigest,
                boundsHint: ins.boundsHint,
                objectType: ins.objectType,
                zOrderHint: Int(i),
                sourceXObjectName: ins.formName
            ))
        }
        // Objects already claimed by a logical target this pass — so two visually identical
        // twins don't both bind to the same physical object. Operations for the same persisted
        // target reuse its binding, allowing compatible style/transform/reorder/delete sequences.
        var claimed = Set<Int>()   // indices into `live`
        var resolvedIndexByTarget: [PDFObjectReplayIdentity: Int] = [:]
        var applied: Set<UUID> = []
        var unresolved: Set<UUID> = []

        // Deletes/reorders change the page's object set; apply transforms/styles first, then
        // structural ops, so a transform+delete pair on the same object still resolves cleanly.
        let ordered = ops.sorted { orderRank($0.type) < orderRank($1.type) }

        for op in ordered {
            let target = op.sourceObjectKey.replayIdentity
            let resolvedIndex = resolvedIndexByTarget[target]
                ?? resolve(op: op, in: live, claimed: claimed)
            guard let idx = resolvedIndex else {
                unresolved.insert(op.id)
                continue
            }
            claimed.insert(idx)
            resolvedIndexByTarget[target] = idx
            let handle = live[idx].handle
            switch op.type {
            case .objectTransform:
                var m = POEFSMatrix(op.newTransform)
                if poe_SetMatrix(handle, &m) != 0 { applied.insert(op.id) } else { unresolved.insert(op.id) }
            case .objectStyleChange:
                if applyStyle(op.newStylePayload, to: handle) {
                    applied.insert(op.id)
                } else {
                    unresolved.insert(op.id)
                }
            case .objectReorder:
                // Remove then re-insert at the target index (clamped) — realizes bring/send.
                if poe_RemoveObject(page, handle) != 0 {
                    let target = max(0, min(op.newZIndex, Int(poe_CountObjects(page))))
                    if poe_InsertObjectAtIndex(page, handle, target) != 0 {
                        applied.insert(op.id)
                    } else {
                        poe_Destroy(handle)   // re-insert failed: free the detached object, don't leak
                        unresolved.insert(op.id)
                    }
                } else { unresolved.insert(op.id) }
            case .objectDelete:
                if op.replacementStrategy == .pdfiumStructural, poe_RemoveObject(page, handle) != 0 {
                    poe_Destroy(handle)          // ownership transferred by RemoveObject
                    applied.insert(op.id)
                } else {
                    unresolved.insert(op.id)     // coverPatch/raster deletes are handled elsewhere
                }
            case .objectReplace:
                unresolved.insert(op.id)         // image replacement — Phase 4
            }
        }
        return (applied, unresolved)
    }

    /// Transform/style before structural remove/reorder, so a handle claimed for a transform is
    /// still valid when a later delete op resolves against the (unchanged) digest set.
    private static func orderRank(_ t: ObjectEditType) -> Int {
        switch t {
        case .objectStyleChange: return 0
        case .objectTransform: return 1
        case .objectReorder: return 2
        case .objectReplace: return 3
        case .objectDelete: return 4
        }
    }

    /// Resolve a previously unseen logical target to a live object index: exact structuralDigest
    /// match, tie-broken by nearest quantized-bounds hint. Once resolved, every operation carrying
    /// the same full replay identity reuses that index. (AddMark fast-path is added later.)
    private static func resolve(op: ObjectEditOperation, in live: [LiveObject], claimed: Set<Int>) -> Int? {
        let identity = op.sourceObjectKey.replayIdentity
        var best: Int?
        var bestBoundsDistance = UInt.max
        var bestZDistance = UInt.max
        for (i, object) in live.enumerated()
        where !claimed.contains(i)
            && object.digest == identity.structuralDigest
            && (identity.typeHint.isEmpty || object.objectType.rawValue == identity.typeHint)
            && (identity.sourceXObjectName == nil || object.sourceXObjectName == identity.sourceXObjectName) {
            let boundsDistance = PDFObjectReplayHintDistance.bounds(
                object.boundsHint,
                identity.quantizedBoundsHint
            )
            let zDistance = PDFObjectReplayHintDistance.scalar(
                object.zOrderHint,
                identity.zOrderHint
            )
            if boundsDistance < bestBoundsDistance
                || (boundsDistance == bestBoundsDistance && zDistance < bestZDistance) {
                bestBoundsDistance = boundsDistance
                bestZDistance = zDistance
                best = i
            }
        }
        return best
    }

    private static func applyStyle(_ payload: ObjectStylePayload?, to handle: OpaquePointer?) -> Bool {
        guard let payload, payload.isSupportedForStructuralReplay else { return false }
        var attemptedSetter = false
        var allSucceeded = true
        if let fill = payload.fillColor {
            attemptedSetter = true
            allSucceeded = poe_SetFillColor(
                handle,
                UInt32(clampByte(fill.red)),
                UInt32(clampByte(fill.green)),
                UInt32(clampByte(fill.blue)),
                UInt32(clampByte(fill.alpha))
            ) != 0 && allSucceeded
        }
        if let stroke = payload.strokeColor {
            attemptedSetter = true
            allSucceeded = poe_SetStrokeColor(
                handle,
                UInt32(clampByte(stroke.red)),
                UInt32(clampByte(stroke.green)),
                UInt32(clampByte(stroke.blue)),
                UInt32(clampByte(stroke.alpha))
            ) != 0 && allSucceeded
        }
        if let width = payload.lineWidth {
            attemptedSetter = true
            allSucceeded = poe_SetStrokeWidth(handle, Float(max(0, width))) != 0 && allSucceeded
        }
        return attemptedSetter && allSucceeded
    }

    private static func clampByte(_ v: CGFloat) -> Int {
        Int((v * 255).rounded().clamped(to: 0...255))
    }

    /// Serializes an already-open PDFium document without routing its object graph through
    /// PDFKit. Callers must hold `pdfiumLock` and own the PDFium library lifetime.
    static func saveAsCopy(_ doc: OpaquePointer?) -> Data {
        poeEditSaveBuffer = Data()
        var fw = FPDFCompressionFileWrite(version: 1, writeBlock: { _, data, size in
            if let data, size > 0 { poeEditSaveBuffer.append(data.assumingMemoryBound(to: UInt8.self), count: Int(size)) }
            return 1
        })
        return FPDFCompression_SaveAsCopy(doc, &fw, UInt32(1 << 1)) != 0 ? poeEditSaveBuffer : Data()   // FPDF_NO_INCREMENTAL
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

// SetStrokeWidth binding — the only style setter not already declared in PDFiumObjectBindings.
// C: FPDFPageObj_SetStrokeWidth(FPDF_PAGEOBJECT, float width) — width is BY VALUE, not a pointer.
@_silgen_name("FPDFPageObj_SetStrokeWidth")
private func poe_SetStrokeWidth(_ obj: OpaquePointer?, _ width: Float) -> Int32
