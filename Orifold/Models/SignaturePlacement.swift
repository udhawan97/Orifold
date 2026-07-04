import Foundation

struct SignaturePlacement: Codable, Identifiable {
    enum Kind: String, Codable {
        case visualTyped
        case visualInitials
        case cryptographic
    }

    var id: UUID = UUID()
    var pageRefId: UUID
    var imageData: Data
    var rect: CGRect
    var kind: Kind
    var signerName: String?
    var signedAt: Date?
    var signerIdentityRef: String?
    var reason: String?
    var location: String?
    var contactInfo: String?
    var subFilter: String?
    var timestampApplied: Bool

    enum CodingKeys: String, CodingKey {
        case id, pageRefId, imageData, rect, kind, signerName, signedAt
        case signerIdentityRef, reason, location, contactInfo, subFilter, timestampApplied
    }

    init(id: UUID = UUID(),
         pageRefId: UUID,
         imageData: Data,
         rect: CGRect,
         kind: Kind = .visualTyped,
         signerName: String? = nil,
         signedAt: Date? = nil,
         signerIdentityRef: String? = nil,
         reason: String? = nil,
         location: String? = nil,
         contactInfo: String? = nil,
         subFilter: String? = nil,
         timestampApplied: Bool = false) {
        self.id = id
        self.pageRefId = pageRefId
        self.imageData = imageData
        self.rect = rect
        self.kind = kind
        self.signerName = signerName
        self.signedAt = signedAt
        self.signerIdentityRef = signerIdentityRef
        self.reason = reason
        self.location = location
        self.contactInfo = contactInfo
        self.subFilter = subFilter
        self.timestampApplied = timestampApplied
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        pageRefId = try c.decode(UUID.self, forKey: .pageRefId)
        imageData = try c.decode(Data.self, forKey: .imageData)
        let rd = try c.decode([String: Double].self, forKey: .rect)
        rect = CGRect(x: rd["x"] ?? 0, y: rd["y"] ?? 0, width: rd["width"] ?? 0, height: rd["height"] ?? 0)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .visualTyped
        signerName = try c.decodeIfPresent(String.self, forKey: .signerName)
        signedAt = try c.decodeIfPresent(Date.self, forKey: .signedAt)
        signerIdentityRef = try c.decodeIfPresent(String.self, forKey: .signerIdentityRef)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        location = try c.decodeIfPresent(String.self, forKey: .location)
        contactInfo = try c.decodeIfPresent(String.self, forKey: .contactInfo)
        subFilter = try c.decodeIfPresent(String.self, forKey: .subFilter)
        timestampApplied = try c.decodeIfPresent(Bool.self, forKey: .timestampApplied) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(pageRefId, forKey: .pageRefId)
        try c.encode(imageData, forKey: .imageData)
        try c.encode(["x": rect.origin.x, "y": rect.origin.y, "width": rect.size.width, "height": rect.size.height], forKey: .rect)
        try c.encode(kind, forKey: .kind)
        try c.encodeIfPresent(signerName, forKey: .signerName)
        try c.encodeIfPresent(signedAt, forKey: .signedAt)
        try c.encodeIfPresent(signerIdentityRef, forKey: .signerIdentityRef)
        try c.encodeIfPresent(reason, forKey: .reason)
        try c.encodeIfPresent(location, forKey: .location)
        try c.encodeIfPresent(contactInfo, forKey: .contactInfo)
        try c.encodeIfPresent(subFilter, forKey: .subFilter)
        try c.encode(timestampApplied, forKey: .timestampApplied)
    }
}

extension SignaturePlacement {
    var isCryptographic: Bool { kind == .cryptographic }
}
