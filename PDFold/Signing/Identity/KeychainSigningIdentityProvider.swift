import Foundation
import Security

enum KeychainSigningIdentityProvider {
    static func identities() throws -> [SecuritySigningIdentity] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw SigningIdentityError.securityStatus(operation: "SecItemCopyMatching identities", status: status)
        }

        guard let result else {
            return []
        }

        if CFGetTypeID(result) == SecIdentityGetTypeID() {
            let identity = unsafeBitCast(result, to: SecIdentity.self)
            return [try SecuritySigningIdentity(secIdentity: identity)]
        }

        guard CFGetTypeID(result) == CFArrayGetTypeID() else {
            return []
        }

        let identityArray = unsafeBitCast(result, to: CFArray.self)
        let identities = (0..<CFArrayGetCount(identityArray)).compactMap { index -> SecIdentity? in
            guard let value = CFArrayGetValueAtIndex(identityArray, index) else { return nil }
            return unsafeBitCast(value, to: SecIdentity.self)
        }

        return try identities.map { try SecuritySigningIdentity(secIdentity: $0) }
    }

    static func identity(matchingCommonName commonName: String) throws -> SecuritySigningIdentity? {
        try identities().first { $0.commonName == commonName }
    }

    static func identity(matchingCertificateData certificateData: Data) throws -> SecuritySigningIdentity? {
        try identities().first {
            SecCertificateCopyData($0.secCertificate) as Data == certificateData
        }
    }
}
