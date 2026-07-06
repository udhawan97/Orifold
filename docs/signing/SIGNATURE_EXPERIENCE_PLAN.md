# Orifold Signature Experience — Redesign & Hardening Plan

Status: **PLAN ONLY — no implementation in this document's authoring session.**
Audience: Sonnet (implementer), reviewers.
Date: 2026-07-06.

---

## 0. Ground truth: what already exists (verified in this session)

This plan is **not greenfield**. A prior effort (see `docs/signing/SIGNING_SPEC.md` and
`docs/signing/VERIFICATION.md`) already shipped a real cryptographic signing pipeline:

| Component | File(s) | State |
|---|---|---|
| Incremental-update PDF signer (ByteRange, `/Contents` splice, append-only) | `Orifold/Signing/SigningContracts.swift` (`PDFIncrementalSigner`) | **Implemented & externally verified** — `pdfsig` reports *"Signature is Valid / Total document signed"*, SubFilter `ETSI.CAdES.detached` |
| CMS/CAdES SignedData builder (PAdES B-B/B-T, ESS `signing-certificate-v2`, RFC-3161 unsigned attr) | `Orifold/Signing/CMS/CMSSignatureBuilder.swift` | Implemented, unit-tested |
| RFC-3161 timestamp client (default `https://freetsa.org/tsr`, graceful B-B fallback) | `Orifold/Signing/Timestamp/` | Implemented, unit-tested |
| Identity providers: `.p12`/`.pfx` import (`SecPKCS12Import`), Keychain identities, self-signed generation (swift-certificates) | `Orifold/Signing/Identity/` | Implemented |
| Appearance renderer (Form XObject for crypto widget + bake-into-page for visual) | `Orifold/Signing/Appearance/` | Implemented, tested |
| Visual export-survival baking | `SignatureExportBaker` | Implemented, tested |
| UI: Type / Initials / Digital tabs, intent fields, TSA toggle, trust popover, bundled certificate guide | `Orifold/Views/SignaturePalette.swift`, `docs/signing/CERTIFICATE_GUIDE.md` (bundled as resource) | Implemented, basic |
| FOSS deps | `Package.swift`: swift-crypto, swift-asn1, swift-certificates (all Apache-2.0) | In place |

**Consequence:** the user-visible problem ("Digital feels incomplete / not professional") is
mostly a **UX, lifecycle, and hardening** problem, not a missing-crypto problem. The plan below
keeps the verified byte-exact core untouched wherever possible and builds around it.

### Known defects / gaps found during planning review (must-fix list)

These were found by reading the current code and are the technical heart of this plan:

1. **No persistent certificate profiles.** `resolveSigningIdentity` resolves ad hoc at
   placement time; **self-signed generates a brand-new certificate every signing**
   (`SelfSignedSigningIdentityProvider.generate` per call). Recipients can never build trust in
   a cert that changes each time, and the Keychain accumulates orphan keys. Need a
   `DigitalCertificateProfile` store with create-once/reuse semantics.
2. **Non-ASCII strings are mangled.** `pdfLiteralString` in `SigningContracts.swift` maps UTF-8
   bytes to Latin-1 characters one by one. Signer names / reasons in Japanese, German, Hindi,
   etc. will corrupt. PDF text strings must be written as UTF-16BE with BOM (`(\xFE\xFF...)`)
   or PDFDocEncoded when representable. Orifold ships 6 languages — this is a real bug.
3. **Signing runs synchronously on the main thread** (`signAndExportCryptographicPDF` uses
   `NSSavePanel.runModal` then a synchronous TSA fetch + full-file hashing). Large PDFs or a
   slow TSA freeze the UI. Needs an async task with progress + cancel.
4. **Classic-xref-only incremental writer.** `PDFIncrementalUpdatePlan` emits a classic `xref`
   table with `/Prev`. That is fine when the base bytes come from Orifold's own export pipeline
   (which normalizes), but re-signing an **externally produced PDF whose last xref is a
   cross-reference stream** (most modern PDFs) yields a hybrid many validators reject.
   Must **detect** xref-stream trailers and either (a) emit an xref-stream incremental section,
   or (b) fail safely with a clear message ("Orifold will rewrite this PDF before signing" via
   the qpdf normalization path). Never emit a corrupt file.
5. **The regex/string PDF parsing in `PDFIncrementalUpdatePlan`** (`parsePageObjectNumber`
   scanning `N 0 obj … endobj` text) breaks on PDFs with object streams, binary content that
   isn't valid UTF-8, or page objects inside object streams. Same mitigation as (4): sign only
   Orifold-normalized bytes (run through the existing qpdf/serializer export first), and detect
   + refuse anything else. Make the precondition explicit and tested.
6. **Wrong-`.p12`-password UX**: `SecPKCS12Import` failure surfaces as a raw error; no retry
   loop, no "wrong password" specific message, no attempt counting.
7. **Crypto appearance stream only renders the typed name** (`.typedName(...)`), ignoring the
   reason/location/date metadata that the *preview image* shows — the exported appearance and
   the in-app preview don't match. One renderer, one truth.
8. **No signature reading/validation**: Orifold cannot show whether an *opened* PDF already has
   signatures, nor self-check its own output beyond `verifyExportedFile`. Users can't see
   chain/expiry/status anywhere.
9. **No Draw mode** (freehand). The earlier spec removed it deliberately; product decision
   below reintroduces it properly.
10. **`/Contents` placeholder is fixed at 32,768 hex chars (16 KB DER)** — adequate for
    self-signed + timestamp, but a `.p12` with a long chain plus a large TSA token can
    overflow. Size the placeholder from the actual identity (estimate = chain DER + 8 KB slack,
    min 16 KB) instead of a constant.

---

## 1. Product strategy — the signature system in plain English

Orifold offers **two families** of signatures, and the UI must never blur them:

### Family A — Visual signatures (appearance only)
Ink on paper, digitally. They change how the page **looks**, nothing else.

- **Typed signature** — your name rendered in a script font. Good for: informal approvals,
  internal documents, "sign here" workflows where the counterparty just wants a mark.
  Cannot guarantee: who signed, when, or that the file wasn't altered afterwards.
- **Drawn signature** *(reintroduced in this plan)* — freehand with trackpad/mouse/tablet.
  Same guarantees (none) as typed; feels more personal.
- **Initials** — compact mark for "initial each page". Same guarantees as typed.

### Family B — Digital signatures (cryptographic)
Mathematics, not pictures. The PDF gains an embedded CMS/PKCS#7 (CAdES) signature over the
file's bytes. Any PDF reader with signature support (Acrobat, Foxit, Okular, `pdfsig`) can
verify: *the document has not been modified since signing*, and *which certificate signed it*.
A visible appearance is attached, but the appearance is cosmetic — the cryptography is the
signature.

- **Self-signed digital signature** — Orifold generates a certificate for you, free, locally.
  Guarantees: tamper-evidence (any change after signing is detectable), a stable signer
  certificate. Cannot guarantee: your *identity* to strangers — Acrobat will show
  "Signed. Validity unknown / identity not verified" until the recipient trusts your
  certificate once. Perfect for: internal workflows, teams that exchange certificates,
  personal archiving, testing.
- **CA-issued digital signature** — you buy/obtain a Digital ID from a Certificate Authority
  (ideally on the Adobe Approved Trust List, or an eIDAS-qualified provider in the EU) and
  import the `.p12`/`.pfx`. Guarantees: tamper-evidence **plus** automatic identity trust in
  readers that trust that CA (Acrobat trusts AATL + EUTL out of the box). This is the option
  for signing contracts with strangers.
- **Timestamped signature (RFC 3161)** — an add-on to either of the above. A timestamp
  authority countersigns the signature value, proving the signature existed at a given time
  even if your certificate later expires. Depends on trusting the TSA. Orifold already
  supports this with a free TSA default and graceful fallback.

### Honest-language matrix (use this wording everywhere in UI and docs)

| Option | Proves document unchanged? | Proves signer identity? | Legal weight |
|---|---|---|---|
| Typed / Drawn / Initials | No | No | Appearance only — like a pasted image. May still be acceptable where "simple electronic signatures" are (many jurisdictions), but Orifold makes **no claim**. |
| Self-signed digital | **Yes** | Only to recipients who trust your cert | Cryptographically real; trust must be established manually |
| CA-issued digital | **Yes** | **Yes**, where the reader trusts the CA (AATL/EUTL) | Strongest practical option; in the EU, a qualified cert (QES) has statutory standing |
| + Timestamp | Adds proof of *when* | — | Strengthens evidence; depends on TSA trust |

**Never** use the phrase "legally binding" in the app. Approved phrasing: *"tamper-evident"*,
*"cryptographically signed"*, *"identity not independently verified"* (self-signed),
*"trusted automatically by readers that trust this CA"* (CA-issued).

---

## 2. Proposed UX redesign

### 2.1 Panel structure

Replace the current 3-segment picker with a **4-mode selector** and a two-zone layout
(mode content on top, shared preview card + primary action at the bottom):

```
┌─ Signatures ────────────────────────────── ⓘ Guide ─┐
│  [ Type ] [ Draw ] [ Initials ] [ Digital ID ]      │
│  ─────────────────────────────────────────────      │
│  (mode-specific content)                             │
│                                                      │
│  ┌─ Preview card ─────────────────────────────┐     │
│  │   ~formal appearance preview~              │     │
│  │   ⛩ chip row: [Visual only] or             │     │
│  │   [🔏 Self-signed] [🕐 Timestamped] [⚠ …]  │     │
│  └────────────────────────────────────────────┘     │
│  hint line (one sentence, honest-language matrix)    │
│  [        Place signature        ]                   │
└──────────────────────────────────────────────────────┘
```

- **Type** — unchanged flow (name field → preview → place). Add font choice later (P4).
- **Draw** — new: a drawing canvas (NSBezierPath capture, pressure if available), Clear/Undo,
  smoothed stroke; output stored as PNG (and retain the vector points in the profile for
  re-rendering at export resolution). Saved drawn signatures persist as reusable
  `SignatureProfile`s so users draw once.
- **Initials** — unchanged flow.
- **Digital ID** — redesigned; see below.

### 2.2 Digital ID section

```
Digital ID
  ┌ identity selector (menu) ──────────────────────────┐
  │ ● My self-signed ID — "Umang Dhawan" (exp 2027-07) │
  │ ○ Imported: work-id.p12 — "U. Dhawan, ACME" ✅ CA  │
  │ ○ Keychain: …                                      │
  │ ──────────────                                     │
  │ + Create local self-signed ID…                     │
  │ + Import .p12 / .pfx…                              │
  │ ⚙ Manage certificates…                             │
  │ ？ How to get a verified (CA-issued) ID…           │
  └────────────────────────────────────────────────────┘
  Intent fields:  Signer name · Reason · Location · Contact
  ☑ Request trusted timestamp (RFC 3161)   ⓘ
  Certificate status line:  "Self-signed · valid until 2027-07-04"
```

Key behavioral changes vs today:

- **Identities are persistent profiles**, listed by friendly name + status chip
  (`Self-signed` / `CA-issued` / `Expired` / `Expires soon`). Selecting one never re-imports
  or re-generates.
- **Create self-signed ID…** opens a small sheet: Name (required), Email (optional),
  Organization (optional), validity (default 2 years). One click → stored in Keychain →
  becomes the selected profile. Explains in one line: *"Free. Recipients will see 'identity
  not verified' until they trust this certificate once."* Offers **Export public certificate
  (.cer)…** so the user can send it to recipients for the manual-trust flow.
- **Import .p12/.pfx…** opens file picker → password sheet (SecureField) → on wrong password,
  inline error *"That password didn't unlock this file. Passwords are case-sensitive."* with
  retry; after 3 failures suggest checking with the issuer. On success show parsed summary
  (subject CN, issuer, expiry, chain length) before saving the profile.
- **Manage certificates…** sheet: list profiles, inspect (subject, issuer, serial, validity,
  chain, key algorithm, SHA-256 fingerprint), export public cert, **delete** (with Keychain
  cleanup and a warning that previously signed PDFs remain valid).
- **Learn how to get a verified certificate** → opens the existing bundled guide (§3).

### 2.3 Preview card

One shared `SignaturePreviewCard` used by all four modes and by the exported appearance
(§4 — same renderer, so preview == output):

- Formal layout: script-font name (left), metadata block (right): "Digitally signed by …",
  date, reason, location — mirroring the Acrobat convention users recognize.
- Chips under the card: `Visual only` (gray) / `Self-signed` (indigo) / `CA-issued` (green) /
  `Timestamped` (with clock icon) / `Certificate expired` (red, blocks signing).
- Origami accent: use the existing `OrifoldFoldMark`/fold motif as a subtle watermark corner on
  crypto previews — distinctive but not noisy, consistent with the app's Japanese aesthetic.

### 2.4 Validation hints (contextual one-liners)

Show exactly one hint under the preview, chosen by state:

- Visual modes: *"This is a visual signature only — it does not protect the document from
  changes."*
- Digital, self-signed: *"This PDF will contain a cryptographic signature. Recipients may see
  'identity not verified' unless they trust your certificate."*
- Digital, CA-issued: *"CA-issued signatures are trusted automatically by readers that trust
  the issuing authority."*
- After signing: *"Any further edit will invalidate the cryptographic signature."* (the
  view-model already tracks this at `WorkspaceViewModel` lines ~2138/3790 — keep and surface.)

### 2.5 Sign & Export flow

- Rename button to **"Sign & Export PDF…"** with a lock-seal icon; only enabled when a crypto
  placement exists (current behavior, keep).
- Async progress sheet: *Preparing document → Building signature → Requesting timestamp →
  Writing file → Verifying*. Cancelable before "Writing file".
- Success state: checkmark + file path + **"How to verify this PDF"** disclosure (per-reader
  instructions, §3) + "Reveal in Finder".
- Failure state: specific message per `SigningError`, never a silent no-op, and **never a
  half-written file** (write to temp, verify, then atomically move — extend the existing
  `writeExportData`/`verifyExportedFile` path).

---

## 3. Built-in user guide

Keep the single-source-of-truth model already in place (`docs/signing/CERTIFICATE_GUIDE.md`
bundled to `Orifold/Resources/`, rendered in-app). Expand it into a sectioned **Signature
Guide** sheet with a sidebar TOC (rendered from the markdown headings):

1. **What is a digital signature?** — plain-English: math over the file's bytes; any change
   breaks it; different from a picture of your signature.
2. **What is a certificate / Digital ID?** — keypair + identity attestation; X.509 in one
   paragraph, no jargon dump.
3. **What is a .p12/.pfx file?** — a password-protected bundle of your certificate + private
   key. **Warning box:** never share it or its password; anyone holding it can sign as you.
4. **Self-signed vs CA-issued** — the table from §1; screenshots of what Acrobat shows for
   each (bundle two small annotated screenshots).
5. **Create a free self-signed ID** — the in-app flow, plus the equivalent OpenSSL commands
   for power users (already drafted in VERIFICATION.md).
6. **Import a certificate** — steps + wrong-password troubleshooting.
7. **Verify a signed PDF** —
   - Adobe Acrobat Reader: signature panel, what "validity unknown" means, how a recipient
     trusts a self-signed cert once (Certificate viewer → Trust → Add to Trusted Certificates).
   - macOS Preview: shows/preserves the signature field appearance but **does not validate**
     cryptographic signatures — say so explicitly to preempt confusion.
   - Command line: `pdfsig` (poppler, `brew install poppler`), `pyHanko` (`pip install
     pyhanko`) — both FOSS validators; include exact commands.
   - Browsers: Chrome/Firefox built-in viewers render but don't validate — signature appears
     as an image only.
8. **Get a CA-issued Digital ID** — keep current honest content (AATL explanation,
   ~US $180–600/yr typical, buy direct from provider). Add:
   - **Free/low-cost realistic paths:** there is **no free AATL document-signing cert**; say
     so plainly. Cheaper routes worth listing (verify current pricing at implementation time,
     link official pages only): EU **eIDAS qualified certificates** via national eID schemes
     (several member states issue them free or near-free with the national ID card; Estonian
     e-Residency for non-EU residents — card fee, then signing is free and EUTL-trusted);
     institutional IDs (many universities/employers issue S/MIME+document-signing certs via
     Sectigo/GÉANT); sector schemes (US federal PIV/CAC).
   - Provider list (AATL members: DigiCert, GlobalSign, Entrust, Sectigo, SSL.com, Certum…)
     with links to their document-signing pages and to Adobe's AATL member list.
9. **FAQ** — "Is this legally binding?" (jurisdiction-dependent; Orifold provides the
   cryptography, not legal advice), "Why does Preview not show a green check?", "What happens
   if I edit after signing?", "What if my certificate expires?" (timestamped signatures remain
   verifiable at time-of-signing; that's what the timestamp is for).

Localization: the guide ships in English first with a header noting so; UI strings around it
are localized in all 6 languages. (Translating the full guide is a P4 stretch item.)

---

## 4. Technical architecture

### 4.1 Layers (mostly exists — reorganize, don't rewrite)

```
SignaturePalette / sheets (SwiftUI)           ← redesign (§2)
   │
SignatureCenter (new @Observable coordinator) ← new: owns profiles, selection, async signing
   │
├─ SignatureProfileStore     (new)  — visual profiles (typed/drawn/initials), JSON in App Support
├─ CertificateProfileStore   (new)  — DigitalCertificateProfile metadata (JSON) + Keychain refs
├─ SigningIdentity providers (exists) — p12 / Keychain / self-signed
├─ SignatureAppearanceRenderer (exists, extend) — ONE renderer → preview image, XObject, bake
├─ PDFSigningService         (new thin façade) — wraps PDFIncrementalSigner + CMSSignatureBuilder
│                                                + TimestampClient; async; progress reporting;
│                                                pre-flight checks (xref type, encryption, size)
├─ SignatureValidationService (new) — read /Sig fields of opened PDFs; self-check exports
└─ Export pipeline           (exists) — SignatureExportBaker for visual; sign-last ordering
```

Pre-flight in `PDFSigningService` (fail-safe rules):
- Base bytes must be Orifold's own normalized export output (classic xref, no object-stream
  pages) **or** pass an explicit structure probe; otherwise route through the existing
  qpdf normalization step first, and if that's impossible (encrypted with unknown password,
  malformed), throw a typed error with a user-facing message. Never hand arbitrary bytes to
  the regex-based `PDFIncrementalUpdatePlan`.
- Size `/Contents` placeholder from identity chain length (§0 item 10).
- Refuse to sign when the selected certificate is expired (allow override only for
  self-signed testing, behind a confirm dialog).

### 4.2 Data model (Codable; keep `SignaturePlacement` back-compat)

```swift
/// A reusable saved appearance the user created (typed, drawn, initials).
struct SignatureProfile: Codable, Identifiable {
    let id: UUID
    var kind: Kind                    // .typed(name:fontID:), .drawn(strokes:[Stroke], pngCache:Data), .initials(text:)
    var displayName: String
    var createdAt: Date
}

/// Persistent metadata for a signing identity. Private key stays in Keychain — NEVER here.
struct DigitalCertificateProfile: Codable, Identifiable {
    let id: UUID
    var label: String                 // user-facing, e.g. "My self-signed ID"
    var source: Source                // .selfSignedGenerated, .importedP12(originalFilename:), .keychainReference
    var keychainPersistentRef: Data   // SecIdentity persistent reference
    var subjectCommonName: String
    var issuerCommonName: String
    var serialHex: String
    var notBefore: Date
    var notAfter: Date
    var isSelfSigned: Bool
    var chainCertificatesDER: [Data]  // public certs only (needed to embed chain)
    var keyAlgorithm: String          // "RSA-2048", "ECDSA-P256"
    var sha256Fingerprint: String
}

/// What the visible stamp looks like. Feeds preview, XObject, and bake identically.
struct SignatureAppearance: Codable {
    var profileID: UUID?              // visual profile, or nil for generated crypto layout
    var showDate: Bool
    var showReason: Bool
    var showLocation: Bool
    var showDistinguishedName: Bool
    var accent: AccentStyle           // .none, .foldMark (origami watermark)
}

/// Why/where/when — maps onto /Reason /Location /ContactInfo /M and CMS signing-time.
struct SignatureIntent: Codable {
    var signerName: String
    var reason: String?
    var location: String?
    var contactInfo: String?
    var requestTimestamp: Bool
    var tsaURL: URL?                  // nil = default (freetsa), user-overridable in settings
}

/// Outcome of a Sign & Export run — drives the success/failure sheet.
struct SignatureExportResult {
    var outputURL: URL
    var subFilter: String             // ETSI.CAdES.detached | adbe.pkcs7.detached
    var timestampApplied: Bool
    var timestampFallbackReason: String?
    var certificate: DigitalCertificateProfile
    var byteRange: [Int]
    var selfCheck: SignatureValidationResult
}

/// Result of validating one signature (ours post-export, or one found in an opened PDF).
struct SignatureValidationResult {
    enum Integrity { case intact, modified, unverifiable(reason: String) }
    enum IdentityTrust { case selfSigned, chainPresentUntrusted, caIssued, expired, unknown }
    var fieldName: String
    var signerCommonName: String?
    var signingTime: Date?
    var integrity: Integrity          // digest over ByteRange matches?
    var identityTrust: IdentityTrust  // best-effort local classification — NOT Adobe's verdict
    var timestamped: Bool
    var coversWholeDocument: Bool     // ByteRange end == EOF (else "modified after signing")
    var notes: [String]
}
```

`SignaturePlacement` keeps its current fields (`kind`, `signerIdentityRef`, `reason`, …) and
gains `certificateProfileID: UUID?` (optional → old files decode fine).

### 4.3 Validation/diagnostic service scope (be realistic)

Phase 3 implements **local, best-effort** validation: parse `/AcroForm /Fields` → `/Sig`
dictionaries, check ByteRange coverage, recompute the digest, verify the CMS signature and
`message-digest` attribute with swift-crypto/swift-certificates, classify chain
(self-signed vs chained), check validity dates. It does **not** replicate Acrobat trust
decisions (no AATL/EUTL store, no revocation checking in this phase) — the UI must label the
verdict *"Checked by Orifold — open in Adobe Reader for authoritative trust status."*

### 4.4 Error taxonomy

Extend `SigningError` with user-mappable cases: `.wrongPassphrase`, `.certificateExpired`,
`.unsupportedPDFStructure(detail:)`, `.encryptedDocument`, `.timestampUnavailable` (exists),
`.contentsPlaceholderTooSmall` (exists), `.keychainAccessDenied`, `.cancelled`. Every case has
a localized, actionable message. Signing failures leave the original document untouched and
delete any temp output.

---

## 5. Security & privacy safeguards

- **Private keys live only in the macOS Keychain** (already true for self-signed; extend to
  imported p12: after `SecPKCS12Import`, persist the `SecIdentity` into the Keychain and store
  only a persistent ref — never key bytes on disk, never in the profile JSON).
- **Passwords:** `.p12` passphrases are read into a `SecureField`, passed directly to
  `SecPKCS12Import`, and **never persisted, logged, or placed in `UserDefaults`**. No
  "remember password" (the key is re-wrapped into Keychain, so the password isn't needed again).
- **Logging:** signing code paths must not log key material, passphrases, DER blobs, or full
  subject DNs at default log level. Add a test/grep CI check for `print(`/os_log in
  `Orifold/Signing/`.
- **Self-signed warning:** creation sheet + hint line state the trust limitation up front
  (wording in §2.4). No dark patterns pushing paid CAs — just facts.
- **Deletion:** Manage Certificates → delete removes the profile JSON **and** the Keychain
  identity (SecItemDelete by persistent ref), with confirm dialog noting existing signed PDFs
  stay valid.
- **Local-only:** the only network call in the entire signing system is the optional RFC-3161
  POST (contains only a hash — no document content, no identity). Say this in the guide. TSA
  is user-configurable and can be disabled.
- **Fail safe:** temp-file + verify + atomic move (extend existing `writeExportData`); any
  thrown error → no output file, clear message, original untouched.

---

## 6. Capability phases (rebased on actual current state)

**Phase 1 — Experience & lifecycle (the big visible win)**
- 4-mode palette (Type / Draw / Initials / Digital ID); Draw canvas + reusable profiles.
- `CertificateProfileStore` + Manage Certificates sheet; create-once self-signed flow with
  export-public-cert; persistent p12 import with password retry UX.
- Shared `SignaturePreviewCard` + chips + honest hint lines.
- Expanded in-app Signature Guide (§3) with verify-instructions.
- Full L10n for every new string (all 6 languages; keep the `LocalizationCoverageTests` green).

**Phase 2 — Hardening the crypto path (mostly invisible, high trust)**
- Fix UTF-16BE PDF strings (§0 item 2); async signing with progress/cancel (item 3);
  xref-stream detection + normalize-or-refuse pre-flight (items 4–5); dynamic `/Contents`
  sizing (item 10); unified appearance renderer for preview==export (item 7);
  wrong-password taxonomy (item 6); expired-cert refusal.
- Post-export self-check surfaced in the success sheet ("Orifold verified: signature intact").
- Verification matrix rerun and `docs/signing/VERIFICATION.md` updated with fresh output.

**Phase 3 — Visibility & multi-signature**
- `SignatureValidationService`: signature panel for opened PDFs (list signatures, integrity,
  signer, time, "modified after signing" via ByteRange-vs-EOF).
- Certificate chain display in Manage/Inspect.
- Multi-signature UX: sign → reopen → countersign (engine already append-only preserves
  priors — `testSecondSignaturePreservesTheFirst`); per-signature status list.
- Signature field locking (`/Lock` dict / DocMDP `/P` levels) — place field, choose "no
  changes allowed / form fill allowed".

**Phase 4 — Exploration (only if demand)**
- LTV (embed OCSP/CRL + `/DSS`): significant scope; document as exploration, prototype with
  pyHanko cross-checks before committing.
- Font choices for typed signatures (bundle 2–3 SIL-OFL script fonts, subset on embed).
- Full guide translation; team profile export/import (a signed bundle of public certs).

---

## 7. Acceptance criteria

Functional (each becomes an XCTest or scripted QA step):

1. Type signature: unchanged flow places and survives export → reopen (existing
   `SignatureExportSurvivalTests` stay green).
2. Initials: same.
3. Draw: a drawn signature can be created, saved, reused across app launches, placed, exported.
4. Digital ID import: valid `.p12` → profile appears with correct CN/expiry; persists across
   launches; private key retrievable only via Keychain.
5. Wrong `.p12` password → specific inline error, retry offered, no crash, no partial profile.
6. Self-signed generation: created **once**, reused on subsequent signings (assert the cert
   serial is stable across two sign operations).
7. Signed PDF opens in Adobe Acrobat Reader with the signature panel showing the signature,
   "document has not been modified", and the visible appearance matching the in-app preview.
8. Self-signed output: `pdfsig` reports *Signature is Valid* + *Certificate issuer is unknown*
   (this exact pair is the expected, documented state).
9. CA-issued `.p12` (test with any chained cert): chain embedded (verify via
   `openssl pkcs7 -print_certs` on the extracted `/Contents`), validates where trusted.
10. Export never silently fails: every error path sets `exportError` with a distinct message;
    fault-injection tests for TSA down (→ B-B fallback + notice), disk full, cancelled panel.
11. Signed output byte-verifies: Orifold's own post-export self-check passes; original file
    untouched on failure.
12. Unsupported structure (xref-stream external PDF, encrypted PDF) → clear refusal message,
    no output file, no corruption.
13. Non-ASCII signer name (e.g. "山田太郎") round-trips correctly in Acrobat's signature panel.
14. All new strings present in all 6 language tables (`LocalizationCoverageTests`).
15. `swift build` + full `swift test` green (SPM only, no xcodebuild).

---

## 8. Edge cases

| Case | Planned behavior |
|---|---|
| Password-protected PDF | Existing decrypt-on-open flow; signing operates on decrypted bytes; **sign+encrypt in one export is refused** with message (already partially enforced at WVM:3790) — offer "encrypt first, then sign" ordering note |
| Already-signed PDF (opened) | P3: show signature panel; editing warns it invalidates; re-signing appends incrementally preserving priors — but only if structure probe passes, else explain |
| PDFs with forms | AcroForm merge: incremental update must **extend** an existing `/AcroForm /Fields` array, not replace it (current `catalogBody()` strips and re-adds `/AcroForm` — P2 fix: preserve existing fields; add test with a form PDF) |
| Flattened vs not | Crypto signing always runs on final flattened export bytes (current design — keep); visual placements bake before signing |
| Multiple signature fields | P3; engine ready, UX listed above |
| Expired certificate | Refuse (override behind confirm for self-signed); chip shows "Expired" |
| Revoked certificate | Out of scope to *check* (no OCSP until P4) — guide explains readers may flag it |
| Missing chain in p12 | Import succeeds; profile notes "issuer certificate not included — recipients may see an incomplete chain"; embed what exists |
| Wrong .p12 password | §2.2 retry UX |
| Unsupported cert format (.pem/.cer without key) | Detect and explain: "This file contains a certificate but no private key. You need the .p12/.pfx export that includes your key." |
| User signs visually, expects validation | Hint line + export summary says "visual only"; the Sign & Export button is only in the Digital tab |
| PDF modified after signing | Readers flag it (that's the design working); Orifold's own edit path warns before invalidating; P3 panel shows "signature does not cover latest changes" via ByteRange-vs-EOF |
| Huge PDFs / scanned PDFs | Async signing + progress (P2); hashing is streaming-friendly (digest input already concatenates spans — switch to incremental SHA-256 update to avoid a second full copy) |

---

## 9. UI polish checklist

- `SignaturePreviewCard`: paper-white card, subtle shadow, serif header, script name, metadata
  column, chips (§2.3); identical rendering source as export.
- Status chips: pill style consistent with existing DS tokens (`dsAccent`, `dsSeparator`);
  colors: gray=visual, indigo=self-signed, green=CA, red=expired.
- Security iconography: `checkmark.seal`, `lock.doc`, `clock.badge.checkmark` SF Symbols only —
  no fake "verified" badges on unverified states.
- Disabled states: every disabled button has a `.help()` tooltip explaining why.
- Export progress sheet with staged labels (§2.5); success sheet with "How to verify" and
  "Reveal in Finder".
- Hover help (`.help`) on: Reason, Location, Contact, timestamp toggle, TSA URL setting,
  each identity row, each chip.
- Typography: keep the app's serif titles / clean body; the guide sheet gets the same reading
  layout as existing sheets.
- Localization: all 6 languages (en, + the 5 existing); remember the xcstrings/SPM pitfall —
  strings must load via the established `L10n` Bundle.module path.
- Origami touch: fold-mark watermark option on crypto appearance (off by default, toggle in
  appearance options).

---

## 10. Open-source / licensing position (already clean — keep it that way)

| Dependency | License | Role |
|---|---|---|
| swift-crypto, swift-asn1, swift-certificates | Apache-2.0 | CMS, X.509, self-signed generation — **keep as the only crypto deps** |
| Apple Security.framework / CryptoKit / PDFKit | system | PKCS#12 import, Keychain, key ops (`SecKeyCreateSignature` — key never leaves Keychain) |
| qpdf (already bundled) | Apache-2.0 | normalization pre-flight for foreign PDFs |
| poppler `pdfsig`, OpenSSL CLI, pyHanko | GPL-2/Apache/MIT | **dev/test-time validators only — never bundled** (GPL of poppler is irrelevant since it's not shipped) |

Explicitly rejected: iText (AGPL — viral for a MIT-style app), PDFBox (JVM — wrong runtime,
but its `CreateSignature` remains the reference algorithm), pdf-lib (JS; no incremental-save
signing support anyway), node-forge (JS), commercial SDKs (PSPDFKit/ComPDF/etc. — paid),
bundling OpenSSL (unnecessary; Security.framework + swift-crypto cover everything).
No SaaS, no server, no telemetry. The only network egress is the optional TSA POST of a hash.

---

## 11. Testing matrix

Automated (SPM tests):
- Existing suites stay green: `PDFByteRangeCalculatorTests`, `PDFIncrementalSignerStructureTests`,
  `SignatureExportSurvivalTests`, `CMSSignatureBuilderTests`, `TimestampClientTests`,
  `SignatureAppearanceTests`, `LocalizationCoverageTests`.
- New: profile store CRUD + Keychain lifecycle; wrong-password; expired cert; UTF-16BE string
  encoding; AcroForm-merge with form PDF; xref-stream refusal; dynamic `/Contents` sizing;
  self-signed serial stability; validation service on known-good/known-tampered fixtures
  (flip one byte inside ByteRange → integrity == .modified).

Manual QA matrix (record results in `docs/signing/VERIFICATION.md`):

| Viewer | Self-signed | CA-issued | Expired cert | Tampered file | Timestamped |
|---|---|---|---|---|---|
| Adobe Acrobat Reader (macOS) | valid, identity unknown | green check | flagged | "modified" flagged | time shown from TSA |
| Adobe Acrobat Reader (Windows, if available) | same | same | same | same | same |
| macOS Preview | appearance visible; **no validation UI** (expected) | — | — | — | — |
| Chrome / Firefox built-in viewer | appearance renders as image (expected) | — | — | — | — |
| `pdfsig` (poppler) | "Signature is Valid / issuer unknown" | "Valid" | reports expiry | "Signature is Invalid" | timestamp listed |
| pyHanko `validate` | cross-check verdicts | ✓ | ✓ | ✓ | ✓ |

Document classes: small text PDF, 200+ page PDF, scanned/image PDF, AcroForm PDF,
previously-signed PDF, non-ASCII metadata PDF.

---

## 12. Sonnet handoff prompt

> **Task:** Execute the Orifold signature-experience plan in
> `docs/signing/SIGNATURE_EXPERIENCE_PLAN.md`. Read it fully first, plus
> `docs/signing/SIGNING_SPEC.md` and `docs/signing/VERIFICATION.md`. The cryptographic core
> already works and is externally verified — do not rewrite `PDFIncrementalSigner`,
> `CMSSignatureBuilder`, or `TimestampClient` internals except where the plan names a specific
> defect (UTF-16BE strings, AcroForm merge, dynamic /Contents sizing, xref pre-flight).
>
> **Order of work:**
> 1. Phase 1 (UX & lifecycle): `CertificateProfileStore` + `SignatureProfileStore` (new files
>    under `Orifold/Signing/Profiles/`), Manage Certificates sheet, create-self-signed sheet,
>    p12 import flow with password retry, Draw mode canvas, 4-mode `SignaturePalette` rework,
>    `SignaturePreviewCard`, hint lines, expanded guide content in
>    `docs/signing/CERTIFICATE_GUIDE.md` (keep the single-source-bundling scheme). Files most
>    affected: `Orifold/Views/SignaturePalette.swift`, `Orifold/ViewModels/WorkspaceViewModel.swift`
>    (`resolveSigningIdentity` becomes profile-based), `Orifold/Models/SignaturePlacement.swift`
>    (add optional `certificateProfileID`), `Orifold/Signing/Identity/*`, all 6 `Localizable`
>    tables.
> 2. Phase 2 (hardening): items exactly as listed in plan §6 Phase 2; each defect in §0 gets a
>    failing test first.
> 3. Phase 3 only after 1–2 are merged and manually verified in Adobe Reader.
>
> **Test commands:** `swift build`; `swift test` (Xcode is NOT installed — never xcodebuild).
> Targeted: `swift test --filter PDFByteRangeCalculatorTests` etc. External check:
> `pdfsig out.pdf` (brew poppler), pyHanko for cross-validation.
>
> **Manual QA checklist:** run the §11 matrix rows you can locally (Acrobat Reader + Preview +
> pdfsig at minimum) and paste real output into `docs/signing/VERIFICATION.md`.
>
> **Hard constraints:** no regressions to Type/Initials (export-survival tests must stay
> green); FOSS deps only (Apache/MIT/BSD; no AGPL, no commercial SDKs, no OpenSSL bundling);
> zero cloud/server involvement — the only permitted network call is the optional RFC-3161 TSA
> POST; private keys only in Keychain; passwords never persisted or logged; all UI copy uses
> the honest-language matrix in plan §1 (never say "legally binding"); keep the Japanese/
> origami design language (existing DS tokens, serif headers, fold-mark motif); localize every
> new string in all 6 languages and keep `LocalizationCoverageTests` green; `.orifold` files
> saved by the current version must still open (back-compat decode test for
> `SignaturePlacement`).

---

## Appendix A — Competitive reference (research summary)

- **Adobe Acrobat**: "Fill & Sign" (visual) is fully separated from "Use a certificate"
  (crypto) — two different tools; certificate flow has Digital ID management, appearance
  editor, reason/location optional (off by default), timestamp preferences, and the
  green-check/questioned/failed triad. Orifold's separation into visual tabs vs Digital ID tab
  mirrors this correctly.
- **macOS Preview**: visual-only (camera/trackpad capture); no cryptographic signing or
  validation. This is why the guide must warn users that Preview won't show validity.
- **Foxit / PDF-XChange**: both expose Digital ID managers (list/import/create self-signed),
  reason/location fields, timestamp server configuration, and visible-appearance editors —
  the same profile-based lifecycle this plan adopts.
- **LibreOffice Draw**: signs via system certificate stores (GPG/X.509), demonstrating a fully
  FOSS signing stack is viable; weakness is discoverability — a lesson for keeping Orifold's
  flow beginner-first.
- **Open-source signing/validation ecosystem**: Apache PDFBox `CreateSignature` (reference
  algorithm for incremental signing), pyHanko (best-in-class FOSS PAdES signer/validator —
  use as test oracle), OpenPDF (LGPL/MPL, JVM), qpdf (structure normalization, no signing),
  `@signpdf` (JS, reference for ByteRange handling), poppler `pdfsig` (validator). Orifold's
  Swift-native approach (Security.framework + swift-certificates) avoids bundling any of
  these at runtime while using pyHanko/pdfsig as dev-time oracles.

## Appendix B — Review passes performed on this plan

- **Pass 1 (product/UX & beginner clarity):** ensured one honest hint per state instead of
  disclaimers everywhere; moved "how to verify" into the success sheet where it's actionable;
  renamed options to plain English ("Create local self-signed ID", not "Generate X.509");
  kept the paid-CA reality out of the main flow (popover + guide) so free users never feel
  nagged; confirmed Draw reintroduction is a product decision recorded here since the earlier
  spec removed it.
- **Pass 2 (technical/security/realism):** verified against current code that the crypto core
  exists and which defects are real (§0 list, each pinned to a file); scoped validation
  honestly (no AATL trust emulation, no revocation until P4); flagged xref-stream and
  AcroForm-merge as the two highest-risk correctness items; confirmed licensing table has no
  AGPL/commercial deps; confirmed the only network call is the TSA hash POST; kept LTV
  explicitly exploratory because embedding revocation data correctly (DSS/VRI) is a large,
  easy-to-get-wrong surface.
