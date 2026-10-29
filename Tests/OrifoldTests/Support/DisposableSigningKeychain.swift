import Foundation
import Security
import XCTest

extension XCTestCase {
    /// Exercises real persistent identities without creating keys in the user's login Keychain.
    func makeDisposableSigningKeychain() throws -> SecKeychain {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("Orifold-signing-test-\(UUID().uuidString).keychain-db").path
        let password = Array(UUID().uuidString.utf8)
        var keychain: SecKeychain?
        let status = password.withUnsafeBytes { bytes in
            SecKeychainCreate(path, UInt32(bytes.count), bytes.baseAddress, false, nil, &keychain)
        }
        XCTAssertEqual(status, errSecSuccess, "could not create the disposable signing Keychain")
        let created = try XCTUnwrap(keychain)
        addTeardownBlock {
            XCTAssertEqual(SecKeychainDelete(created), errSecSuccess,
                           "could not delete the disposable signing Keychain")
        }
        return created
    }
}
