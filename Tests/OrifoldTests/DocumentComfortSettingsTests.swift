import XCTest
@testable import Orifold

final class DocumentComfortSettingsTests: XCTestCase {
    func testAppAppearanceModeMapsToExpectedColorSchemes() {
        XCTAssertNil(AppAppearanceMode.system.colorScheme)
        XCTAssertEqual(AppAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(AppAppearanceMode.dark.colorScheme, .dark)
    }

    func testDocumentComfortSettingsClampPersistedValuesIntoSupportedRange() {
        var settings = DocumentComfortSettings()
        settings.brightness = 10
        settings.contrast = 999
        settings.warmth = -40
        let clamped = settings.clamped

        XCTAssertEqual(clamped.brightness, 50)
        XCTAssertEqual(clamped.contrast, 150)
        XCTAssertEqual(clamped.warmth, 0)
    }

    func testDefaultSettingsAreAtDefault() {
        XCTAssertTrue(DocumentComfortSettings.default.isAtDefault)
    }

    func testNonDefaultSettingsAreNotAtDefault() {
        var settings = DocumentComfortSettings.default
        settings.brightness = 80
        XCTAssertFalse(settings.isAtDefault)
    }

    func testPageModeColorSchemesMatchExpectedAppearance() {
        XCTAssertNil(PageMode.defaultMode.colorScheme)
        XCTAssertEqual(PageMode.light.colorScheme, .light)
        XCTAssertEqual(PageMode.sepia.colorScheme, .light)
        XCTAssertEqual(PageMode.dark.colorScheme, .dark)
        XCTAssertEqual(PageMode.dim.colorScheme, .dark)
        XCTAssertEqual(PageMode.highContrast.colorScheme, .dark)
    }

    func testDimmerBrightnessProducesStrongerToneOverlay() {
        var brighter = DocumentComfortSettings.default
        brighter.brightness = 100
        var dimmer = DocumentComfortSettings.default
        dimmer.brightness = 60

        XCTAssertGreaterThan(dimmer.toneOverlayColor.alphaComponent, brighter.toneOverlayColor.alphaComponent)
    }

    func testAboveDefaultBrightnessProducesBrightenOverlay() {
        var settings = DocumentComfortSettings.default
        settings.brightness = 130
        XCTAssertGreaterThan(settings.brightenOverlayColor.alphaComponent, 0)

        var defaultSettings = DocumentComfortSettings.default
        defaultSettings.brightness = 100
        XCTAssertEqual(defaultSettings.brightenOverlayColor, .clear)
    }

    func testHighContrastPageModeProducesFullDesaturation() {
        var settings = DocumentComfortSettings.default
        settings.pageMode = .highContrast
        XCTAssertEqual(settings.desaturationOverlayColor.alphaComponent, 1, accuracy: 0.001)
    }

    func testDocumentComfortSettingsRoundTripsThroughJSON() throws {
        var settings = DocumentComfortSettings.default
        settings.pageMode = .sepia
        settings.brightness = 82
        settings.reduceGlare = true
        settings.focusMode = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(DocumentComfortSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
    }
}
