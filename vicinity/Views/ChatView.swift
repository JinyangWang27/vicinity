import SwiftUI
import SwiftData

/// Displays the conversation thread with a specific peer.
struct ChatView: View {
    let peer: Peer

    @EnvironmentObject var multipeerSession: MultipeerSession
    @Environment(\.modelContext) private var modelContext

    @Query private var allMessages: [Message]
    @State private var inputText = ""

    /// Messages filtered to this peer's conversation, sorted by time.
    /// Filters by UUID when available (stable across display-name changes and device restores),
    /// falling back to peerID (display name) for pre-v1.1 messages.
    private var messages: [Message] {
        let filtered: [Message]
        if let uuid = peer.uuid {
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
        HStack(spacing: 8) {
            TextField("Message", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...5)
                .submitLabel(.send)
                .onSubmit(sendMessage)

            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        multipeerSession.send(text: trimmed, to: peer)

        let message = Message(
            text: trimmed,
            senderName: multipeerSession.myDisplayName,
            isOutgoing: true,
            peerID: peer.id,
            peerUUID: peer.uuid
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

