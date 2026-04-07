import Foundation
import SwiftData

enum ScheduledMessageStatus: String, Codable {
    case pending
    case sent
    case cancelled
}

@Model
class ScheduledMessage {
    var id: UUID
    var targetPeerUUID: String
    var text: String
    var createdAt: Date
    var status: ScheduledMessageStatus
    var sentAt: Date?

    init(targetPeerUUID: String, text: String) {
        self.id = UUID()
        self.targetPeerUUID = targetPeerUUID
        self.text = text
        self.createdAt = Date()
        self.status = .pending
        self.sentAt = nil
    }
}
