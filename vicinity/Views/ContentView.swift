import SwiftUI
import SwiftData
import CoreBluetooth

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

    @AppStorage("storeWasReset") private var storeWasReset = false
    @AppStorage("storageUnavailable") private var storageUnavailable = false

    var body: some View {
        NavigationSplitView {
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
                    .accessibilityLabel(String(localized: "Known friends"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel(String(localized: "Settings"))
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if storageUnavailable {
                        storageUnavailableWarning
                    }
                    if storeWasReset {
                        storeResetWarning
                    }
                    diagnosticBanner
                }
            }
        } detail: {
            if let peer = selectedPeer {
                ChatView(peer: peer)
            } else {
                ContentUnavailableView(
                    "Select a peer",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Tap a nearby person to start chatting.")
                )
            }
        }
        .onChange(of: selectedPeer) { _, peer in
            if let peer, !peer.isConnected {
                multipeerSession.connect(to: peer)
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showKnownFriends) {
            KnownFriendsView()
        }
        .alert("Connection Request", isPresented: Binding(
            get: { multipeerSession.pendingInvitationPeerName != nil },
            set: { _ in }
        )) {
            Button("Accept") {
                multipeerSession.respondToInvitation(true)
            }
            Button("Decline", role: .cancel) {
                multipeerSession.respondToInvitation(false)
            }
        } message: {
            if let name = multipeerSession.pendingInvitationPeerName {
                Text("\(name) wants to chat.")
            }
        }
        .onAppear {
            scheduledMessageService.refreshScanTargets()
        }
        // Persist incoming chat messages from any peer at the root level so messages
        // are saved regardless of which chat (if any) is open. Dedupe by wireID so a
        // resent message (e.g. after a flap) doesn't create duplicate rows.
        .onReceive(multipeerSession.messagePublisher) { text, senderName, peerIDString, wireID in
            if let wireID,
               let existing = try? modelContext.fetch(
                   FetchDescriptor<Message>(predicate: #Predicate { $0.wireID == wireID })
               ),
               !existing.isEmpty {
                return
            }
            let uuid = multipeerSession.peers.first { $0.displayName == peerIDString }?.uuid
            let message = Message(
                text: text,
                senderName: senderName,
                isOutgoing: false,
                peerID: peerIDString,
                peerUUID: uuid,
                wireID: wireID
            )
            modelContext.insert(message)
            try? modelContext.save()
        }
        // Mark the matching outgoing Message as delivered when the peer ACKs.
        .onReceive(multipeerSession.ackPublisher) { wireID in
            if let match = try? modelContext.fetch(
                FetchDescriptor<Message>(predicate: #Predicate { $0.wireID == wireID })
            ).first {
                match.deliveredAt = Date()
                try? modelContext.save()
            }
        }
        // Upsert KnownPeer and retroactively tag unlinked messages when a handshake arrives.
        // ScheduledMessageService delivery is handled via its own Combine subscription.
        .onReceive(multipeerSession.handshakePublisher) { peerID, uuid, displayName in
            upsertKnownPeer(uuid: uuid, displayName: displayName)
            retrotagMessages(peerID: peerID, uuid: uuid)
            try? modelContext.save()
        }
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

    private var storageUnavailableWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive.badge.xmark")
            Text("Storage is unavailable. Messages won't be saved this session.")
                .font(.caption)
            Spacer()
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red)
    }

    private var storeResetWarning: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Your message history was reset to recover from a storage error.")
                .font(.caption)
            Spacer()
            Button {
                storeWasReset = false
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.85))
    }

    /// Targeted diagnostic banner. Picks the most actionable failure reason between
    /// Bluetooth power state, BT authorization, and the catch-all multipeer
    /// "discovery failed" signal. Returns an empty view when everything is healthy.
    @ViewBuilder
    private var diagnosticBanner: some View {
        switch proximityBluetoothService.bluetoothAuthorization {
        case .denied, .restricted:
            permissionDeniedBanner
        case .notDetermined, .allowedAlways:
            switch proximityBluetoothService.bluetoothState {
            case .poweredOff:
                bluetoothOffBanner
            case .unauthorized:
                permissionDeniedBanner
            case .unsupported:
                bluetoothUnsupportedBanner
            case .unknown, .resetting, .poweredOn:
                if !multipeerSession.isDiscoverable {
                    discoveryRetryingBanner
                }
            @unknown default:
                EmptyView()
            }
        @unknown default:
            EmptyView()
        }
    }

    private var bluetoothOffBanner: some View {
        bannerRow(
            icon: "bolt.horizontal.circle",
            text: String(localized: "Bluetooth is off — turn it on to find nearby people."),
            background: .orange
        )
    }

    private var bluetoothUnsupportedBanner: some View {
        bannerRow(
            icon: "exclamationmark.triangle",
            text: String(localized: "This device doesn't support Bluetooth."),
            background: .red
        )
    }

    private var permissionDeniedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.slash")
            Text("Bluetooth permission denied.")
                .font(.caption)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .tint(.white)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.orange)
    }

    private var discoveryRetryingBanner: some View {
        bannerRow(
            icon: "exclamationmark.triangle",
            text: String(localized: "Discovery failed — retrying\u{2026}"),
            background: .orange
        )
    }

    private func bannerRow(icon: String, text: String, background: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(background)
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
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    multipeerSession.forget(peer: peer)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
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
                Text(peer.resolvedDisplayName ?? peer.displayName)
                    .font(.body)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(peer.statusLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
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
