# Digital Signature — Verification (Module G)

Status: **crypto pipeline and app integration verified** with real external tools. The app's
"Sign & Export" path now resolves a concrete signing identity, calls the same
`PDFIncrementalSigner` → `CMSSignatureBuilder` pipeline used by this harness, and keeps the
fail-closed `missingIdentity` behavior when no identity has been resolved.

## Environment
- macOS (Darwin), `swift build` / `swift test` (no Xcode).
- `openssl` 3.6.2; `pdfsig` (poppler) 26.06.0 (installed via `brew install poppler`).

## How this was produced (reproducible, no paid certificate)
A self-signed signer was generated with OpenSSL (free — the "identity not verified" path), packaged
as PKCS#12, and fed through the SAME component pipeline the app's Sign & Export must call
(`PKCS12SigningIdentityProvider` → `PDFIncrementalSigner` → `CMSSignatureBuilder`) via the gated
test `Tests/PDFoldTests/SigningVerificationHarness.swift`.

```
# 1. self-signed signer cert + key, packaged as .p12 (no CA, no cost)
openssl req -x509 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes \
  -subj "/CN=pdFold Test Signer/O=pdFold/C=US" \
  -addext "keyUsage=critical,digitalSignature,nonRepudiation"
openssl pkcs12 -export -inkey key.pem -in cert.pem -out id.p12 -passout pass:test -legacy \
  -name "pdFold Test Signer"

# 2. sign a sample PDF through the real pipeline
PDFOLD_P12_PATH=id.p12 PDFOLD_P12_PASS=test PDFOLD_SIGN_OUT=signed.pdf \
  swift test --filter SigningVerificationHarness
# -> wrote signed PDF: signed.pdf (34266 bytes)

# Optional PAdES B-T run: request a RFC-3161 token over the CMS signature value before SignerInfo
# is finalized. PDFOLD_TSA_URL can override the default https://freetsa.org/tsr endpoint.
PDFOLD_P12_PATH=id.p12 PDFOLD_P12_PASS=test PDFOLD_SIGN_OUT=signed-bt.pdf \
  PDFOLD_SIGN_TIMESTAMP=1 swift test --filter SigningVerificationHarness
# -> wrote signed PDF: signed-bt.pdf (34266 bytes)

# 3. validate
pdfsig signed.pdf
pdfsig signed.pdf -dump           # -> signed.pdf.sig0 (raw CMS)
openssl asn1parse -inform DER -in signed.pdf.sig0
```

## Result 1 — `pdfsig signed.pdf`
```
Digital Signature Info of: signed.pdf
Signature #1:
  - Signature Field Name: Signature 9
  - Signer Certificate Common Name: pdFold Test Signer
  - Signer full Distinguished Name: C=US,O=pdFold,CN=pdFold Test Signer
  - Signing Time: Jul 01 2026 07:07:15
  - Signing Hash Algorithm: SHA-256
  - Signature Type: ETSI.CAdES.detached
  - Signed Ranges: [0 - 1219], [33989 - 34266]
  - Total document signed
  - Signature Validation: Signature is Valid.
  - Certificate Validation: Certificate issuer is unknown.
```
Reading:
- **Signature is Valid** + **Total document signed** → the ByteRange/incremental-update writer and
  the digest are byte-correct.
- **Signature Type: ETSI.CAdES.detached** → real PAdES, not legacy CMS.
- **Certificate issuer is unknown** → EXPECTED for a self-signed ID. This is the "valid, identity
  not verified" state; a CA-issued (AATL) cert or a one-time manual trust removes it. See
  `CERTIFICATE_GUIDE.md`.
- The `NSS_Init failed: ... bad database` line is poppler's empty trust store, not a signature
  error — it does not affect cryptographic validity.

## Result 2 — `openssl asn1parse` of the embedded CMS
Confirms a well-formed `pkcs7-signedData` with SHA-256 and, critically, the required signed
attributes for PAdES:
```
30:  OBJECT :sha256
43:  OBJECT :pkcs7-data                     (eContentType — detached)
95:  OBJECT :sha256WithRSAEncryption        (signature algorithm)
1047: OBJECT :contentType
1073: OBJECT :signingTime
1103: OBJECT :messageDigest
1153: OBJECT :id-smime-aa-signingCertificateV2   <-- ESS signing-certificate-v2 (makes it valid PAdES)
```
Signer certificate is embedded (`subject = issuer = CN=pdFold Test Signer` — self-signed as
expected).

## Result 3 — PAdES B-T timestamp run
The same harness was rerun with `PDFOLD_SIGN_TIMESTAMP=1`, which drives the app-equivalent callback:
```swift
try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity) { signatureValue in
    try Self.fetchTimestampSynchronously(for: signatureValue, tsaURL: tsaURL).cmsTimeStampToken
}
```

`pdfsig signed-bt.pdf`:
```
NSS_Init failed: security library: bad database.
Digital Signature Info of: tmp/signing-v4/signed-bt.pdf
Signature #1:
  - Signature Field Name: Signature 9
  - Signer Certificate Common Name: pdFold Test Signer
  - Signer full Distinguished Name: C=US,O=pdFold,CN=pdFold Test Signer
  - Signing Time: Jul 01 2026 07:16:38
  - Signing Hash Algorithm: SHA-256
  - Signature Type: ETSI.CAdES.detached
  - Signed Ranges: [0 - 1219], [33989 - 34266]
  - Total document signed
  - Signature Validation: Signature is Valid.
  - Certificate Validation: Certificate issuer is unknown.
```

`pdfsig signed-bt.pdf -dump` plus `openssl asn1parse -inform DER -in signed-bt.pdf.sig0` confirms
the timestamp unsigned attribute and embedded RFC-3161 token:
```
137: 1581:d=7  hl=2 l=  11 prim: OBJECT            :id-smime-aa-timeStampToken
140: 1602:d=9  hl=2 l=   9 prim: OBJECT            :pkcs7-signedData
149: 1645:d=12 hl=2 l=  11 prim: OBJECT            :id-smime-ct-TSTInfo
```

## Unit tests
`swift build` and full `swift test` are green — **78 tests, 0 failures**, including the 8 byte-exact
signing acceptance tests in `PDFSigningTests.swift` (ByteRange/Contents splicing, append-only
incremental update, multi-signer preservation, export-survival). The opt-in
`SigningVerificationHarness` remains skipped in the normal suite unless the `PDFOLD_*` environment
variables are supplied.

## Remaining external scope
- **Adobe Acrobat/Reader** visual confirmation not captured in this headless environment; `pdfsig`
  is the authoritative CLI validator used here.
- **No LTV** (OCSP/CRL) — intentionally out of scope for this pass.

## App integration status
`WorkspaceViewModel.signAndExportCryptographicPDF` no longer hardcodes `SigningError.missingIdentity`.
Module F now resolves Import .p12, Choose Keychain ID, and Generate self-signed into concrete
`SigningIdentity` instances, stores the resolved identity for the placement session, and uses:
```swift
try CMSSignatureBuilder.buildCMS(byteRangeBytes: byteRangeBytes, identity: identity)
```

When the timestamp toggle is on, pdFold requests a `CMSTimeStampToken` via `TimestampClient` over
the CMS signature value, passes it into the CMS builder before `SignerInfo` is finalized, and embeds
it as PAdES B-T. If the TSA is unavailable, export continues as PAdES B-B and surfaces a visible
warning. If no identity was resolved, signing still fails closed with `SigningError.missingIdentity`.
