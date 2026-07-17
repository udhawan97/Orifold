import XCTest
@testable import Orifold

final class SpellCheckPreferenceTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SpellCheckPreference.defaultsKey)
        super.tearDown()
    }

    func testDefaultsToEnabled() {
        UserDefaults.standard.removeObject(forKey: SpellCheckPreference.defaultsKey)
        XCTAssertTrue(SpellCheckPreference.isEnabled)
    }

    func testPersistsDisabled() {
        SpellCheckPreference.isEnabled = false
        XCTAssertFalse(SpellCheckPreference.isEnabled)
        XCTAssertFalse(UserDefaults.standard.bool(forKey: SpellCheckPreference.defaultsKey))
    }

    @MainActor
    func testTextViewHonorsPreference() {
        SpellCheckPreference.isEnabled = true
        let enabled = InlineEditableTextView(frame: .zero)
        enabled.applySpellCheckPreference()
        XCTAssertTrue(enabled.isContinuousSpellCheckingEnabled)
        XCTAssertFalse(enabled.isAutomaticSpellingCorrectionEnabled)

        SpellCheckPreference.isEnabled = false
        let disabled = InlineEditableTextView(frame: .zero)
        disabled.applySpellCheckPreference()
        XCTAssertFalse(disabled.isContinuousSpellCheckingEnabled)
    }
}
