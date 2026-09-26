# Next Orifold improvements — Sol execution plan

Prepared September 25, 2026 against local `main` at `c7e43447583b1eeb0e7738e5ec6cf19a7cee408c`.

Planning only. Application code was inspected, not changed or executed. No build, test suite, native acceptance, hosted CI, or release verification was run for this plan. Confidence describes implementation feasibility from current source, not measured demand. Effort is relative scope, not a calendar estimate.

The untracked September 12 planning draft is preserved. This document updates its sequencing: true redaction now exists in this checkout, so it is no longer a proposed new engine. The public release status was not checked. Older `docs/*_PLAN.md` and the July open-source roadmap contain historical proposals that have since been implemented; source takes precedence.

## Recommendation

Start with **reliable, inspectable folder workflows**. Users already have OCR, compression, and watermark engines; the missing piece is knowing exactly what happened to each file and repeating a useful configuration. Ship this as two independently reviewable slices: **A, batch results and safe output creation**, then **B, reusable presets**.

Next, improve **comparison reliability and cancellation** (C). A local comparison report (D) becomes useful only once incomplete analysis cannot look like “no changes.” The larger feature worth investigating afterward is **search-assisted redaction** (E), with an explicit geometry/correctness gate before implementation.

| Order | Outcome | Confidence | Effort | Main tradeoff |
|---|---|---|---|---|
| A | Per-file batch results; preserve existing outputs during naming collisions | High for results; writer change needs a focused correctness proof | Medium | Less flashy, directly improves an existing workflow |
| B | Built-in presets plus one saved custom configuration | High | Small–medium | Deliberately limited settings, no automation platform |
| C | Comparison progress, cancellation, and honest incomplete states | High for control wiring; medium for completeness handling | Medium | Some extraction APIs currently erase failure distinctions |
| D | Export a readable local comparison summary | Medium, depends on C | Small–medium after C | Must describe scope and missing evidence accurately |
| E | Find text, review matches, mark selected matches for redaction | Medium; spike first | Medium–large | Search geometry and sensitive-content limits require proof |

## A. Batch results and safe output creation — implement first

### User flow

Choose **Fold a Folder**, choose operations, confirm a folder, watch progress, then see a session-only result sheet. Every planned input has a result: **completed**, **failed**, **cancelled while processing**, or **not started**. Show filename plus relative source folder when names repeat; successful rows reveal their output in Finder. Include filters and a summary whose counts sum to the planned input count.

Cancellation keeps the report available. Folder-creation failure displays the actual error and leaves all inputs not started. Retain the most recent result until the next run or window close, with a way to reopen it. Do not persist paths or result history.

“Planned inputs” means the discovered eligible PDFs, not every file in the folder. Carry `FolderScanResult.wasTruncated` into the report: the existing scanner stops after 10,000 entries. Show incomplete-scan scope explicitly, distinguish an empty scan from a known scan failure, and do not invent counts for undiscovered files. Keep broader scanner redesign out of this slice.

### Verified starting points

- `Orifold/Engine/BatchFoldService.swift:34–57`: `FileOutcome` and `RunResult` already hold successes, output URLs, failures and cancellation, but no complete input ledger or setup error.
- `BatchFoldService.swift:230–242`: output-directory creation failure returns an empty result, losing the underlying error.
- `BatchFoldService.swift:265–290`: names come from a directory snapshot; the loop uses the shared replacement-capable writer. Cancellation exits without an outcome for the interrupted input.
- `Orifold/Engine/ExportFileWriter.swift:42–66`: existing destinations can be replaced, and the direct-write fallback can overwrite. Sequential naming tests do not prove safety if another writer creates the selected name after enumeration. This is a source-level risk, not a reproduced data-loss incident.
- `Orifold/ViewModels/WorkspaceViewModel.swift:10346`: `presentBatchFoldResult` reduces the run to counts/first error; cancelled runs lose the output-folder action.
- `Tests/OrifoldTests/BatchFoldServiceTests.swift`: covers ordinary mixed outcomes, pre-existing collisions and between-file cancellation; extend these behaviors rather than duplicating engine tests.

### Implementation sequence

1. Extend the result contract with planned inputs, explicit per-input states, and an optional run-level setup failure. Capture the input list once. Keep completed rows truthful if cancellation arrives after a file has committed. Check cancellation immediately before starting a write; interruption during the atomic commit is not promised.
2. Add a **create-new output path** for batch use. Keep intentional Save/Export replacement semantics intact. Validate staged bytes before publication; commit without replacing an existing destination. On a concurrent name collision, select the next suffix and retry with a bounded limit. On exhaustion or permission failure, report that input as failed.
3. Prove the write contract before integrating the UI: no check-then-overwrite path, no overwrite fallback, and no removal of a file owned by another writer during cleanup. Inject a narrow filesystem/write seam only where required to force these failure paths deterministically. Do not build a general job framework.
4. Present the report through the existing batch lifecycle, preserving operation IDs and cancellation guards. Add a small result view/presentation model instead of another large section of unrelated logic in `WorkspaceViewModel`.
5. Add all user-facing strings in six languages; update batch-fold documentation to match the delivered behavior.

Apple documents that `withoutOverwriting` rejects an existing destination and cannot be combined with `atomic`. Merely combining write flags is therefore not a solution to the staging-plus-publication requirement. Select and test a supported no-replace commit primitive during implementation; fail closed if it is unavailable on a destination. [Apple: withoutOverwriting](https://developer.apple.com/documentation/foundation/nsdata/writingoptions/withoutoverwriting)

### Acceptance

- Mixed valid/unreadable PDFs; locked/password-protected and oversized inputs with truthful failures under existing limits; all failed; empty/truncated scan; duplicate names in nested folders; pre-existing output names, including case-only variants.
- A destination appears between naming and commit: its bytes stay identical, and the new output gets a different name or an explicit failure. Exercise the actual commit boundary, not only the name helper.
- Permission/setup failure, validation failure, publication failure and temporary-file cleanup. Injected failure must leave no completed-looking partial PDF at the final path.
- Cancel before the first input, during a transform, between inputs, and around commit. Ledger counts reconcile; successfully committed files remain successful; no unstarted file is labelled failed.
- Originals and pre-existing outputs remain byte-identical. Active workspace contents and its undo stack are unaffected.
- Dismiss/reopen results, start a later run, remove an output externally, and exercise Finder reveal failure gracefully. Late callbacks cannot update the next run.
- Native keyboard navigation, VoiceOver labels and localized counts/errors are checked with synthetic files.

**Out of scope:** automatic retry, persistent history, watchers, scheduled work, passwords stored for reuse, parallel PDF transforms. Retry can follow later with fresh permissions and re-read source bytes.

**Stop rule:** if safe publication needs a broader writer redesign, stop at a tested writer slice and report that dependency. Do not ship the report with a stronger preservation claim than the writer can uphold.

## B. Reusable batch presets

Built-ins: **Searchable copies** (OCR), **Smaller copies** (balanced compression), **Review copies** (standard DRAFT watermark plus balanced compression). Add one custom saved configuration with save/replace/delete, not a named recipe library.

`Orifold/Views/BatchFoldSheet.swift` currently constructs `BatchFoldService.Options` from transient state. Use a small versioned settings value for OCR toggle, compression enum, and standard watermark choice. Persist no source/destination paths, custom watermark text, passwords, identities, or document text. Resolve standard watermark wording through localization when a run starts; custom text remains editable for that run.

Selecting a preset populates the existing controls and visible summary; it never runs a job. Keep the current options action → folder confirmation flow. Snapshot options for the active run.

Test option equivalence to manual configuration, relaunch persistence, corrupt/unknown settings fallback, empty configuration disabling, save/delete without execution, and changes during an active run. Audit the packaged privacy declaration when adding storage usage. Apple describes UserDefaults as storage for nonsensitive configuration and requires declaring its API use. [Apple: UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)

Dependency: A is the recommended delivery sequence, not an engine-level dependency. Keep B separately reviewable.

## C. Trustworthy, cancellable comparisons

`PDFComparisonService.compare` accepts progress and cancellation callbacks, but `ComparePanelModel.run` supplies neither. Its `runToken` prevents stale final display, not obsolete computation. Reuse the existing thread-safe `OperationCancellationToken`; keep UI updates on MainActor and engine work detached.

Split into two commits:

1. **Run control:** page-pair progress; Cancel; cancel on dismissal and offset change; only the newest run accepts progress or final results. Explicit running/completed/cancelled/failed states. Cancellation is cooperative between pairs, not interruption inside an active rasterization call. Use throttled updates and test late callbacks, rapid offset changes and rapid reopen.
2. **Evidence completeness:** do not label absent analysis as unchanged. Today optional visual/text channels default to no change, invalid right bytes return an empty array, and cancellation returns a partial array. Introduce a minimal run result with terminal status and per-pair channel availability. Distinguish a legitimate empty text layer from an extraction failure through a narrow extraction-result API; do not silently turn the latter into empty text. A known difference can still be shown when another channel is unavailable, with the missing channel disclosed.

Model actual left/right page indices and the pages excluded by a manual offset. Positive offsets can omit leading right pages; extreme negative offsets can produce index slots with no page on either side under the current formula. Exclude empty slots, account for unmatched/excluded pages, and never imply complete document equivalence from a scoped comparison.

Cover request preparation too: `WorkspaceViewModel.prepareCompare(withOtherFileAt:)` currently skips a workspace page when combined-page lookup or member bytes are missing. Preserve original workspace page identities/numbers and represent these omissions as unavailable coverage before invoking the engine; do not renumber the remaining pages into an apparently complete comparison.

Acceptance: identical/changed/one-sided pages, scans, malformed bytes, failed rendering/extraction, empty valid text, coarse text comparison, missing-source pages during preparation, reordered/multi-member workspaces, both offset signs and offsets larger than either document. Use injected failures for uncommon channel failures. Measure cancellation latency on a synthetic large fixture and record hardware/page characteristics; do not promise universal 300-page performance.

Stop after C if representing completeness requires broader engine work. D remains disabled/deferred until the result contract is trustworthy.

## D. Export a comparison summary

After C, add **Save comparison summary…** producing local Markdown via the existing destination workflow. Use `CommentSummaryExporter` as a formatting pattern, not a reason to create a generic report subsystem.

Include filenames, comparison direction (picked/right draft → workspace/left), offset, actual page numbers, coverage/exclusions, changed/unmatched counts, and word additions/deletions only when `comparedExhaustively` is true. Display unavailable channels and coarse results explicitly. Export only the completed current run; no report from cancelled, stale or failed work.

No full document text, screenshots, automatic sharing, automatic page alignment, or legal-equivalence language. Test Markdown escaping, Unicode filenames, offset numbering, incomplete channels, stale-run disabling and failed writes. Neither input PDF is mutated.

## E. Bigger feature: search-assisted redaction — conditional

User outcome: find a repeated phrase, review where it appears, select matches, then **Mark selected matches** using the existing redaction review/apply flow. The first version accepts a literal phrase only; no AI, NER, regex patterns, automatic OCR, or unattended redaction.

Current pieces: `SearchView` displays `PDFSelection` matches; `WorkspaceViewModel` resolves page references and exposes `addRedactionMark`; `PDFTextAnalysisEngine` binds PDFium character geometry; `applyRedactions` already handles member-byte mutation and refuses marked pages with pending text/object-edit operations and regions intersecting form widgets. These pieces justify a spike, not a claim that search results can safely be converted directly to rectangles.

**Timebox the first task to a proof fixture and design decision:** map literal match ranges to tight PDF-space rectangles on multiline, rotated, cropped/nonzero-origin, ligature/Unicode and OCR-text fixtures. Verify against the current visible document revision, deduplicate overlaps and handle multi-member/reordered pages. Prefer existing geometry APIs; any new C binding must meet the release-build signature rule. If text cannot be mapped reliably, report the unsupported match and require manual marking. Unsupported/scanned pages must never look like a complete zero-match search.

Only after the spike passes: a session-only match review list, selected-match marking as one undo group, stale-match invalidation after any content/geometry revision, and the existing explicit Apply confirmation. Refused pages remain refused.

The current redaction design explicitly excludes metadata, bookmark titles and structure-tree Alt/ActualText; comments and attachments can also contain copies independent of the selected page content. Preserve visible limitations and do not claim “all sensitive content removed.” Sanitization is not proof that every such store was scrubbed. Broader cleanup is a separate design. Member-byte redactions remain undoable in-session; intersecting comment-anchor snippets and rich-import source payload scrubbing are intentionally not undone. Original source files remain outside this operation.

Gate using `RedactionEngineTests`, `RedactionWorkflowTests`, save/reopen/export/replay fixtures and native selection/marking acceptance. Test that adding/removing proposed marks changes no PDF bytes; only explicit Apply mutates them. A geometry failure defers E without holding A–D.

## Deferred choices

- **Hindi/more OCR engines:** valuable, but needs recognition-quality fixtures, optional model packaging and a maintenance decision. Do not infer current language coverage from the July roadmap.
- **Large-document optimization:** first profile cold open, navigation, thumbnails, comparison and memory on synthetic large files; optimize measured bottlenecks. C addresses an already visible control gap without inventing a speed target.
- **Cloud AI, sync and collaboration:** not part of this local-document-processing plan.
- **Object-edit expansion, notarization, OS/toolchain upgrade:** separate correctness, publisher-credential or compatibility work. No credentials are needed for A–D.

## Execution and verification contract

At execution time recheck HEAD, instructions, dirty files, active worktrees and current source. Do not overwrite either planning document or unrelated changes. Use an isolated `stay-calm-its-codex/…` worktree/branch when appropriate. Baseline failures are evidence to diagnose; do not lower CI policy or treat an old failure mentioned in September 12 notes as still current.

For each implemented slice: focused XCTest behavior coverage, `swift build`, `swift test`, `swiftlint lint --quiet`, `git diff --check`; keep SwiftPM/Xcode manifests consistent and regenerate the Xcode project when files/resources/manifests require it. Run `swift build -c release` for any new/changed C bindings. Verify localization coverage and raw-key checks for UI strings. Refresh Graphify after code changes and corroborate a scoped query with source.

Run native acceptance of the touched flow using generated fictional PDFs. Record tests actually run, skips, failures and untested environments. A passing unit suite is not proof of Finder permissions, VoiceOver or packaged-app behavior. A new automated native smoke flow can be added where it meaningfully protects a touched path; avoid a broad test-infrastructure rewrite.

This request authorized planning only. The handoff below is text for the user to give Sol later. It requests A only; B–E need subsequent selection. Merge, push, tag, release and installed-app replacement are separate actions unless explicitly included in the user's execution instruction.

## Copy/paste handoff to Sol

> Implement slice A of `docs/plans/2026-09-25-next-features-sol.md`: reliable per-file batch results and safe create-new output publication. Read the plan, current repository instructions and current source first; preserve unrelated work. Work in a dedicated branch/worktree. Prove concurrent-collision protection and cancellation/setup failure outcomes with focused tests, then wire the session-only results UI and six-language strings. Complete the plan's relevant checks and native acceptance using fictional fixtures; report any unverified native behavior plainly. Keep ordinary intentional Save replacement behavior unchanged. Stop at a reviewable implementation with verification evidence; do not start B–E, merge, push, tag, publish, or replace my installed app. If safe output publication requires a larger redesign, finish a bounded tested prerequisite and report the remaining dependency.
