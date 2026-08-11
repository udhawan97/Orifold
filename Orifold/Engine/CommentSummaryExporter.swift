import Foundation

/// Renders the workspace's comments and markup as a Markdown digest — the Zotero-style
/// "export annotations" story. Pure string building: the view model gathers the items,
/// this type only formats them, so every layout rule is testable without a PDF.
enum CommentSummaryExporter {

    struct Comment: Equatable {
        var pageNumber: Int?
        var snippet: String?
        var body: String
        var tags: [String]
        var isResolved: Bool
    }

    enum HighlightKind: String {
        case highlight
        case underline
        case strikeout

        var labelKey: String { "commentExport.kind.\(rawValue)" }
    }

    struct Highlight: Equatable {
        var pageNumber: Int
        var kind: HighlightKind
        var quote: String?
    }

    static func markdown(
        workspaceTitle: String,
        comments: [Comment],
        highlights: [Highlight],
        locale: Locale? = nil
    ) -> String {
        var out = "# \(L10n.format("commentExport.title", workspaceTitle, locale: locale))\n"

        if !comments.isEmpty {
            out += "\n## \(L10n.string("commentExport.comments.header", locale: locale))\n\n"
            for comment in comments {
                var heading = "- "
                if let page = comment.pageNumber {
                    heading += "**\(L10n.format("commentExport.pageLabel", page, locale: locale))**"
                } else {
                    heading += "**\(L10n.string("commentExport.noPage", locale: locale))**"
                }
                if let snippet = comment.snippet, !snippet.isEmpty {
                    heading += " — “\(snippet)”"
                }
                if !comment.tags.isEmpty {
                    heading += " _(\(comment.tags.joined(separator: ", ")))_"
                }
                if comment.isResolved {
                    heading += " [\(L10n.string("commentExport.resolved", locale: locale))]"
                }
                out += heading + "\n"
                // Prefix every body line, including empty ones, so the blockquote
                // survives Markdown renderers that reset on a plain line.
                let quoted = comment.body
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { $0.isEmpty ? ">" : "> \($0)" }
                    .joined(separator: "\n")
                out += quoted + "\n"
            }
        }

        if !highlights.isEmpty {
            out += "\n## \(L10n.string("commentExport.highlights.header", locale: locale))\n\n"
            for highlight in highlights {
                var line = "- **\(L10n.format("commentExport.pageLabel", highlight.pageNumber, locale: locale))**"
                line += " — \(L10n.string(forKey: highlight.kind.labelKey, locale: locale))"
                if let quote = highlight.quote, !quote.isEmpty {
                    line += ": “\(quote)”"
                }
                out += line + "\n"
            }
        }

        return out
    }
}
