import Foundation

struct WorkspaceComment: Codable, Identifiable {
    var id: UUID = UUID()
    var body: String
    var createdAt: Date = Date()
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
