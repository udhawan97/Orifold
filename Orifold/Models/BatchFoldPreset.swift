import Foundation

enum BatchFoldStandardWatermark: String, Codable, Sendable {
    case draft
}

/// The deliberately small, nonsensitive subset of batch options that can be reused.
/// Source paths, output paths, document content, passwords, and custom watermark text never
/// enter this value and therefore cannot be written to UserDefaults by the preset store.
struct BatchFoldConfiguration: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var version: Int
    var runsOCR: Bool
    var compressionPreset: PDFCompressionPreset?
    var standardWatermark: BatchFoldStandardWatermark?

    init(
        version: Int = currentVersion,
        runsOCR: Bool = false,
        compressionPreset: PDFCompressionPreset? = nil,
        standardWatermark: BatchFoldStandardWatermark? = nil
    ) {
        self.version = version
        self.runsOCR = runsOCR
        self.compressionPreset = compressionPreset
        self.standardWatermark = standardWatermark
    }

    var isSupported: Bool { version == Self.currentVersion }

    var isEmpty: Bool {
        !runsOCR && compressionPreset == nil && standardWatermark == nil
    }

    func resolvedOptions(locale: Locale) -> BatchFoldService.Options {
        BatchFoldService.Options(
            compressionPreset: compressionPreset,
            runsOCR: runsOCR,
            watermarkText: standardWatermark == nil
                ? nil
                : L10n.string("decoration.defaultWatermark", locale: locale)
        )
    }
}

enum BatchFoldWatermarkChoice: Equatable, Sendable {
    case none
    case standard
    case custom(String)
}

/// The editable state behind the batch-fold controls. Keeping option resolution here gives
/// preset selection and run snapshots one production path that can be tested without opening
/// an AppKit folder panel.
struct BatchFoldSelection: Equatable, Sendable {
    var runsOCR = false
    var compressionPreset: PDFCompressionPreset?
    var watermark: BatchFoldWatermarkChoice = .none

    var persistableConfiguration: BatchFoldConfiguration {
        BatchFoldConfiguration(
            runsOCR: runsOCR,
            compressionPreset: compressionPreset,
            standardWatermark: watermark == .standard ? .draft : nil
        )
    }

    func applying(_ configuration: BatchFoldConfiguration) -> Self {
        Self(
            runsOCR: configuration.runsOCR,
            compressionPreset: configuration.compressionPreset,
            watermark: configuration.standardWatermark == nil ? .none : .standard
        )
    }

    func resolvedOptions(locale: Locale) -> BatchFoldService.Options {
        let watermarkText: String?
        switch watermark {
        case .none:
            watermarkText = nil
        case .standard:
            watermarkText = L10n.string("decoration.defaultWatermark", locale: locale)
        case .custom(let text):
            watermarkText = text
        }
        return BatchFoldService.Options(
            compressionPreset: compressionPreset,
            runsOCR: runsOCR,
            watermarkText: watermarkText
        )
    }

    func command(
        for intent: BatchFoldSheetIntent,
        locale: Locale
    ) -> BatchFoldSheetCommand? {
        switch intent {
        case .savePreset:
            let configuration = persistableConfiguration
            return configuration.isEmpty ? nil : .savePreset(configuration)
        case .deletePreset:
            return .deletePreset
        case .chooseFolder:
            let options = resolvedOptions(locale: locale)
            return options.isEmpty ? nil : .chooseFolder(options)
        }
    }
}

enum BatchFoldSheetIntent: Equatable, Sendable {
    case savePreset
    case deletePreset
    case chooseFolder
}

enum BatchFoldSheetCommand: Equatable, Sendable {
    case savePreset(BatchFoldConfiguration)
    case deletePreset
    case chooseFolder(BatchFoldService.Options)
}

enum BatchFoldPreset: String, CaseIterable, Identifiable {
    case searchableCopies
    case smallerCopies
    case reviewCopies

    var id: String { rawValue }

    var configuration: BatchFoldConfiguration {
        switch self {
        case .searchableCopies:
            return BatchFoldConfiguration(runsOCR: true)
        case .smallerCopies:
            return BatchFoldConfiguration(compressionPreset: .balanced)
        case .reviewCopies:
            return BatchFoldConfiguration(
                compressionPreset: .balanced,
                standardWatermark: .draft
            )
        }
    }

    func title(locale: Locale) -> String {
        L10n.string(forKey: "batchFold.preset.\(rawValue).title", locale: locale)
    }

    var systemImage: String {
        switch self {
        case .searchableCopies: return "text.viewfinder"
        case .smallerCopies: return "arrow.down.right.and.arrow.up.left"
        case .reviewCopies: return "doc.text.magnifyingglass"
        }
    }
}

struct BatchFoldPresetStore {
    static let defaultsKey = "orifold.batchFold.customPreset"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> BatchFoldConfiguration? {
        guard let data = defaults.data(forKey: Self.defaultsKey),
              let configuration = try? JSONDecoder().decode(BatchFoldConfiguration.self, from: data),
              configuration.isSupported,
              !configuration.isEmpty else {
            return nil
        }
        return configuration
    }

    @discardableResult
    func save(_ configuration: BatchFoldConfiguration) -> Bool {
        guard configuration.isSupported,
              !configuration.isEmpty,
              let data = try? JSONEncoder().encode(configuration) else {
            return false
        }
        defaults.set(data, forKey: Self.defaultsKey)
        return true
    }

    func delete() {
        defaults.removeObject(forKey: Self.defaultsKey)
    }
}
