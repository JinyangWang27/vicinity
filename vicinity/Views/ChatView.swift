import SwiftUI
import SwiftData

/// Displays the conversation thread with a specific peer.
struct ChatView: View {
    let peer: Peer

    @EnvironmentObject var multipeerSession: MultipeerSession
    @Environment(\.modelContext) private var modelContext

    @Query private var allMessages: [Message]
    @State private var inputText = ""
    @State private var showClearConfirmation = false

    /// Live peer entry from the session — reflects the current connection state and UUID
    /// even when those fields have changed since this view was pushed.
    private var livePeer: Peer? {
        multipeerSession.peers.first { $0.id == peer.id }
    }

    /// Messages filtered to this peer's conversation, sorted by time.
    /// Prefers the live UUID (updated after handshake) over the snapshot value so the
    /// correct filter is applied as soon as the UUID becomes known mid-session.
    /// Falls back to peerID (display name) for pre-handshake and pre-v1.1 messages.
    private var messages: [Message] {
        let filtered: [Message]
        if let uuid = livePeer?.uuid ?? peer.uuid {
            filtered = allMessages.filter { $0.peerUUID == uuid }
        } else {
            filtered = allMessages.filter { $0.peerID == peer.id }
        }
        return filtered.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            inputBar
        }
        .navigationTitle(peer.id)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(
                    destination: ScheduledMessagesView(
                        peerUUID: peer.uuid ?? "",
                        peerDisplayName: peer.resolvedDisplayName ?? peer.id
                    )
                ) {
                    Image(systemName: "clock.badge.plus")
                }
                .disabled(peer.uuid == nil)
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
            Text("All messages with \(peer.resolvedDisplayName ?? peer.id) will be permanently deleted from this device.")
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

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if livePeer?.isConnected != true {
                connectionBanner
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
        }
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

        multipeerSession.send(text: trimmed, to: livePeer)

        let message = Message(
            text: trimmed,
            senderName: multipeerSession.myDisplayName,
            isOutgoing: true,
            peerID: livePeer.id,
            peerUUID: livePeer.uuid
        )
        modelContext.insert(message)
        inputText = ""
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

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }

            if !message.isOutgoing { Spacer(minLength: 60) }
        }
    }
}

