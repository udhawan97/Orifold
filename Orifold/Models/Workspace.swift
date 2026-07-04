import Foundation

enum WorkspaceCommentTextSize: String, Codable, CaseIterable, Identifiable {
    case small
    case regular
    case large

    var id: String { rawValue }
}

struct WorkspaceCommentStyle: Codable, Equatable {
    var isBold: Bool = false
    var isItalic: Bool = false
    var textSize: WorkspaceCommentTextSize = .regular
    var colorHex: String = "#1F2933"

    enum CodingKeys: String, CodingKey {
        case isBold, isItalic, textSize, colorHex
    }

    init(isBold: Bool = false,
         isItalic: Bool = false,
         textSize: WorkspaceCommentTextSize = .regular,
         colorHex: String = "#1F2933") {
        self.isBold = isBold
        self.isItalic = isItalic
        self.textSize = textSize
        self.colorHex = colorHex
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? false
        isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        textSize = try c.decodeIfPresent(WorkspaceCommentTextSize.self, forKey: .textSize) ?? .regular
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#1F2933"
    }
}

enum WorkspaceCommentAnchorKind: String, Codable {
    case text
    case region
}

struct WorkspaceCommentAnchor: Codable, Equatable {
    var pageRefID: UUID
    var rect: CGRect
    var kind: WorkspaceCommentAnchorKind
    var snippet: String?

    enum CodingKeys: String, CodingKey {
        case pageRefID, rect, kind, snippet
    }

    init(pageRefID: UUID,
         rect: CGRect,
         kind: WorkspaceCommentAnchorKind,
         snippet: String? = nil) {
        self.pageRefID = pageRefID
        self.rect = rect
        self.kind = kind
        self.snippet = snippet
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pageRefID = try c.decode(UUID.self, forKey: .pageRefID)
        rect = try c.decode(CGRect.self, forKey: .rect)
        kind = try c.decodeIfPresent(WorkspaceCommentAnchorKind.self, forKey: .kind) ?? .text
        snippet = try c.decodeIfPresent(String.self, forKey: .snippet)
    }
}

struct WorkspaceComment: Codable, Identifiable {
    var id: UUID = UUID()
    var body: String
    var createdAt: Date = Date()
    var style: WorkspaceCommentStyle = WorkspaceCommentStyle()
    var tags: [String] = []
    var anchor: WorkspaceCommentAnchor?
    var anchorWasRemoved: Bool = false
    var isResolved: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, body, createdAt, style, tags, anchor, anchorWasRemoved, isResolved
    }

    init(id: UUID = UUID(),
         body: String,
         createdAt: Date = Date(),
         style: WorkspaceCommentStyle = WorkspaceCommentStyle(),
         tags: [String] = [],
         anchor: WorkspaceCommentAnchor? = nil,
         anchorWasRemoved: Bool = false,
         isResolved: Bool = false) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.style = style
        self.tags = tags
        self.anchor = anchor
        self.anchorWasRemoved = anchorWasRemoved
        self.isResolved = isResolved
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        style = try c.decodeIfPresent(WorkspaceCommentStyle.self, forKey: .style) ?? WorkspaceCommentStyle()
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        anchor = try c.decodeIfPresent(WorkspaceCommentAnchor.self, forKey: .anchor)
        anchorWasRemoved = try c.decodeIfPresent(Bool.self, forKey: .anchorWasRemoved) ?? false
        isResolved = try c.decodeIfPresent(Bool.self, forKey: .isResolved) ?? false
    }
}

struct Workspace: Codable {
    var id: UUID = UUID()
    var title: String = "Untitled Workspace"
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()
    var documents: [MemberDocument] = []
    var pageOrder: [PageRef] = []
    var signatures: [SignaturePlacement] = []
    var decorations: [PageDecoration] = []
    var tags: [String] = []
    var comments: [WorkspaceComment] = []
    var pageEditStates: [PageEditState] = []
    var schemaVersion: Int = 5

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, documents, pageOrder, signatures, decorations, tags, comments, pageEditStates, schemaVersion
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled Workspace"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        modifiedAt = try c.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        documents = try c.decodeIfPresent([MemberDocument].self, forKey: .documents) ?? []
        pageOrder = try c.decodeIfPresent([PageRef].self, forKey: .pageOrder) ?? []
        signatures = try c.decodeIfPresent([SignaturePlacement].self, forKey: .signatures) ?? []
        decorations = try c.decodeIfPresent([PageDecoration].self, forKey: .decorations) ?? []
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        comments = try c.decodeIfPresent([WorkspaceComment].self, forKey: .comments) ?? []
        pageEditStates = try c.decodeIfPresent([PageEditState].self, forKey: .pageEditStates) ?? []
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}

extension Workspace {
    var hasActiveDecorations: Bool {
        decorations.contains(where: \.isEnabled)
    }
}
