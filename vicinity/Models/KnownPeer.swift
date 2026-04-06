import Foundation
import SwiftData

/// A peer whose identity has been confirmed via UUID handshake.
/// Persisted across sessions so returning friends are recognized automatically.
@Model
class KnownPeer {
    var uuid: String         // stable device UUID — the permanent identity key
    var displayName: String  // last known display name (may change)
    var lastSeen: Date

    init(uuid: String, displayName: String, lastSeen: Date = Date()) {
        self.uuid = uuid
        self.displayName = displayName
        self.lastSeen = lastSeen
    }
}
