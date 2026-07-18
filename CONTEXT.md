# Domain language

The vocabulary Orifold's code uses for itself. Terms here are load-bearing: they name
invariants that span several files, and most of them previously existed only in comments
next to one of their uses.

Architecture vocabulary (module, interface, seam, adapter, depth) is separate and lives in
the `codebase-design` skill — this file is about the PDF-editing domain.

## Workspace and its parts

**Workspace** — the edited document model: the members it was assembled from, the page order,
decorations, comments, signatures, and per-page edit state. One window edits one workspace.

**Member** (`MemberDocument`) — one imported PDF inside a workspace. A workspace assembled
from three files has three members; a merged export flattens them into one PDF.

**Page ref** (`PageRef`) — a page's identity in the workspace, as `(member, source page
index)`. Page order is a list of page refs, so reordering and cross-member moves never
renumber anything.

## Byte lanes

Each member's bytes exist in up to three lanes, and a mutation that touches one generally
has to touch all of them:

- **Live** (`memberPDFData`) — the current bytes, carrying every committed edit.
- **Pristine base** (`originalMemberPDFData`) — the bytes as imported, with no baked edits.
  Kept only for members that actually have committed edits.
- **Object base** (`objectBaseData`) — the base that object-level edits apply to.

The bases carry no baked edits, so a document-level change (metadata, attachments) must be
applied to each lane independently. Skipping the bases lets a later **replay** resurrect the
old state; applying the live transform to them would double-apply the committed edits.

**Member-byte mutation** (`mutateMemberBytes`) — the one flow that transforms every present
lane, aborts atomically if any lane fails, and registers a single isolated undo step whose
inverse re-registers itself for redo. Metadata and attachment editing are its two callers.

## Preserving, replaying, baking

**Preserving** — the rule that page content is never rebuilt through PDFKit. Changes graft
onto the qpdf or PDFium object graph instead, so text layers, annotations and structure
survive. Named in `replacingInteractiveState`, `runJobPreservingSource`, and the replay
engines.

**Replay** (`WorkspaceEditReplayEngine`) — regenerating a member's bytes from its committed
edit operations: object ops first, then text overlays, then grafting live annotations back.

**Bake** — flattening something that is currently a live annotation or an overlay into page
content, so it survives passes that discard annotations. Signatures, decorations, comments
and form fields are all baked on export.

**Bake stamp** (`BakeStamp`) — an invisible off-page FreeText annotation carrying a hash of
the operations a page's bytes were baked from. Lets a later session tell whether bytes are in
sync with operations without re-rendering. It is engine bookkeeping, not user markup, so
every scan of a page's annotations must exclude it — use `BakeStamp.userAnnotations(on:)`.
Written through PDFium (raw key) and read through PDFKit (leading slash); both spellings
derive from one constant.

**Baked bytes** (`BakedPDFData`) — export bytes whose annotations are already flattened.
Imposition requires them: PDFium's N-up rebuilds pages as form XObjects and drops live
annotations, producing structurally valid output with the stamps silently missing. The type
exists so that precondition cannot be forgotten.

## Export

**Assembly** — merging members into one PDF. A merged PDF has exactly one `/Info`
dictionary, so assembly must pick whose document properties survive; it adopts the first
member's. The Info inspector therefore reads and writes that same member, or the user would
edit properties the merge discards.

**Decoration** — a watermark, stamp, hanko, image, page number, or Bates number placed on a
page. All six bake through one baker.

**Imposition** — laying pages onto sheets: saddle-stitch **booklet** (2-up, padded to a
multiple of four, folio order) or **N-up** (a rows × cols grid). Runs after the bake and
compression, before attachment re-injection.

**Sanitize** — the share-safe pass that strips metadata and embedded files. Deliberately runs
*after* attachments are re-injected, so asking for both still removes them.

## Editing surfaces

**Armed placement** (`PendingPlacement`) — the single click-to-place action waiting for a
page click: a signature, stamp, hanko, or barcode. Exactly one may be armed, which is why it
is one slot rather than parallel flags.

**Structure revision** (`structureRevision`) — a counter bumped by every `rebuild()`. Undo
and redo revert the model without changing which member is selected, so this is the only
signal an inspector draft can watch to re-seed itself. Editable inspector tabs get that
wiring from the `inspectorDraft` modifier rather than repeating it.
