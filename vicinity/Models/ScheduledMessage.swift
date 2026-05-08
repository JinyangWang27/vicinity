import Foundation
import SwiftData

enum ScheduledMessageStatus: String, Codable {
    case pending
    /// Transient state set just before a send attempt. Prevents a synchronously-fired
    /// second handshake from re-fetching the same row as still-pending.
    case sending
    case sent
    case cancelled
}

@Model
class ScheduledMessage {
    @Attribute(.unique) var id: UUID
    var targetPeerUUID: String
    var text: String
    var createdAt: Date
    var status: ScheduledMessageStatus
    var sentAt: Date?
    /// Stable wire identifier reused on retry so the receiver can dedupe even when we
    /// re-send across reconnects. Generated lazily by ScheduledMessageService on the
    /// first send attempt.
    var wireID: UUID?

    init(targetPeerUUID: String, text: String) {
        self.id = UUID()
        self.targetPeerUUID = targetPeerUUID
        self.text = text
        self.createdAt = Date()
        self.status = .pending
        self.sentAt = nil
        self.wireID = nil
    }
}
