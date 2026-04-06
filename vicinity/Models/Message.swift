import Foundation
import SwiftData

@Model
class Message {
    var id: UUID
    var text: String
    var senderName: String
    var isOutgoing: Bool
    var timestamp: Date
    var peerID: String   // MCPeerID.displayName (display-name fallback)
    var peerUUID: String? // stable device UUID, set after handshake exchange

    init(id: UUID = UUID(),
         text: String,
         senderName: String,
         isOutgoing: Bool,
         timestamp: Date = Date(),
         peerID: String,
         peerUUID: String? = nil) {
        self.id = id
        self.text = text
        self.senderName = senderName
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.peerID = peerID
        self.peerUUID = peerUUID
    }
}
