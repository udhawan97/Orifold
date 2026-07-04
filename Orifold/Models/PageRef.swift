import Foundation

struct PageRef: Codable, Identifiable {
    var id: UUID = UUID()
    var memberDocId: UUID
    var sourcePageIndex: Int
    var rotation: Int = 0
    var cropBox: CGRect? = nil

    enum CodingKeys: String, CodingKey {
        case id, memberDocId, sourcePageIndex, rotation, cropBox
    }

    init(id: UUID = UUID(), memberDocId: UUID, sourcePageIndex: Int, rotation: Int = 0, cropBox: CGRect? = nil) {
        self.id = id
        self.memberDocId = memberDocId
        self.sourcePageIndex = sourcePageIndex
        self.rotation = rotation
        self.cropBox = cropBox
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        memberDocId = try c.decode(UUID.self, forKey: .memberDocId)
        sourcePageIndex = try c.decode(Int.self, forKey: .sourcePageIndex)
        rotation = try c.decode(Int.self, forKey: .rotation)
        if let rectDict = try c.decodeIfPresent([String: Double].self, forKey: .cropBox) {
            cropBox = CGRect(
                x: rectDict["x"] ?? 0, y: rectDict["y"] ?? 0,
                width: rectDict["width"] ?? 0, height: rectDict["height"] ?? 0
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(memberDocId, forKey: .memberDocId)
        try c.encode(sourcePageIndex, forKey: .sourcePageIndex)
        try c.encode(rotation, forKey: .rotation)
        if let r = cropBox {
            try c.encode(["x": r.origin.x, "y": r.origin.y, "width": r.size.width, "height": r.size.height], forKey: .cropBox)
        }
    }
}
