import Foundation
import Security
import Observation

enum CertificateProfileError: Error, Equatable, LocalizedError {
    case identityNotFoundInKeychain
    case couldNotPersistToKeychain(OSStatus)

    // Without this, `error.localizedDescription` falls back to a generic, unhelpful
    // "The operation couldn't be completed" message wherever this error surfaces (e.g. when
    // a profile's Keychain identity was removed independently — via Keychain Access, or a
    // Keychain sync — after the profile itself was registered).
    var errorDescription: String? {
        switch self {
        case .identityNotFoundInKeychain:
            return L10n.string("error.certificateProfile.identityNotFoundInKeychain")
        case .couldNotPersistToKeychain:
            return L10n.string("error.certificateProfile.couldNotPersistToKeychain")
        }
    }
}

/// Persistent registry of signing identities (self-signed, imported `.p12`/`.pfx`, or Keychain
/// references), so a signing identity is created/imported ONCE and reused thereafter — see
/// `DigitalCertificateProfile`'s header comment for why this matters. Metadata lives in a small
/// JSON file under Application Support (matching `RecentsStore`'s pattern); the private key
/// never leaves the macOS Keychain, addressed only by a persistent reference.
@MainActor @Observable final class CertificateProfileStore {
    static let shared = CertificateProfileStore()

    private(set) var profiles: [DigitalCertificateProfile] = []

    private let storeURL: URL
    private let keychain: SecKeychain?

    init(storeURL: URL? = nil, keychain: SecKeychain? = nil) {
        self.keychain = keychain
        if let storeURL {
            self.storeURL = storeURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            let root = support.appendingPathComponent("Orifold", isDirectory: true)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            self.storeURL = root.appendingPathComponent("certificate-profiles.json")
        }
        profiles = Self.load(from: self.storeURL)
    }

    // MARK: - CRUD

    /// Persists `identity` as a reusable profile. If an identity with the same certificate
    /// fingerprint is already registered (e.g. re-importing the same `.p12`), the existing
    /// profile's label/source are refreshed in place rather than creating a duplicate.
    @discardableResult
    func register(identity: SecuritySigningIdentity, label: String, source: DigitalCertificateProfile.Source) throws -> DigitalCertificateProfile {
        let profile = try upsertedProfile(for: identity, label: label, source: source)
        persist()
        return profile
    }

    /// Registers several identities as profiles in one pass, writing the JSON store exactly
    /// once at the end rather than once per identity (each `register` call would otherwise
    /// re-encode and rewrite the whole, monotonically growing profiles array on every
    /// iteration — wasted work when only the state after the last write matters).
    @discardableResult
    func registerAll(
        identities: [SecuritySigningIdentity],
        label: (SecuritySigningIdentity) -> String,
        source: DigitalCertificateProfile.Source
    ) throws -> [DigitalCertificateProfile] {
        let registered = try identities.map { identity in
            try upsertedProfile(for: identity, label: label(identity), source: source)
        }
        persist()
        return registered
    }

    /// Inserts or updates `profiles` in place for `identity` (by fingerprint match) without
    /// persisting — callers persist once after all their upserts are done.
    private func upsertedProfile(
        for identity: SecuritySigningIdentity,
        label: String,
        source: DigitalCertificateProfile.Source
    ) throws -> DigitalCertificateProfile {
        let persistentRef = try Self.persistentReference(for: identity.secIdentity, keychain: keychain)
        let fingerprint = try DigitalCertificateProfile.fingerprint(for: identity)
        let existingIndex = profiles.firstIndex { $0.sha256Fingerprint == fingerprint }
        let profile = try DigitalCertificateProfile(
            id: existingIndex.map { profiles[$0].id } ?? UUID(),
            identity: identity,
            label: label,
            source: source,
            keychainPersistentRef: persistentRef,
            createdAt: existingIndex.map { profiles[$0].createdAt } ?? Date()
        )

        if let existingIndex {
            profiles[existingIndex] = profile
        } else {
            profiles.append(profile)
        }
        return profile
    }

    func remove(id: UUID) {
        guard let profile = profiles.first(where: { $0.id == id }) else { return }
        // Keychain item first, THEN persist the profile removal — if the app is killed
        // between these two steps, the worst case is a stale profile entry pointing at an
        // already-deleted Keychain item (harmless, still visible, still deletable again),
        // rather than the reverse: an orphaned Keychain identity with no profile entry
        // left to ever find or remove it through.
        Self.deleteKeychainItem(persistentRef: profile.keychainPersistentRef, keychain: keychain)
        profiles.removeAll { $0.id == id }
        persist()
    }

    func resolveIdentity(for profile: DigitalCertificateProfile) throws -> SecuritySigningIdentity {
        try Self.identity(forPersistentRef: profile.keychainPersistentRef, keychain: keychain)
    }

    // MARK: - Keychain plumbing

    static func persistentReference(for secIdentity: SecIdentity, keychain: SecKeychain? = nil) throws -> Data {
        var query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchItemList as String: [secIdentity],
            kSecReturnPersistentRef as String: true
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw CertificateProfileError.couldNotPersistToKeychain(status)
        }
        return data
    }

    static func identity(forPersistentRef persistentRef: Data, keychain: SecKeychain? = nil) throws -> SecuritySigningIdentity {
        // macOS resolves persistent references through an item list, not kSecValuePersistentRef.
        var query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchItemList as String: [persistentRef],
            kSecReturnRef as String: true
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let result, CFGetTypeID(result) == SecIdentityGetTypeID() else {
            throw CertificateProfileError.identityNotFoundInKeychain
        }
        let secIdentity = unsafeBitCast(result, to: SecIdentity.self)
        return try SecuritySigningIdentity(secIdentity: secIdentity)
    }

    static func deleteKeychainItem(persistentRef: Data, keychain: SecKeychain? = nil) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchItemList as String: [persistentRef]
        ]
        if let keychain {
            query[kSecMatchSearchList as String] = [keychain]
        }
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Persistence

    /// Written synchronously (unlike the fire-and-forget pattern `RecentsStore` uses for its
    /// thumbnail cache): losing an unflushed write here means losing track of a Keychain
    /// identity's metadata entirely — a correctness issue, not just a stale recents list — and
    /// the file is tiny, so the cost is negligible.
    private func persist() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }

    private static func load(from url: URL) -> [DigitalCertificateProfile] {
        guard let data = FileManager.default.contents(atPath: url.path),
              let decoded = try? JSONDecoder().decode([DigitalCertificateProfile].self, from: data) else { return [] }
        return decoded
    }
}
