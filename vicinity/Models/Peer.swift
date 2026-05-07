import Foundation
import MultipeerConnectivity

/// Represents a discovered nearby peer and its current connection state.
struct Peer: Identifiable, Equatable, Hashable {
    let peerID: MCPeerID
    var state: MCSessionState
    var uuid: String?                // populated after handshake
    var resolvedDisplayName: String? // display name received via handshake

    /// Stable identifier preferring the device UUID once the handshake has run.
    /// Pre-handshake we fall back to the MCPeerID display name — two devices that share
    /// a display name will still collide here, but only until handshake completes.
    var id: String { uuid ?? peerID.displayName }

    var displayName: String { peerID.displayName }

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
