import Foundation
import MultipeerConnectivity

/// Represents a discovered nearby peer and its current connection state.
struct Peer: Identifiable, Equatable {
    let id: String  // MCPeerID.displayName
    let peerID: MCPeerID
    var state: MCSessionState

    static func == (lhs: Peer, rhs: Peer) -> Bool {
        lhs.id == rhs.id
    }

    var statusLabel: String {
        switch state {
        case .notConnected: return "Not Connected"
        case .connecting:   return "Connecting…"
        case .connected:    return "Connected"
        @unknown default:   return "Unknown"
        }
    }

    var isConnected: Bool {
        state == .connected
    }
}
