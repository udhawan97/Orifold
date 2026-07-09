import Foundation

/// A dotted-numeric app version (e.g. `0.8.4`), parsed from any of the tag/marketing
/// forms the release pipeline emits: `release-v0.9.0`, `v0.9.0`, `0.9.0`.
///
/// This is the app-side twin of the normalization the release scripts perform on tags
/// (`scripts/lib/version.sh`, WEBSITE_PLAN §7): strip a leading `release-`, strip a
/// leading `v`, then compare component-by-component as integers with missing trailing
/// components treated as `0` (so `0.9` == `0.9.0`). Keeping the semantics identical on
/// both sides is what lets "is this release newer than what I'm running?" give the same
/// answer in CI and in the app. The shared test-vector list lives in `UpdateVersionTests`.
struct UpdateVersion: Comparable, Hashable, CustomStringConvertible {
    /// The integer components, most-significant first. Never empty.
    let components: [Int]

    /// Parses a tag/marketing string, returning `nil` if — after normalization — there is
    /// no leading run of dotted integers to compare (e.g. `"latest"`, `""`, `"main"`).
    init?(string raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("release-") { s.removeFirst("release-".count) }
        if s.first == "v" || s.first == "V" { s.removeFirst() }

        // Take only the leading dotted-numeric run so a pre-release/build suffix
        // (`0.9.0-beta.2`, `0.9.0+42`) still parses to its release core. A component that
        // carries a non-digit suffix (`0-beta`) contributes its leading digits and then
        // *ends* the run — everything after it is pre-release/build metadata, not a
        // further version component.
        var parsed: [Int] = []
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            let digits = part.prefix { $0.isNumber }
            guard !digits.isEmpty, let value = Int(digits) else { break }
            parsed.append(value)
            if digits.count != part.count { break }
        }

        guard !parsed.isEmpty else { return nil }
        // Drop trailing zeros so `0.9.0` and `0.9` hash/compare equal.
        while parsed.count > 1, parsed.last == 0 { parsed.removeLast() }
        components = parsed
    }

    /// The version the running bundle reports (`CFBundleShortVersionString`), or `0`
    /// if the key is somehow absent/unparseable — an absent version is treated as the
    /// oldest possible, so "an update is available" fails safe toward *offering* it.
    static func current(bundle: Bundle = .main) -> UpdateVersion {
        let raw = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return raw.flatMap(UpdateVersion.init(string:)) ?? UpdateVersion(components: [0])
    }

    private init(components: [Int]) {
        self.components = components
    }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    var description: String { components.map(String.init).joined(separator: ".") }
}
