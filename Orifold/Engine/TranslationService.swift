import Foundation
import Observation

enum TranslationSourceKind: String, Equatable {
    case selection
    case currentPage
}

struct TranslationRequestText: Identifiable, Equatable {
    let id: UUID
    let sourceKind: TranslationSourceKind
    let source: String
    let chunks: [String]

    init(
        id: UUID = UUID(),
        sourceKind: TranslationSourceKind,
        source: String,
        chunks: [String]? = nil
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.source = source
        self.chunks = chunks ?? TranslationChunker.chunk(source)
    }
}

enum TranslationFeature {
    static var isAvailable: Bool {
        if #available(macOS 15.0, *) {
            return true
        }
        return false
    }
}

enum TranslationSourceResolver {
    static func request(selection: String?, currentPage: String?) -> TranslationRequestText? {
        if let selection = normalized(selection), !selection.isEmpty {
            return TranslationRequestText(sourceKind: .selection, source: selection)
        }
        if let currentPage = normalized(currentPage), !currentPage.isEmpty {
            return TranslationRequestText(sourceKind: .currentPage, source: currentPage)
        }
        return nil
    }

    private static func normalized(_ text: String?) -> String? {
        text?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum TranslationChunker {
    static let defaultMaximumCharacters = 800

    static func chunk(
        _ text: String,
        maxCharacters: Int = defaultMaximumCharacters
    ) -> [String] {
        guard maxCharacters > 0 else { return [] }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }

        var sentences: [String] = []
        normalized.enumerateSubstrings(
            in: normalized.startIndex..<normalized.endIndex,
            options: [.bySentences]
        ) { substring, _, _, _ in
            guard let sentence = substring?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !sentence.isEmpty else { return }
            sentences.append(sentence)
        }
        if sentences.isEmpty {
            sentences = [normalized]
        }

        var result: [String] = []
        var pending = ""

        func flushPending() {
            guard !pending.isEmpty else { return }
            result.append(pending)
            pending = ""
        }

        for sentence in sentences {
            if sentence.count <= maxCharacters {
                let candidate = pending.isEmpty ? sentence : "\(pending) \(sentence)"
                if candidate.count <= maxCharacters {
                    pending = candidate
                } else {
                    flushPending()
                    pending = sentence
                }
                continue
            }

            flushPending()
            for wordSlice in sentence.split(whereSeparator: \.isWhitespace) {
                let word = String(wordSlice)
                if word.count > maxCharacters {
                    flushPending()
                    var remaining = word[...]
                    while !remaining.isEmpty {
                        let end = remaining.index(
                            remaining.startIndex,
                            offsetBy: min(maxCharacters, remaining.count)
                        )
                        result.append(String(remaining[..<end]))
                        remaining = remaining[end...]
                    }
                    continue
                }

                let candidate = pending.isEmpty ? word : "\(pending) \(word)"
                if candidate.count <= maxCharacters {
                    pending = candidate
                } else {
                    flushPending()
                    pending = word
                }
            }
        }
        flushPending()
        return result
    }
}

protocol TextTranslating {
    func translate(_ chunks: [String]) async throws -> [String]
}

@MainActor
@Observable
final class TranslationPanelModel {
    let request: TranslationRequestText
    private var translator: (any TextTranslating)?

    var translatedText = ""
    var isTranslating = false
    var errorMessage: String?

    init(request: TranslationRequestText, translator: (any TextTranslating)? = nil) {
        self.request = request
        self.translator = translator
    }

    func translate(using translator: any TextTranslating) async {
        self.translator = translator
        await translate()
    }

    func translate() async {
        guard let translator else { return }
        isTranslating = true
        translatedText = ""
        errorMessage = nil
        defer { isTranslating = false }

        do {
            let translations = try await translator.translate(request.chunks)
            guard translations.count == request.chunks.count else {
                throw TranslationModelError.incompleteResponse
            }
            translatedText = translations.joined(separator: "\n\n")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum TranslationModelError: LocalizedError {
    case incompleteResponse

    var errorDescription: String? {
        "Translation returned an incomplete response."
    }
}
