import SwiftUI
import SwiftData

/// Displays the conversation thread with a specific peer.
struct ChatView: View {
    let peer: Peer

    @EnvironmentObject var multipeerSession: MultipeerSession
    @Environment(\.modelContext) private var modelContext

    /// Messages tagged with this peer's UUID (post-handshake / retrotagged).
    @Query private var byUUID: [Message]
    /// Messages tagged only by display-name peerID (pre-handshake).
    @Query private var byDisplayName: [Message]

    @State private var inputText = ""
    @State private var showClearConfirmation = false
    @State private var lastSendFailed = false

    init(peer: Peer) {
        self.peer = peer
        // Sentinel that won't match any real UUID, used when peer.uuid is nil so the
        // byUUID query simply returns nothing rather than the full table.
        let uuid = peer.uuid ?? "__no_uuid__"
        let displayName = peer.displayName
        _byUUID = Query(
            filter: #Predicate<Message> { $0.peerUUID == uuid },
            sort: \Message.timestamp
        )
        _byDisplayName = Query(
            filter: #Predicate<Message> { $0.peerID == displayName },
            sort: \Message.timestamp
        )
    }

    /// Live peer entry from the session — reflects the current connection state and UUID
    /// even when those fields have changed since this view was pushed. Prefers the
    /// MCPeerID instance (stable across handshake) and falls back to display-name match
    /// in case the instance was replaced via BLE rediscovery.
    private var livePeer: Peer? {
        multipeerSession.peers.first { $0.peerID == peer.peerID }
            ?? multipeerSession.peers.first { $0.displayName == peer.displayName }
    }

    /// Union of the two predicate-scoped queries, deduped by message id and sorted by
    /// timestamp. Avoids the O(N) scan of @Query of all messages.
    private var messages: [Message] {
        var seen = Set<UUID>()
        var combined: [Message] = []
        for m in byUUID + byDisplayName where seen.insert(m.id).inserted {
            combined.append(m)
        }
        return combined.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            if peer.uuid == nil {
                preHandshakeFooter
            }
            Divider()
            inputBar
        }
        .onChange(of: livePeer?.isConnected) { _, connected in
            // Clear the stale "send failed" banner once we're back online so the user
            // isn't staring at a red bar after they reconnect.
            if connected == true { lastSendFailed = false }
        }
        .navigationTitle(peer.resolvedDisplayName ?? peer.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(
                    destination: ScheduledMessagesView(
                        peerUUID: peer.uuid ?? "",
                        peerDisplayName: peer.resolvedDisplayName ?? peer.displayName
                    )
                ) {
                    Image(systemName: "clock.badge.plus")
                }
                .disabled(peer.uuid == nil)
                .accessibilityLabel(String(localized: "Schedule a message"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        showClearConfirmation = true
                    } label: {
                        Label("Clear Conversation", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .disabled(messages.isEmpty)
                .accessibilityLabel(String(localized: "More options"))
            }
        }
        .confirmationDialog(
            "Clear this conversation?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                for message in messages {
                    modelContext.delete(message)
                }
            }
        } message: {
            Text("All messages with \(peer.resolvedDisplayName ?? peer.displayName) will be permanently deleted from this device.")
        }
    }

    // MARK: - Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                            .contextMenu {
                                Button(role: .destructive) {
                                    modelContext.delete(message)
                                } label: {
                                    Label("Delete Message", systemImage: "trash")
                                }
                            }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onAppear {
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = messages.last {
            withAnimation {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    /// Footer shown below the message list while the peer's UUID is unknown,
    /// explaining why the schedule-message clock icon is disabled.
    private var preHandshakeFooter: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
            Text("Scheduling becomes available once connected.")
            Spacer()
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if livePeer?.isConnected != true {
                connectionBanner
                Divider()
            }
            if lastSendFailed {
                sendFailureBanner
                Divider()
            }
            HStack(spacing: 8) {
                TextField("Message", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .submitLabel(.send)
                    .onSubmit(sendMessage)

                Button(action: sendMessage) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend)
                .accessibilityLabel(String(localized: "Send message"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
    }

    private var sendFailureBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.circle")
            Text("Message failed to send")
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.red.opacity(0.85))
    }

    @ViewBuilder
    private var connectionBanner: some View {
        HStack(spacing: 6) {
            if let livePeer {
                if livePeer.state == .connecting {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting\u{2026}")
                } else {
                    Image(systemName: "wifi.slash")
                    Text("Not connected")
                    Spacer()
                    Button("Reconnect") {
                        multipeerSession.connect(to: livePeer)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            } else {
                Image(systemName: "wifi.slash")
                Text("Not in range")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        livePeer?.isConnected == true
    }

    private func sendMessage() {
        guard canSend, let livePeer else { return }
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)

        let wireID = multipeerSession.send(text: trimmed, to: livePeer)
        lastSendFailed = (wireID == nil)

        if let wireID {
            let message = Message(
                text: trimmed,
                senderName: multipeerSession.myDisplayName,
                isOutgoing: true,
                peerID: livePeer.displayName,
                peerUUID: livePeer.uuid,
                wireID: wireID
            )
            modelContext.insert(message)
            try? modelContext.save()
            inputText = ""
        }
    }
}

// MARK: - MessageBubble

private struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 60) }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
                if !message.isOutgoing {
                    Text(message.senderName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }

                Text(message.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.isOutgoing ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                    if message.isOutgoing { deliveryIndicator }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            if !message.isOutgoing { Spacer(minLength: 60) }
        }
    }

    /// Outgoing-only indicator:
    /// - double-check once the peer ACKs receipt (deliveredAt set)
    /// - single-check otherwise (framework accepted but no ACK yet)
    /// Pre-WireMessage messages (no wireID) keep the single-check forever.
    @ViewBuilder
    private var deliveryIndicator: some View {
        if message.deliveredAt != nil {
            Image(systemName: "checkmark.circle.fill")
                .accessibilityLabel(String(localized: "Delivered"))
        } else {
            Image(systemName: "checkmark")
                .accessibilityLabel(String(localized: "Sent"))
        }
    }
}

