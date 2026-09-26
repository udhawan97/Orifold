import XCTest
@testable import Orifold

final class BatchFoldPresetTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var store: BatchFoldPresetStore!

    override func setUp() {
        super.setUp()
        suiteName = "BatchFoldPresetTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = BatchFoldPresetStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testEveryBuiltInUsesTheSameProductionMappingAsManualControls() {
        let locale = Locale(identifier: "en")
        let manualOptions: [BatchFoldPreset: BatchFoldService.Options] = [
            .searchableCopies: BatchFoldService.Options(runsOCR: true),
            .smallerCopies: BatchFoldService.Options(compressionPreset: .balanced),
            .reviewCopies: BatchFoldService.Options(
                compressionPreset: .balanced,
                watermarkText: "Draft"
            )
        ]
        let dirtySelection = BatchFoldSelection(
            runsOCR: true,
            compressionPreset: .small,
            watermark: .custom("run only")
        )

        for preset in BatchFoldPreset.allCases {
            let applied = dirtySelection.applying(preset.configuration)
            XCTAssertEqual(applied.resolvedOptions(locale: locale), manualOptions[preset])
        }
    }

    func testStandardWatermarkResolvesWhenOptionsAreCreated() {
        let configuration = BatchFoldConfiguration(standardWatermark: .draft)

        let options = configuration.resolvedOptions(locale: Locale(identifier: "en"))

        XCTAssertEqual(options.watermarkText, "Draft")
    }

    func testSavedConfigurationRoundTripsAcrossStoreInstances() {
        let configuration = BatchFoldConfiguration(
            runsOCR: true,
            compressionPreset: .small,
            standardWatermark: .draft
        )

        XCTAssertTrue(store.save(configuration))
        XCTAssertEqual(BatchFoldPresetStore(defaults: defaults).load(), configuration)
    }

    func testSavingAgainReplacesTheSingleCustomPreset() {
        XCTAssertTrue(store.save(BatchFoldConfiguration(runsOCR: true)))
        let replacement = BatchFoldConfiguration(compressionPreset: .balanced)

        XCTAssertTrue(store.save(replacement))

        XCTAssertEqual(store.load(), replacement)
    }

    func testDeleteRemovesTheCustomPreset() {
        XCTAssertTrue(store.save(BatchFoldConfiguration(runsOCR: true)))

        store.delete()

        XCTAssertNil(store.load())
    }

    func testCorruptAndUnknownSettingsFallBackToNoPreset() throws {
        defaults.set(Data("not json".utf8), forKey: BatchFoldPresetStore.defaultsKey)
        XCTAssertNil(store.load())

        let unknown = BatchFoldConfiguration(version: 999, runsOCR: true)
        defaults.set(try JSONEncoder().encode(unknown), forKey: BatchFoldPresetStore.defaultsKey)
        XCTAssertNil(store.load())
    }

    func testEmptyConfigurationCannotReplaceASavedPreset() {
        let original = BatchFoldConfiguration(runsOCR: true)
        XCTAssertTrue(store.save(original))

        XCTAssertFalse(store.save(BatchFoldConfiguration()))

        XCTAssertEqual(store.load(), original)
    }

    func testEncodedPresetContainsExactlyTheAllowedKeys() throws {
        let configuration = BatchFoldConfiguration(
            runsOCR: true,
            compressionPreset: .balanced,
            standardWatermark: .draft
        )

        let encoded = try JSONEncoder().encode(configuration)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

        XCTAssertEqual(
            Set(object.keys),
            Set(["version", "runsOCR", "compressionPreset", "standardWatermark"])
        )
    }

    func testRunCommandKeepsAnOptionsSnapshotWhenControlsChange() throws {
        var selection = BatchFoldSelection(runsOCR: true)
        let command = try XCTUnwrap(selection.command(
            for: .chooseFolder,
            locale: Locale(identifier: "en")
        ))

        selection.runsOCR = false
        selection.compressionPreset = .small

        XCTAssertEqual(
            command,
            .chooseFolder(BatchFoldService.Options(runsOCR: true))
        )
    }

    func testSaveReplaceAndDeleteCommandsNeverRequestFolderSelection() throws {
        let selection = BatchFoldSelection(runsOCR: true)
        let locale = Locale(identifier: "en")

        let save = try XCTUnwrap(selection.command(for: .savePreset, locale: locale))
        let replace = try XCTUnwrap(selection.command(for: .savePreset, locale: locale))
        let delete = try XCTUnwrap(selection.command(for: .deletePreset, locale: locale))

        XCTAssertEqual(save, .savePreset(BatchFoldConfiguration(runsOCR: true)))
        XCTAssertEqual(replace, .savePreset(BatchFoldConfiguration(runsOCR: true)))
        XCTAssertEqual(delete, .deletePreset)
    }
}
