import SwiftUI
import SwiftData

/// Displays all peers whose identity has been confirmed via UUID handshake,
/// sorted by most recently seen. A green dot indicates the peer is currently nearby.
struct KnownFriendsView: View {
    @Query(sort: \KnownPeer.lastSeen, order: .reverse) private var knownPeers: [KnownPeer]
    @EnvironmentObject private var multipeerSession: MultipeerSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if knownPeers.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("Known Friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var list: some View {
        List(knownPeers) { known in
            KnownFriendRow(known: known, isNearby: isNearby(known))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No known friends yet")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Friends appear here after your first connected chat.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private func isNearby(_ known: KnownPeer) -> Bool {
        multipeerSession.peers.contains { $0.uuid == known.uuid }
    }
}

// MARK: - KnownFriendRow

private struct KnownFriendRow: View {
    let known: KnownPeer
    let isNearby: Bool

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(isNearby ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(known.displayName)
                    .font(.body)
                Text(lastSeenLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var lastSeenLabel: String {
        if isNearby { return String(localized: "Nearby now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relative = formatter.localizedString(for: known.lastSeen, relativeTo: Date())
        return String(format: String(localized: "last_seen_format",
                                    defaultValue: "Last seen %@"), relative)
    }
}
