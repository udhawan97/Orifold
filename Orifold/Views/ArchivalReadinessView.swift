import SwiftUI

/// A checklist of archival-readiness *hints* for the active document.
///
/// Deliberately never renders an aggregate verdict. Real PDF/A validation is hundreds of
/// clauses and this is a handful of cheap catalog probes, so the panel shows one row per
/// signal and says outright that it is not validation. Any future change that adds a
/// summary "PASS" badge, or the words valid/compliant/validated, breaks that promise.
struct ArchivalReadinessView: View {
    var viewModel: WorkspaceViewModel
    @Environment(\.dismiss) private var dismiss
    // Read so SwiftUI re-invokes `body` when the app language changes.
    @Environment(\.locale) private var locale

    @State private var readiness: ArchivalReadiness?
    @State private var isEvaluating = true

    private struct Row: Identifiable {
        let id: String
        let titleKey: String
        let passes: Bool
    }

    private func rows(for readiness: ArchivalReadiness) -> [Row] {
        [
            Row(id: "encryption", titleKey: "archival.row.encryption", passes: !readiness.isEncrypted),
            Row(id: "activeContent",
                titleKey: "archival.row.activeContent",
                passes: !readiness.hasActiveContent),
            Row(id: "fonts", titleKey: "archival.row.fontsEmbedded", passes: readiness.allFontsEmbedded),
            Row(id: "outputIntent",
                titleKey: "archival.row.outputIntent",
                passes: readiness.hasOutputIntent),
            Row(id: "xmp", titleKey: "archival.row.xmp", passes: readiness.hasXMPMetadata),
            Row(id: "tagged", titleKey: "archival.row.tagged", passes: readiness.isTagged)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .dsMD) {
            VStack(alignment: .leading, spacing: .dsXS) {
                Text(L10n.string("archival.title", locale: locale))
                    .font(.system(size: 16, weight: .semibold, design: .serif))
                    .foregroundStyle(Color.dsTextPrimary)
                Text(L10n.string("archival.subtitle", locale: locale))
                    .font(.dsCaption())
                    .foregroundStyle(Color.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Rectangle().fill(Color.dsSeparator).frame(height: 0.5)

            if isEvaluating {
                HStack(spacing: .dsSM) {
                    ProgressView().controlSize(.small)
                    Text(L10n.string("archival.evaluating", locale: locale))
                        .font(.dsBody())
                        .foregroundStyle(Color.dsTextSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else if let readiness {
                VStack(alignment: .leading, spacing: .dsSM) {
                    ForEach(rows(for: readiness)) { row in
                        HStack(spacing: .dsSM) {
                            Image(systemName: row.passes ? "checkmark.seal" : "exclamationmark.triangle")
                                .foregroundStyle(row.passes ? Color.dsSuccessAccent : Color.dsWarningAccent)
                                .frame(width: 16)
                            Text(L10n.string(forKey: row.titleKey, locale: locale))
                                .font(.dsBody())
                                .foregroundStyle(Color.dsTextPrimary)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                Text(L10n.string("archival.unavailable", locale: locale))
                    .font(.dsBody())
                    .foregroundStyle(Color.dsTextSecondary)
            }

            HStack {
                Spacer()
                Button(L10n.string("archival.done", locale: locale)) { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.dsXL)
        .frame(width: 420)
        .background(Color.dsSurface)
        .task { await evaluate() }
    }

    /// The font walk crosses every page, so it runs off the main actor — on a large
    /// document it is long enough to drop frames if evaluated inline.
    private func evaluate() async {
        let data = viewModel.activeMemberDataForArchivalReadiness()
        guard let data else {
            readiness = nil
            isEvaluating = false
            return
        }
        let evaluated = await Task.detached { ArchivalReadinessService.evaluate(data) }.value
        readiness = evaluated
        isEvaluating = false
    }
}
