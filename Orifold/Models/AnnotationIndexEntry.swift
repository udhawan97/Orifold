import Foundation

struct AnnotationIndexEntry: Codable, Identifiable {
    var id: UUID = UUID()
    var pageRefId: UUID
    var type: String
    var author: String?
    var contents: String?
    var createdAt: Date = Date()
}
