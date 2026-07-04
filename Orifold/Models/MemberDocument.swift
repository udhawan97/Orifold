import Foundation

struct MemberDocument: Codable, Identifiable {
    var id: UUID = UUID()
    var displayName: String
    var sourcePDFRef: String
    var pageRefs: [UUID] = []
}
