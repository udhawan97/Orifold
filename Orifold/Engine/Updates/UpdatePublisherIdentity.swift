import Foundation
import Security

/// The publisher identity that an automatic swap is allowed to inherit from the running app.
/// Ad-hoc signatures intentionally produce `nil`: a development build can still be installed
/// manually, but it must never establish the trust anchor for an unattended replacement.
struct UpdatePublisherIdentity: Equatable, Sendable {
    static let expectedBundleIdentifier = "com.ud.Orifold"

    let bundleIdentifier: String
    let teamIdentifier: String

    var isDeveloperID: Bool {
        !teamIdentifier.isEmpty
    }

    static func current(for bundleURL: URL) -> UpdatePublisherIdentity? {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)
        guard createStatus == errSecSuccess, let staticCode else { return nil }

        var signingInformation: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard infoStatus == errSecSuccess,
              let info = signingInformation as? [String: Any],
              let identifier = info[kSecCodeInfoIdentifier as String] as? String,
              let team = info[kSecCodeInfoTeamIdentifier as String] as? String,
              !team.isEmpty,
              identifier == expectedBundleIdentifier else {
            return nil
        }
        return UpdatePublisherIdentity(bundleIdentifier: identifier, teamIdentifier: team)
    }
}
