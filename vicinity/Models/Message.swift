import Foundation
import SwiftData

@Model
class Message {
    @Attribute(.unique) var id: UUID
    var text: String
    var senderName: String
    var isOutgoing: Bool
    var timestamp: Date
    var peerID: String      // MCPeerID.displayName (display-name fallback)
    var peerUUID: String?   // stable device UUID, set after handshake exchange
    /// Sender-generated identifier used for receiver-side dedupe and ACK matching.
    /// Optional because legacy rows (pre-WireMessage builds) have no wireID; SQL
    /// UNIQUE allows multiple NULLs so the constraint is safe even with those rows.
    @Attribute(.unique) var wireID: UUID?
    /// Set on receipt of a delivery ACK from the peer. Lets ChatView render a
    /// double-check indicator on outgoing messages once they're confirmed received.
    var deliveredAt: Date?

    init(id: UUID = UUID(),
         text: String,
         senderName: String,
         isOutgoing: Bool,
         timestamp: Date = Date(),
         peerID: String,
         peerUUID: String? = nil,
         wireID: UUID? = nil,
         deliveredAt: Date? = nil) {
        self.id = id
        self.text = text
        self.senderName = senderName
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.peerID = peerID
        self.peerUUID = peerUUID
        self.wireID = wireID
        self.deliveredAt = deliveredAt
    }
}
