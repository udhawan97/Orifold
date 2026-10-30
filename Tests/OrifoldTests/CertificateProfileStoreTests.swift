import Security
import XCTest
@testable import Orifold

// Regression coverage for the "self-signed regenerates a new certificate every signing"
// defect: a recipient can never learn to trust a self-signed certificate that's different
// each time they receive one. These tests pin that a registered identity is reused, not
// regenerated, across resolves and across store instances (i.e. across app launches).
@MainActor
final class CertificateProfileStoreTests: XCTestCase {
    private var signingKeychain: SecKeychain!

    override func setUpWithError() throws {
        signingKeychain = try makeDisposableSigningKeychain()
    }

    private func makeTempStore() -> CertificateProfileStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cert-profiles-\(UUID().uuidString).json")
        return CertificateProfileStore(storeURL: url, keychain: signingKeychain)
    }

    private func makeSelfSignedIdentity(commonName: String = "Test Signer") throws -> SecuritySigningIdentity {
        try SelfSignedSigningIdentityProvider.generate(
            request: SelfSignedIdentityRequest(commonName: "\(commonName) \(UUID().uuidString)"),
            keychain: signingKeychain
        )
    }

    func testRegisteringAnIdentityPersistsAcrossStoreInstances() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cert-profiles-\(UUID().uuidString).json")
        let identity = try makeSelfSignedIdentity()

        let store1 = CertificateProfileStore(storeURL: url, keychain: signingKeychain)
        let profile = try store1.register(identity: identity, label: "My self-signed ID", source: .selfSignedGenerated)
        XCTAssertEqual(store1.profiles.count, 1)

        // A fresh store instance loading from the same file must see the same profile — this
        // is what makes "create once, reuse forever" actually work across app launches.
        let store2 = CertificateProfileStore(storeURL: url, keychain: signingKeychain)
        XCTAssertEqual(store2.profiles.map(\.id), [profile.id])
        XCTAssertEqual(store2.profiles.first?.sha256Fingerprint, profile.sha256Fingerprint)
        let reloadedProfile = try XCTUnwrap(store2.profiles.first)
        let reloadedIdentity = try store2.resolveIdentity(for: reloadedProfile)
        XCTAssertEqual(reloadedIdentity.certificate, identity.certificate)
        let payload = Data("reloaded signing profile".utf8)
        let signature = try reloadedIdentity.sign(payload)
        let publicKey = try XCTUnwrap(SecCertificateCopyKey(identity.secCertificate))
        XCTAssertTrue(SecKeyVerifySignature(publicKey, .ecdsaSignatureMessageX962SHA256,
                                           payload as CFData, signature as CFData, nil))

        try? FileManager.default.removeItem(at: url)
    }

    func testResolvingAProfileReturnsTheSameCertificateEveryTime() throws {
        let store = makeTempStore()
        let identity = try makeSelfSignedIdentity()
        let profile = try store.register(identity: identity, label: "Reusable ID", source: .selfSignedGenerated)
        let resolvedOnce = try store.resolveIdentity(for: profile)
        let resolvedTwice = try store.resolveIdentity(for: profile)

        // The whole point of persistence: two signings using this profile must use the exact
        // same certificate (same serial), not a freshly generated one each time.
        XCTAssertEqual(resolvedOnce.certificate, identity.certificate)
        XCTAssertEqual(resolvedTwice.certificate, identity.certificate)

        store.remove(id: profile.id)
    }

    func testReRegisteringTheSameCertificateUpdatesInPlaceInsteadOfDuplicating() throws {
        let store = makeTempStore()
        let identity = try makeSelfSignedIdentity()
        let first = try store.register(identity: identity, label: "Original label", source: .selfSignedGenerated)
        let second = try store.register(identity: identity, label: "Renamed", source: .selfSignedGenerated)

        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.profiles.first?.label, "Renamed")

        store.remove(id: second.id)
    }

    func testRemovingAProfileDeletesTheKeychainEntryAndTheProfile() throws {
        let store = makeTempStore()
        let identity = try makeSelfSignedIdentity()
        let profile = try store.register(identity: identity, label: "To delete", source: .selfSignedGenerated)
        XCTAssertEqual(try store.resolveIdentity(for: profile).certificate, identity.certificate)

        store.remove(id: profile.id)

        XCTAssertTrue(store.profiles.isEmpty)
        XCTAssertThrowsError(try store.resolveIdentity(for: profile)) { error in
            XCTAssertEqual(error as? CertificateProfileError, .identityNotFoundInKeychain)
        }
    }

    func testProfileMetadataReflectsTheCertificate() throws {
        let store = makeTempStore()
        let identity = try makeSelfSignedIdentity(commonName: "Ada Lovelace")
        let profile = try store.register(identity: identity, label: "Ada's ID", source: .selfSignedGenerated)

        XCTAssertTrue(profile.subjectCommonName.hasPrefix("Ada Lovelace"))
        XCTAssertTrue(profile.isSelfSigned)
        XCTAssertFalse(profile.isExpired)
        XCTAssertFalse(profile.sha256Fingerprint.isEmpty)

        store.remove(id: profile.id)
    }
}
