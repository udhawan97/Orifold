import CoreText
import Foundation

/// Registers the bundled substitution fonts (Liberation Sans/Serif/Mono, Carlito,
/// Caladea) with CoreText at process scope so `FontSubstitution`'s targets actually
/// resolve in the editor, and locates the bundled Adobe Core-14 AFM metrics. Owns the one
/// shared, non-trapping bundled-resource resolver reused by the font layer.
///
/// Registration runs at most once (a lazy `static let`, so it's thread-safe and
/// idempotent) and must happen before the first editor render — see
/// `OrifoldAppDelegate.applicationDidFinishLaunching`.
enum FontRegistrar {
    /// Registers every bundled `.ttf`. Idempotent: safe to call repeatedly; "already
    /// registered" (including fonts already installed system-wide) counts as success.
    static func registerBundledFonts() {
        _ = registerOnce
    }

    /// The URL of the copied `Fonts` resource directory, or `nil` if it isn't bundled in
    /// this build.
    static func fontsDirectoryURL() -> URL? {
        if let url = bundle.url(forResource: "Fonts", withExtension: nil) { return url }
        if let resourceURL = bundle.resourceURL {
            let candidate = resourceURL.appendingPathComponent("Fonts", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    /// The URL of a bundled Core-14 AFM by its PostScript resource name (`"Helvetica"`,
    /// `"Times-Roman"`), or `nil` when the metrics aren't bundled.
    static func afmURL(forResource name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "afm", subdirectory: "Fonts/AFM")
    }

    // MARK: Registration

    private static let registerOnce: Void = {
        guard let directory = fontsDirectoryURL(),
              let contents = try? FileManager.default.contentsOfDirectory(
                  at: directory, includingPropertiesForKeys: nil
              ) else { return }
        for url in contents where url.pathExtension.lowercased() == "ttf" {
            register(url)
        }
    }()

    private static func register(_ url: URL) {
        var error: Unmanaged<CFError>?
        if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) { return }
        // A false return with the "already registered" code is success (the app relaunched,
        // or the user has the font installed system-wide). Any other failure is non-fatal:
        // that one font just falls back to system resolution.
        if let cfError = error?.takeRetainedValue(),
           CFErrorGetCode(cfError) == CTFontManagerError.alreadyRegistered.rawValue {
            return
        }
    }

    // MARK: Bundled-resource resolution
    //
    // Same hand-rolled, non-trapping resolver as `SampleDocument`/`L10n`: SwiftPM's
    // `Bundle.module` traps when `Orifold_Orifold.bundle` can't be located, which would
    // turn a packaging omission into a launch crash. Degrade to `.main` instead.

    #if SWIFT_PACKAGE
    private final class BundleAnchor {}
    private static let bundle: Bundle = {
        let bundleName = "Orifold_Orifold.bundle"
        let anchor = Bundle(for: BundleAnchor.self)
        let candidates: [URL?] = [
            Bundle.main.resourceURL,
            Bundle.main.bundleURL,
            Bundle.main.executableURL?.deletingLastPathComponent(),
            Bundle.main.bundleURL.deletingLastPathComponent(),
            anchor.resourceURL,
            anchor.bundleURL,
            anchor.bundleURL.deletingLastPathComponent(),
            anchor.executableURL?.deletingLastPathComponent(),
        ]
        for base in candidates {
            guard let url = base?.appendingPathComponent(bundleName),
                  let found = Bundle(url: url) else { continue }
            return found
        }
        return .main
    }()
    #else
    private final class BundleAnchor {}
    private static let bundle = Bundle(for: BundleAnchor.self)
    #endif
}
