import SwiftUI
import SwiftData

/// Root view — shows the list of discovered nearby peers.
/// Also owns the global incoming-message persistence handler.
struct ContentView: View {
    @EnvironmentObject var multipeerSession: MultipeerSession
    @EnvironmentObject var scheduledMessageService: ScheduledMessageService
    @EnvironmentObject var proximityBluetoothService: ProximityBluetoothService
    @Environment(\.modelContext) private var modelContext

    @State private var selectedPeer: Peer?
    @State private var showSettings = false
    @State private var showKnownFriends = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showKnownFriends = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                }
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
            .sheet(isPresented: $showKnownFriends) {
                KnownFriendsView()
            }
            .navigationDestination(item: $selectedPeer) { peer in
                ChatView(peer: peer)
            }
            .onAppear {
                setupCallbacks()
            }
        }
    }

    // MARK: - Multipeer callbacks

    private func setupCallbacks() {
        // Persist incoming chat messages from any peer at the root level
        // so messages are saved regardless of which chat (if any) is open.
        multipeerSession.onMessageReceived = { text, senderName, peerIDString in
            let uuid = multipeerSession.peers.first { $0.id == peerIDString }?.uuid
            let message = Message(
                text: text,
                senderName: senderName,
                isOutgoing: false,
                peerID: peerIDString,
                peerUUID: uuid
            )
            modelContext.insert(message)
        }

        // Upsert KnownPeer and retroactively tag unlinked messages when a handshake arrives.
        // ScheduledMessageService delivery is handled via its own Combine subscription.
        multipeerSession.onHandshakeReceived = { peerID, uuid, displayName in
            upsertKnownPeer(uuid: uuid, displayName: displayName)
            retrotagMessages(peerID: peerID, uuid: uuid)
        }

        syncProximityScanTargets()
    }

    /// Syncs ProximityBluetoothService scan targets with currently pending scheduled messages.
    private func syncProximityScanTargets() {
        let pending = ScheduledMessageStatus.pending
        let all = (try? modelContext.fetch(
            FetchDescriptor<ScheduledMessage>(predicate: #Predicate { $0.status == pending })
        )) ?? []
        let uuids = Array(Set(all.map(\.targetPeerUUID)))
        proximityBluetoothService.updateScanTargets(uuids)
    }

    /// Insert or update the KnownPeer record for this UUID.
    private func upsertKnownPeer(uuid: String, displayName: String) {
        let existing = (try? modelContext.fetch(
            FetchDescriptor<KnownPeer>(predicate: #Predicate { $0.uuid == uuid })
        )) ?? []

        if let known = existing.first {
            known.displayName = displayName
            known.lastSeen = Date()
        } else {
            modelContext.insert(KnownPeer(uuid: uuid, displayName: displayName))
        }
    }

    /// Tag old messages for this peerID (display name) that were stored before UUID exchange.
    private func retrotagMessages(peerID: String, uuid: String) {
        let untagged = (try? modelContext.fetch(
            FetchDescriptor<Message>(predicate: #Predicate { $0.peerID == peerID && $0.peerUUID == nil })
        )) ?? []
        for msg in untagged { msg.peerUUID = uuid }
    }

    // MARK: - Sub-views

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
    let session = MultipeerSession()
    let schema = Schema([Message.self, KnownPeer.self, ScheduledMessage.self])
    let container = try! ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let sms = ScheduledMessageService(modelContext: container.mainContext, multipeerSession: session)
    let pbs = ProximityBluetoothService(deviceUUID: session.myDeviceUUID)
    return ContentView()
        .environmentObject(session)
        .environmentObject(sms)
        .environmentObject(pbs)
        .modelContainer(container)
}
