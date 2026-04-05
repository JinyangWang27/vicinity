import Foundation
import SwiftData

@Model
class Message {
    var id: UUID
    var text: String
    var senderName: String
    var isOutgoing: Bool
    var timestamp: Date
    var peerID: String  // MCPeerID.displayName

    init(id: UUID = UUID(),
         text: String,
         senderName: String,
         isOutgoing: Bool,
         timestamp: Date = Date(),
         peerID: String) {
        self.id = id
        self.text = text
        self.senderName = senderName
        self.isOutgoing = isOutgoing
        self.timestamp = timestamp
        self.peerID = peerID
    }
}
