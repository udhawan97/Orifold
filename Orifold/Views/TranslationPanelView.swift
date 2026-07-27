import AppKit
import SwiftUI

#if canImport(Translation)
import Translation
#endif

struct TranslationPanelView: View {
    let request: TranslationRequestText

    var body: some View {
        if #available(macOS 15.0, *) {
            AvailableTranslationPanel(request: request)
        } else {
            ContentUnavailableView(
                L10n.string("translation.unavailable.title"),
                systemImage: "character.book.closed",
                description: Text(L10n.string("translation.unavailable.message"))
            )
            .frame(width: 560, height: 360)
        }
    }
}

#if canImport(Translation)
@available(macOS 15.0, *)
private struct AppleTextTranslator: TextTranslating {
    let session: TranslationSession

    func translate(_ chunks: [String]) async throws -> [String] {
        let requests = chunks.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        let responses = try await session.translations(from: requests)
        let indexed = Dictionary(
            uniqueKeysWithValues: responses.compactMap { response in
                response.clientIdentifier.map { ($0, response.targetText) }
            }
        )
        return requests.enumerated().compactMap { index, request in
            indexed[request.clientIdentifier ?? String(index)]
        }
    }
}

@available(macOS 15.0, *)
private struct AvailableTranslationPanel: View {
    private struct TargetLanguage: Identifiable {
        let id: String
    }

    private static let targets = [
        TargetLanguage(id: "en"),
        TargetLanguage(id: "es"),
        TargetLanguage(id: "fr"),
        TargetLanguage(id: "hi"),
        TargetLanguage(id: "ja"),
        TargetLanguage(id: "zh-Hans")
    ]

    let request: TranslationRequestText
    @State private var model: TranslationPanelModel
    @State private var configuration: TranslationSession.Configuration?
    @State private var targetIdentifier: String
    @State private var isShowingDisclosure = false
    @AppStorage("Orifold.hasSeenTranslationDisclosure") private var hasSeenDisclosure = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    init(request: TranslationRequestText) {
        self.request = request
        _model = State(initialValue: TranslationPanelModel(request: request))
        let preferred = Locale.current.language.languageCode?.identifier
        _targetIdentifier = State(initialValue: preferred == "en" ? "es" : "en")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            translationColumns
            Divider()
            footer
        }
        .frame(minWidth: 760, idealWidth: 860, minHeight: 500, idealHeight: 580)
        .background(Color.dsSurface)
        .onAppear {
            if hasSeenDisclosure {
                beginTranslation()
            } else {
                isShowingDisclosure = true
            }
        }
        .onChange(of: targetIdentifier) { _, _ in
            guard hasSeenDisclosure else { return }
            beginTranslation()
        }
        .sheet(isPresented: $isShowingDisclosure, onDismiss: {
            if !hasSeenDisclosure {
                dismiss()
            }
        }) {
            TranslationDisclosureView(
                onContinue: {
                    hasSeenDisclosure = true
                    isShowingDisclosure = false
                    DispatchQueue.main.async { beginTranslation() }
                },
                onCancel: {
                    isShowingDisclosure = false
                }
            )
            .environment(\.locale, locale)
        }
        .translationTask(configuration) { session in
            await model.translate(using: AppleTextTranslator(session: session))
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "character.book.closed.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.dsAccent)
                .frame(width: 38, height: 38)
                .background(Color.dsAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string("translation.title"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string(request.sourceKind == .selection
                    ? "translation.source.selection"
                    : "translation.source.page"))
                    .font(.system(size: 12))
                    .foregroundStyle(Color.dsTextSecondary)
            }

            Spacer()

            Picker(L10n.string("translation.target.label"), selection: $targetIdentifier) {
                ForEach(Self.targets) { target in
                    Text(languageName(for: target.id)).tag(target.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 190)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var translationColumns: some View {
        HStack(spacing: 0) {
            textColumn(
                title: L10n.string("translation.original.title"),
                text: request.source,
                placeholder: nil
            )

            Divider()

            textColumn(
                title: L10n.string("translation.result.title"),
                text: model.translatedText,
                placeholder: resultPlaceholder
            )
        }
    }

    private func textColumn(title: String, text: String, placeholder: AnyView?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.dsTextSecondary)
                .textCase(.uppercase)

            if text.isEmpty, let placeholder {
                placeholder
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(Color.dsTextPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.bottom, 12)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var resultPlaceholder: AnyView {
        if model.isTranslating {
            return AnyView(
                VStack(spacing: 10) {
                    ProgressView()
                    Text(L10n.string("translation.progress"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsTextSecondary)
                }
            )
        }
        if model.errorMessage != nil {
            return AnyView(
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(Color.orange)
                    Text(L10n.string("translation.error"))
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsTextSecondary)
                        .multilineTextAlignment(.center)
                    Button(L10n.string("update.action.tryAgain")) {
                        beginTranslation()
                    }
                }
                .padding(28)
            )
        }
        return AnyView(
            Text(L10n.string("translation.ready"))
                .font(.system(size: 13))
                .foregroundStyle(Color.dsTextSecondary)
        )
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(L10n.string("translation.readOnly"), systemImage: "lock")
                .font(.system(size: 11))
                .foregroundStyle(Color.dsTextSecondary)

            Spacer()

            Button(L10n.string("barcode.result.copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.translatedText, forType: .string)
            }
            .disabled(model.translatedText.isEmpty)

            Button(L10n.string("contentView.done.button")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func beginTranslation() {
        let target = Locale.Language(identifier: targetIdentifier)
        if configuration?.target == target {
            configuration?.invalidate()
        } else {
            configuration = TranslationSession.Configuration(source: nil, target: target)
        }
    }

    private func languageName(for identifier: String) -> String {
        Locale(identifier: locale.identifier).localizedString(forIdentifier: identifier)
            ?? identifier
    }
}
#endif

private struct TranslationDisclosureView: View {
    let onContinue: () -> Void
    let onCancel: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "character.book.closed.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Color.dsAccent)
                Text(L10n.string("translation.disclosure.title"))
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Color.dsTextPrimary)
            }

            Text(L10n.string("translation.disclosure.message"))
                .font(.system(size: 13))
                .foregroundStyle(Color.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                disclosurePoint("checkmark.shield", "translation.disclosure.private")
                disclosurePoint("arrow.down.circle", "translation.disclosure.download")
                disclosurePoint("doc.badge.ellipsis", "translation.disclosure.readOnly")
            }

            HStack {
                Spacer()
                Button(L10n.string("signAlert.cancel.button"), role: .cancel, action: onCancel)
                Button(L10n.string("translation.disclosure.continue"), action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 470)
    }

    private func disclosurePoint(_ systemImage: String, _ key: String) -> some View {
        Label {
            Text(L10n.string(forKey: key, locale: locale))
                .font(.system(size: 13))
                .foregroundStyle(Color.dsTextPrimary)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(Color.dsAccent)
        }
    }
}
