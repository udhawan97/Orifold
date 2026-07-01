import Foundation
import Security

enum PKCS12SigningIdentityProvider {
    typealias PassphraseProvider = () throws -> String

    static func importIdentity(from url: URL, passphraseProvider: PassphraseProvider) throws -> SecuritySigningIdentity {
        let data = try Data(contentsOf: url)
        return try importIdentity(from: data, passphrase: passphraseProvider())
    }

    static func importIdentity(from data: Data, passphrase: String) throws -> SecuritySigningIdentity {
        let identities = try importIdentities(from: data, passphrase: passphrase)
        guard let identity = identities.first else {
            throw SigningIdentityError.noIdentityInPKCS12
        }
        return identity
    }

    static func importIdentities(from data: Data, passphrase: String) throws -> [SecuritySigningIdentity] {
        let options = [kSecImportExportPassphrase as String: passphrase] as CFDictionary
        var importedItems: CFArray?
        let status = SecPKCS12Import(data as CFData, options, &importedItems)
        guard status == errSecSuccess else {
            throw SigningIdentityError.securityStatus(operation: "SecPKCS12Import", status: status)
        }

        guard let items = importedItems as? [[String: Any]] else {
            throw SigningIdentityError.invalidPKCS12
        }

        let identities = try items.compactMap { item -> SecuritySigningIdentity? in
            guard let secIdentity = secIdentity(from: item[kSecImportItemIdentity as String]) else {
                return nil
            }

            let chain = certificateChain(from: item)
            return try SecuritySigningIdentity(secIdentity: secIdentity, secCertificateChain: chain)
        }

        guard !identities.isEmpty else {
            throw SigningIdentityError.noIdentityInPKCS12
        }

        return identities
    }

    private static func certificateChain(from item: [String: Any]) -> [SecCertificate] {
        if let certificates = certificates(from: item[kSecImportItemCertChain as String]), !certificates.isEmpty {
            return certificates
        }

        if let trust = secTrust(from: item[kSecImportItemTrust as String]) {
            return certificates(from: SecTrustCopyCertificateChain(trust)) ?? []
        }

        return []
    }

    private static func secIdentity(from value: Any?) -> SecIdentity? {
        guard let value else { return nil }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == SecIdentityGetTypeID() else { return nil }
        return unsafeBitCast(cfValue, to: SecIdentity.self)
    }

    private static func secTrust(from value: Any?) -> SecTrust? {
        guard let value else { return nil }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == SecTrustGetTypeID() else { return nil }
        return unsafeBitCast(cfValue, to: SecTrust.self)
    }

    private static func certificates(from value: Any?) -> [SecCertificate]? {
        guard let value else { return nil }
        let cfValue = value as CFTypeRef
        guard CFGetTypeID(cfValue) == CFArrayGetTypeID() else { return nil }
        let array = unsafeBitCast(cfValue, to: CFArray.self)
        return certificates(from: array)
    }

    private static func certificates(from array: CFArray) -> [SecCertificate] {
        (0..<CFArrayGetCount(array)).compactMap { index -> SecCertificate? in
            guard let value = CFArrayGetValueAtIndex(array, index) else { return nil }
            let cfValue = unsafeBitCast(value, to: CFTypeRef.self)
            guard CFGetTypeID(cfValue) == SecCertificateGetTypeID() else { return nil }
            return unsafeBitCast(value, to: SecCertificate.self)
        }
    }
}
