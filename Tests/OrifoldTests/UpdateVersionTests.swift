import XCTest
@testable import Orifold

/// The app side of the version-normalization contract shared with the release scripts
/// (`scripts/lib/version.sh`, WEBSITE_PLAN §7). If these vectors change, the shell
/// vectors must change with them — the whole point is that CI and the app agree on
/// "is A newer than B?".
final class UpdateVersionTests: XCTestCase {
    func testParsesEveryTagAndMarketingForm() {
        XCTAssertEqual(UpdateVersion(string: "0.9.0")?.description, "0.9")
        XCTAssertEqual(UpdateVersion(string: "v0.9.0")?.description, "0.9")
        XCTAssertEqual(UpdateVersion(string: "release-v0.9.0")?.description, "0.9")
        XCTAssertEqual(UpdateVersion(string: "  release-v1.2.3  ")?.description, "1.2.3")
        XCTAssertEqual(UpdateVersion(string: "V2")?.description, "2")
    }

    func testTrailingZerosAreEquivalent() {
        XCTAssertEqual(UpdateVersion(string: "0.9"), UpdateVersion(string: "0.9.0"))
        XCTAssertEqual(UpdateVersion(string: "1.0.0"), UpdateVersion(string: "1"))
    }

    func testPreReleaseAndBuildSuffixesParseToReleaseCore() {
        XCTAssertEqual(UpdateVersion(string: "0.9.0-beta.2")?.description, "0.9")
        XCTAssertEqual(UpdateVersion(string: "1.2.3+42")?.description, "1.2.3")
    }

    func testNonNumericTagsAreRejected() {
        XCTAssertNil(UpdateVersion(string: "Orifold-latest"))
        XCTAssertNil(UpdateVersion(string: "latest"))
        XCTAssertNil(UpdateVersion(string: "main"))
        XCTAssertNil(UpdateVersion(string: ""))
        XCTAssertNil(UpdateVersion(string: "v"))
    }

    func testOrderingVectors() {
        let ordered = ["0.8.4", "0.9.0", "0.10.0", "1.0.0", "1.0.1", "2.0.0"]
            .compactMap(UpdateVersion.init(string:))
        XCTAssertEqual(ordered, ordered.sorted())
        // The classic trap: 0.10 must be newer than 0.9, not older (numeric, not string).
        XCTAssertTrue(UpdateVersion(string: "0.10.0")! > UpdateVersion(string: "0.9.0")!)
        XCTAssertTrue(UpdateVersion(string: "0.9.0")! > UpdateVersion(string: "0.8.4")!)
        XCTAssertFalse(UpdateVersion(string: "0.8.4")! > UpdateVersion(string: "0.8.4")!)
    }

    func testCurrentReturnsAParseableVersionWithoutCrashing() {
        // `.current` must never fail — an absent/unparseable bundle key resolves to the
        // oldest version rather than returning nil, so callers never special-case it.
        let current = UpdateVersion.current(bundle: Bundle(for: UpdateVersionTests.self))
        XCTAssertEqual(UpdateVersion(string: current.description), current)
        XCTAssertFalse(current.components.isEmpty)
    }
}
