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

struct WorkspaceComment: Codable, Identifiable {
    var id: UUID = UUID()
    var body: String
    var createdAt: Date = Date()
    var style: WorkspaceCommentStyle = WorkspaceCommentStyle()
    var tags: [String] = []

    enum CodingKeys: String, CodingKey {
        case id, body, createdAt, style, tags
    }

    init(id: UUID = UUID(),
         body: String,
         createdAt: Date = Date(),
         style: WorkspaceCommentStyle = WorkspaceCommentStyle(),
         tags: [String] = []) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.style = style
        self.tags = tags
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        style = try c.decodeIfPresent(WorkspaceCommentStyle.self, forKey: .style) ?? WorkspaceCommentStyle()
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
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
    var tags: [String] = []
    var comments: [WorkspaceComment] = []
    var pageEditStates: [PageEditState] = []
    var schemaVersion: Int = 3

    enum CodingKeys: String, CodingKey {
        case id, title, createdAt, modifiedAt, documents, pageOrder, signatures, tags, comments, pageEditStates, schemaVersion
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
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        comments = try c.decodeIfPresent([WorkspaceComment].self, forKey: .comments) ?? []
        pageEditStates = try c.decodeIfPresent([PageEditState].self, forKey: .pageEditStates) ?? []
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
    }
}
