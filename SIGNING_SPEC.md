# pdFold Digital Signature — Implementation Spec

Authentic, industry-standard PDF digital signatures for pdFold (macOS / Swift / SwiftUI).
Build with `swift build`; test with `swift test`. Xcode is NOT installed — do not use xcodebuild.

This spec is the shared contract for parallel subagents. The Swift interfaces already
exist as a compiling **walking skeleton** in [`PDFold/Signing/SigningContracts.swift`](PDFold/Signing/SigningContracts.swift);
every method throws `SigningError.notImplemented`. The acceptance tests in
[`Tests/PDFoldTests/PDFSigningTests.swift`](Tests/PDFoldTests/PDFSigningTests.swift) are
RED until you implement the modules. **Make them pass without weakening any assertion.**

## Two tiers, one appearance
1. **Visual e-signature** — Typed (handwriting font) or Initials, baked into exported bytes.
2. **Cryptographic digital signature** — PAdES (`ETSI.CAdES.detached`) **B-T** (basic + RFC-3161
   timestamp), validatable by Adobe Reader / `pdfsig`, tamper-evident, with a visible appearance.

## Hard constraints
- **FOSS only.** Allowed deps: `swift-crypto`, `swift-asn1`, `swift-certificates` (all Apache-2.0,
  swiftlang/apple) + Apple system frameworks (Security, CryptoKit, PDFKit, CoreGraphics).
  FORBIDDEN: iText, any AGPL/GPL/commercial lib, bundling OpenSSL.
- **PDFKit cannot create `/Sig` fields.** Signing is raw-bytes incremental update only.
- **Signing is terminal & append-only.** The signed digest covers the whole file except the
  `/Contents` hex; any later edit invalidates it. Multi-signer = successive incremental updates,
  each preserving prior signatures.
- Never export private keys unnecessarily — prefer `SecKeyCreateSignature`.
- Existing `.pdfold` / `SignaturePlacement` data must still decode (back-compat).
- `swift build` and the full `swift test` suite must stay green at each integration point.

---

## Module A — SigningIdentity  (files: `PDFold/Signing/Identity/`)
Unified identity yielding leaf cert, chain (leaf→issuers), and a signing primitive.
```
protocol SigningIdentity {
    var certificate: Certificate { get }       // swift-certificates X.509
    var chain: [Certificate] { get }
    var signatureAlgorithm: SignatureAlgorithm { get }  // RSA-PKCS1-SHA256 or ECDSA-P256-SHA256
    func sign(_ data: Data) throws -> Data      // via SecKeyCreateSignature
}
```
Providers: (1) `.p12`/`.pfx` via `SecPKCS12Import` (passphrase prompt); (2) Keychain identities via
`SecItemCopyMatching(kSecClassIdentity)`; (3) self-signed generation (swift-certificates builder +
swift-crypto), stored in Keychain, labelled "self-signed (identity not independently trusted)".

## Cost & trust model — and the in-app certificate guide
pdFold and everything it bundles are 100% free and open source. The signing *capability* costs
nothing. The only thing that can cost money is an optional **CA-issued Digital ID**, and that is a
third-party purchase external to the app — this is inherent to PKI (no software can grant trust).
The UI must communicate this clearly and professionally so self-signed's "identity not verified"
state reads as expected, not as a bug.

- **Self-signed / Keychain** → free. Adobe shows *"Signed and all signatures are valid"* but
  *"identity not verified / not trusted"* until the recipient trusts the cert once. Fine for
  internal, personal, or test use.
- **CA-issued (AATL) Digital ID** → the only way recipients see a trusted ✅ author automatically.
  Costs roughly **US $180–600 / year** depending on provider and validation level. AATL = Adobe
  Approved Trust List; an AATL cert is what makes Acrobat/Reader trust the signature out of the box.

**In-app surface (owned by Module F):** next to the "Import .p12 / CA-issued Digital ID" picker
option, render an `ⓘ` button opening a `.popover` with the SHORT copy below and a "How to get one"
disclosure that expands the step guide. A "Learn more…" link opens the bundled `CERTIFICATE_GUIDE.md`
(ship it as a resource and render in a sheet, or open externally). Keep all copy verbatim from the
guide so it stays accurate.

> **Short popover copy (verbatim):**
> *"Signing in pdFold is free. A signature made with a self-signed or Keychain ID is valid and
> tamper-evident, but recipients will see 'identity not verified' until they trust it once. To have
> Adobe Acrobat/Reader trust your identity automatically, you need a CA-issued Digital ID from a
> trusted provider (an 'AATL' certificate). These are a paid third-party product (~US $180–600/yr).
> pdFold never charges for signing — you buy the certificate directly from the provider, then import
> the `.p12` file here."*

The full acquisition steps + provider links live in `CERTIFICATE_GUIDE.md` at the repo root — bundle
that file and keep the two in sync. Do NOT hardcode a different set of links in Swift; load/echo the
guide so there is a single source of truth.

## Module B — CMSSignatureBuilder  (files: `PDFold/Signing/CMS/`)
Hand-build a **detached CMS SignedData** (RFC 5652) as DER with swift-asn1 + swift-certificates.
Signed attributes MUST include: `content-type` (id-data), `message-digest` = SHA-256 of the
ByteRange bytes, `signing-time`, and **ESS `signing-certificate-v2` (id-aa-signingCertificateV2)** —
the last makes it valid PAdES and must be present before signing. Sign the DER SET OF signed
attributes via `SigningIdentity.sign`. Embed the full chain. Then optionally attach the RFC-3161
timestamp token as the **unsigned** attribute `id-aa-timeStampToken` → PAdES **B-T**.
```
func buildCMS(byteRangeBytes: Data, identity: SigningIdentity, timestamp: TimeStampToken?) throws -> Data // DER
```
Fallback flag to emit `adbe.pkcs7.detached` if strict CAdES attributes can't be finished — but PAdES
is the goal; if you fall back, STOP and report the tradeoff rather than shipping it silently.

## Module C — TimestampClient  (files: `PDFold/Signing/Timestamp/`)
RFC-3161. Build TimeStampReq over SHA-256 of the SignerInfo signature value, POST to a configurable
TSA URL (default a free TSA, e.g. `https://freetsa.org/tsr`; user-overridable). Parse TimeStampResp,
validate status, extract the TimeStampToken. On failure, allow graceful fallback to B-B (no timestamp)
with a visible warning — never block/crash.
```
func fetchTimestamp(for signatureValue: Data, tsaURL: URL) async throws -> TimeStampToken
```

## Module D — PDFIncrementalSigner  ⚠ HIGHEST RISK — byte-exact  (files: `PDFold/Signing/PDF/`)
Contracts already stubbed: `SignatureByteRange`, `PDFByteRangeCalculator`, `SignatureFieldSpec`,
`PDFAppearanceStream`, `PDFSigner` / `PDFIncrementalSigner`.

### Byte-exact algorithm (this is where signing lives or dies)
1. Start from the final flattened PDF bytes `P` (the export output).
2. **Append an incremental update** (never rewrite a byte of `P`): new objects for AcroForm
   (`/SigFlags 3`), a signature field + widget annotation on `field.pageIndex` whose `/AP /N` is the
   appearance XObject, and the signature dictionary:
   `<< /Type /Sig /Filter /Adobe.PPKLite /SubFilter /ETSI.CAdES.detached
       /ByteRange [0000000000 0000000000 0000000000 0000000000]
       /Contents <0000…(≥ 32768 hex zeros)…0000>
       /M (D:YYYYMMDDHHmmSS'ZZ') /Name (...) /Reason (...) /Location (...) /ContactInfo (...) >>`
   The catalog is updated (new object) to reference the AcroForm; emit a correct incremental xref
   section (or xref stream if `P` uses one) with `/Prev` and a fresh `startxref`.
3. **ByteRange** (see `SignatureByteRange`): `a=0`; `b` = byte offset of the `<` opening the
   `/Contents` value; `c` = offset of the first byte AFTER the closing `>`; `d` = EOF − c. The
   excluded gap is exactly the `<…>` value **including both brackets**. Write the four ints into the
   fixed-width `/ByteRange` placeholder **in place** — same total width, so no downstream byte shifts.
   (`PDFByteRangeCalculator.writeByteRange`).
4. **Digest input** = `P_signed[a ..< a+b] ‖ P_signed[c ..< c+d]` (`digestInput`). SHA-256 this;
   hand it to Module B via the `cms` callback. `PDFIncrementalSigner.sign` calls
   `cms(byteRangeBytes)` — ordering matters: ByteRange and placeholder must be laid out BEFORE
   building the CMS, and the CMS is built over the digest of those exact bytes.
5. **Splice** the returned DER: hex-encode, write into the `/Contents` placeholder, zero-pad the
   remainder (`fillContents`). Throw `.contentsPlaceholderTooSmall` if it doesn't fit. No other byte
   changes.
6. **Multi-signer**: signing an already-signed PDF is another incremental update appended to the
   whole current file; prior `/Sig` objects and their ByteRanges remain byte-identical.

Off-by-one in steps 3–5 is the #1 real-world signing bug — the tests in
`PDFByteRangeCalculatorTests` pin it exactly. Reference algorithm: Apache PDFBox `CreateSignature`
and node `@signpdf`.

## Module E — SignatureAppearance + export-survival baking  (files: `PDFold/Signing/Appearance/`)
One renderer, two outputs, so visual + crypto look identical.
- Render Typed name (embed/subset a SIL-OFL or otherwise FOSS handwriting font) and Initials into
  (a) a PDF Form XObject (`/AP /N`) for crypto widgets and (b) a "bake into page content" path.
- **Fix the export-survival bug.** Today `WorkspaceViewModel.placeSignature` sets a stamp image via
  `ann.setValue(image, forAnnotationKey: .widgetValue)` (display-only) and
  `WorkspaceDocument.exportedPDFData` re-decodes MEMBER bytes and concatenates — so the placement is
  lost on export. Implement `SignatureExportBaker.bake(placements:into:pageIndexForPlacement:)` to
  draw each placement into real page content, and wire it into the export/flatten path so a placed
  signature survives export → reopen. Test: `SignatureExportSurvivalTests`.

## Module F — UI + Model + Integration
Files: `PDFold/Views/SignaturePalette.swift`, `PDFold/Models/SignaturePlacement.swift`,
`PDFold/ViewModels/WorkspaceViewModel.swift`, `PDFold/Document/WorkspaceDocument.swift`,
`PDFold/Views/InspectorView.swift`, `Package.swift`.
- Extend `SignaturePlacement` with `kind` (`.visualTyped` / `.visualInitials` / `.cryptographic`),
  optional signer identity ref, reason, location, contactInfo, subFilter, timestamp-applied flag.
  Keep Codable + back-compat decode.
- Rework `SignaturePalette`: **Type** and **Initials** tabs with live preview; a "Digital Signature
  (certificate)" flow with a picker for Import .p12 / Choose Keychain ID / Generate self-signed;
  Reason/Location fields; TSA on/off toggle. **Remove all freehand-draw code** (`SignatureCanvas`,
  `SignatureDrawingView`, the draw button, and the stub alert).
- **Cost/trust affordance:** next to the CA-issued option, an `ⓘ` popover (short copy from the
  "Cost & trust model" section) with a "How to get one" disclosure and a "Learn more…" that opens the
  bundled `CERTIFICATE_GUIDE.md`. Next to the self-signed option, a one-line caption: *"Free — but
  recipients see 'identity not verified' until they trust it once."* Bundle `CERTIFICATE_GUIDE.md`
  as a resource (declare it in `Package.swift`) so it ships with the app.
- Placement UX: place appearance (reuse `.signature` tool), drag/resize, then "Add" (visual) or
  "Sign & Export…" (crypto, terminal — runs on final flattened bytes via `WorkspaceDocument`).
- After a doc has a crypto signature, any further edit shows a clear "this invalidates existing
  signatures" warning.
- Add the three Apache-2.0 packages to `Package.swift`.

## Module G — Verification (runs last)
- Make the whole `swift test` suite green, including `PDFSigningTests.swift`. Add tests for
  self-signed generate→sign→verify, TSA-offline fallback, wrong-passphrase, large/linearized/
  xref-stream/encrypted PDFs.
- External validation (paste exact output into `VERIFICATION.md`):
  `pdfsig signed.pdf` reports a valid signature; `openssl asn1parse` / `openssl cms -verify` on the
  extracted `/Contents`; open in macOS Preview and Adobe Reader and confirm the signature panel shows
  the appearance + validity.
- Note intentional scope: **B-T only, no LTV** (OCSP/CRL embedding) in this pass.

## Definition of done
`swift build` green; full `swift test` green; a self-signed round-trip verifies in `pdfsig`; a
`.p12`-signed PDF shows valid in Adobe/Preview; a placed visual signature survives export → reopen;
freehand draw removed; `VERIFICATION.md` written with real command output.
