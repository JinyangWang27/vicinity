import Foundation
import MultipeerConnectivity

/// Represents a discovered nearby peer and its current connection state.
struct Peer: Identifiable, Equatable, Hashable {
    let id: String  // MCPeerID.displayName
    let peerID: MCPeerID
    var state: MCSessionState
    var uuid: String?               // populated after handshake
    var resolvedDisplayName: String? // display name received via handshake

    static func == (lhs: Peer, rhs: Peer) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var statusLabel: String {
        switch state {
        case .notConnected: return String(localized: "Not Connected")
        case .connecting:   return String(localized: "Connecting\u{2026}")
        case .connected:    return String(localized: "Connected")
        @unknown default:   return String(localized: "Unknown")
        }
    }

    var isConnected: Bool {
        state == .connected
    }
}
