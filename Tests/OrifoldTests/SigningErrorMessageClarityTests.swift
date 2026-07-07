import XCTest
@testable import Orifold

/// Regression coverage for a real, empirically-confirmed bug found during the
/// exception-handling audit: `SigningIdentityError`, `SignatureAppearanceError`,
/// `CMSSignatureBuilderError`, and `SigningError` were plain `Error` enums that did NOT
/// conform to `LocalizedError`. Every generic catch site in the signing flow (e.g.
/// WorkspaceViewModel's "Orifold couldn't sign the PDF. \(error.localizedDescription)")
/// calls `.localizedDescription` on the caught `Error` -- and for a type that doesn't
/// conform to `LocalizedError`, Swift/Foundation's default `Error` -> `NSError` bridging
/// produces a USELESS generic string ("The operation couldn't be completed. (Orifold.
/// SigningIdentityError error 0.)") that hides every case's real message, including
/// cases that already had carefully-written, plain-English text nobody could ever see.
/// Confirmed via a throwaway XCTest probe before fixing: `.localizedDescription` printed
/// the generic Cocoa string while the type's own `description` property had the real one.
final class SigningErrorMessageClarityTests: XCTestCase {
    /// Every case must produce a message that is NOT the generic Cocoa fallback shape
    /// ("couldn't be completed" / the bare type+case-index string), proving
    /// `.localizedDescription` actually reaches this type's own message.
    private func assertNotGenericFallback(_ error: Error, file: StaticString = #filePath, line: UInt = #line) {
        let message = error.localizedDescription
        XCTAssertFalse(message.isEmpty, "empty error message", file: file, line: line)
        XCTAssertFalse(
            message.contains("couldn’t be completed") || message.contains("couldn't be completed"),
            "localizedDescription fell back to the generic Cocoa bridging string instead of this type's own message: '\(message)'",
            file: file,
            line: line
        )
    }

    func testSigningIdentityErrorSurfacesRealMessageThroughLocalizedDescription() {
        assertNotGenericFallback(SigningIdentityError.missingCertificate)
        assertNotGenericFallback(SigningIdentityError.missingPrivateKey)
        assertNotGenericFallback(SigningIdentityError.invalidPKCS12)
        assertNotGenericFallback(SigningIdentityError.noIdentityInPKCS12)
        assertNotGenericFallback(SigningIdentityError.selfSignedCertificateCreationFailed)
        assertNotGenericFallback(SigningIdentityError.securityStatus(operation: "SecPKCS12Import", status: errSecPkcs12VerifyFailure))
        assertNotGenericFallback(SigningIdentityError.securityStatus(operation: "SecItemCopyMatching", status: errSecItemNotFound))
    }

    /// A wrong PKCS#12 passphrase must read as "that password isn't correct," not a raw
    /// OSStatus code like "-25264" -- the single most common real-world signing failure a
    /// casual user hits, and the worst possible place to show a bare status code.
    func testWrongPKCS12PasswordReadsAsPlainEnglishNotRawOSStatus() {
        let message = SigningIdentityError.securityStatus(operation: "SecPKCS12Import", status: errSecPkcs12VerifyFailure).localizedDescription
        XCTAssertFalse(message.contains("\(errSecPkcs12VerifyFailure)"), "should not show the raw OSStatus code: '\(message)'")
        XCTAssertTrue(message.localizedCaseInsensitiveContains("password"), "should mention the password: '\(message)'")
    }

    func testSignatureAppearanceErrorSurfacesRealMessageThroughLocalizedDescription() {
        assertNotGenericFallback(SignatureAppearanceError.emptyText)
        assertNotGenericFallback(SignatureAppearanceError.invalidSize)
        assertNotGenericFallback(SignatureAppearanceError.imageEncodingFailed)
        assertNotGenericFallback(SignatureAppearanceError.invalidImageData)
    }

    func testCMSSignatureBuilderErrorSurfacesRealMessageThroughLocalizedDescription() {
        assertNotGenericFallback(CMSSignatureBuilderError.emptyCertificate)
        assertNotGenericFallback(CMSSignatureBuilderError.malformedDER)
        assertNotGenericFallback(CMSSignatureBuilderError.malformedCertificate)
        assertNotGenericFallback(CMSSignatureBuilderError.invalidObjectIdentifier("1.2.3"))
    }

    /// These four `SigningError` cases fall through every explicit `case` match at the
    /// "could not sign the PDF" catch site in WorkspaceViewModel into its `default:`
    /// branch -- meaning they are the cases MOST exposed to the generic-fallback bug, and
    /// two of them (`.identityExpired`, `.timestampUnavailable`) are realistic, not
    /// obscure: an expired certificate or an unreachable timestamp server are ordinary
    /// real-world signing failures.
    func testSigningErrorUnmatchedCasesSurfaceRealMessageThroughLocalizedDescription() {
        assertNotGenericFallback(SigningError.invalidPDF)
        assertNotGenericFallback(SigningError.contentsPlaceholderNotFound)
        assertNotGenericFallback(SigningError.timestampUnavailable)
        assertNotGenericFallback(SigningError.identityExpired)
    }

    func testExpiredCertificateMessageMentionsExpiry() {
        let message = SigningError.identityExpired.localizedDescription
        XCTAssertTrue(message.localizedCaseInsensitiveContains("expired"), "should mention expiry: '\(message)'")
    }
}
