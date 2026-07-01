# Getting a Digital ID for Signing PDFs

pdFold is free and open source, and **signing costs you nothing**. This guide is only for people
who want their signature to show a **trusted, verified identity automatically** in Adobe Acrobat and
Reader. That requires a certificate issued by a trusted Certificate Authority (CA) — a paid,
third-party product. You buy it directly from the provider; pdFold never charges for signing.

---

## Which option is right for you?

| You want to… | Use | Cost | What recipients see |
|---|---|---|---|
| Sign for yourself, a team, or testing | **Self-signed** (generate in pdFold) | Free | "Valid, but identity not verified" until they trust it once |
| Use an ID already on your Mac | **Keychain Digital ID** | Free | Depends on that ID's issuer |
| Have Adobe trust your identity automatically | **CA-issued (AATL) Digital ID** | ~US $180–600 / yr | "Signed and valid — identity verified" ✅ |

**AATL** = the *Adobe Approved Trust List*. A certificate from an AATL provider is what makes
Acrobat/Reader trust your signature out of the box, with no manual step for the recipient. In the
EU, a **qualified certificate (eIDAS QES)** from a national Trust List provider gives the highest
legal standing.

---

## Free & self-signed (no purchase)

1. In pdFold's **Signatures** panel, choose **Digital Signature → Generate self-signed ID**.
2. Enter your name/email and a password to protect the key. pdFold stores it in your macOS Keychain.
3. Sign as normal. The signature is cryptographically valid and tamper-evident.
4. To make it show as *trusted* on another machine, the recipient adds your certificate to their
   trusted identities once (Acrobat → *Manage Trusted Certificates*). This is the free way to get a
   green check without paying a CA.

> A free self-signed ID is genuinely secure — it proves the document wasn't altered after signing.
> It just can't prove *who you are* to a stranger, because no independent authority vouches for it.

---

## Getting a CA-issued (AATL) Digital ID — step by step

1. **Pick a provider** (see list below) and choose a **Document Signing** / **Individual** or
   **Organization** certificate. "Document Signing" is the product you want — not an SSL/TLS or
   code-signing certificate.
2. **Complete identity validation.** The CA verifies who you are (ID documents for an individual, or
   business records for an organization). This can take from a few hours to a few days.
3. **Receive your Digital ID.** Providers deliver it either as a downloadable **`.p12` / `.pfx`
   file** (with a password) or on a **hardware USB token** (common for EU qualified certificates).
   - If it's a **`.p12`/`.pfx` file**: you can import it straight into pdFold.
   - If it's a **hardware token**: install the vendor's driver, then add the ID to your macOS
     Keychain; pdFold will list it under **Choose Keychain Digital ID**.
4. **Import into pdFold:** Signatures panel → **Digital Signature → Import .p12 Digital ID**, choose
   the file, enter its password.
5. **Sign & Export.** Place your signature appearance on the page, then **Sign & Export…**. pdFold
   embeds a PAdES B-T signature (with a trusted timestamp) into the PDF.
6. **Verify:** open the exported PDF in Adobe Reader — the signature panel should show
   *"Signed and all signatures are valid"* with your verified identity.

---

## Trusted providers (Document Signing / AATL)

Pricing and product names change — check each provider's current "Document Signing" page.

- **SSL.com — Document Signing** — often the most affordable AATL option.
  https://www.ssl.com/certificates/document-signing/
- **Certum (Asseco) — Electronic Signature / Document Signing** — popular, low-cost, EU-based.
  https://www.certum.eu/en/data-security/electronic-signature/
- **GlobalSign — Digital Signatures / AATL** —
  https://www.globalsign.com/en/digital-signatures
- **Sectigo — Document Signing** —
  https://www.sectigo.com/ssl-certificates-tls/document-signing
- **DigiCert — Document Signing** —
  https://www.digicert.com/document-signing/
- **Entrust — Document Signing Certificates** —
  https://www.entrust.com/digital-security/certificate-solutions/products/digital-signing

**Reference — how Adobe trust works (AATL):**
https://helpx.adobe.com/acrobat/kb/approved-trust-list2.html

**EU / eIDAS qualified providers (national Trusted Lists browser):**
https://eidas.ec.europa.eu/efda/tl-browser/

---

## FAQ

**Do I have to pay to sign?** No. Signing in pdFold is always free. You only pay if you choose a
CA-issued certificate for automatic third-party trust.

**Is a self-signed signature "real"?** Yes — it's a real cryptographic PAdES signature and is
tamper-evident. It simply isn't backed by an independent identity check.

**Is a free email (S/MIME) certificate enough?** Some CAs offer free personal S/MIME certificates.
They can technically sign a PDF, but they are usually **not** on Adobe's AATL, so Acrobat will still
show "identity not verified" — similar to self-signed. For automatic trust you need a Document
Signing / AATL certificate.

**Does the timestamp cost anything?** No. pdFold uses a free public RFC-3161 timestamp authority so
your signing time is provable, at no cost.

**Is my private key safe?** Yes. Keys stay in your macOS Keychain and signing happens locally on
your Mac. Nothing is uploaded except the optional timestamp request (which contains only a hash, not
your document).
