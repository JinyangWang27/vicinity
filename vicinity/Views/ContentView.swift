import SwiftUI
import SwiftData

/// Root view — shows the list of discovered nearby peers.
/// Also owns the global incoming-message persistence handler.
struct ContentView: View {
    @EnvironmentObject var multipeerSession: MultipeerSession
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPeer: Peer?
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if multipeerSession.peers.isEmpty {
                    emptyStateView
                } else {
                    peerList
                }
            }
            .navigationTitle("Vicinity")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .navigationDestination(item: $selectedPeer) { peer in
                ChatView(peer: peer)
            }
            .onAppear {
                // Persist incoming messages from any peer at the root level
                // so messages are saved regardless of which chat (if any) is open.
                multipeerSession.onMessageReceived = { text, senderName, peerIDString in
                    let message = Message(
                        text: text,
                        senderName: senderName,
                        isOutgoing: false,
                        peerID: peerIDString
                    )
                    modelContext.insert(message)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("Looking for nearby devices…")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Make sure others are running Vicinity nearby.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var peerList: some View {
        List(multipeerSession.peers) { peer in
            Button {
                if !peer.isConnected {
                    multipeerSession.connect(to: peer)
                }
                selectedPeer = peer
            } label: {
                PeerRow(peer: peer)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - PeerRow

private struct PeerRow: View {
    let peer: Peer

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(peer.id)
                    .font(.body)
                Text(peer.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch peer.state {
        case .connected:    return .green
        case .connecting:   return .orange
        case .notConnected: return .gray
        @unknown default:   return .gray
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(MultipeerSession())
}

