import SwiftUI
import SwiftData

/// Shows all scheduled messages targeting a specific peer UUID,
/// grouped by status. Provides delete and new-message creation.
struct ScheduledMessagesView: View {

    let peerUUID: String
    let peerDisplayName: String

    @EnvironmentObject var scheduledMessageService: ScheduledMessageService
    @EnvironmentObject var proximityBluetoothService: ProximityBluetoothService
    @Environment(\.modelContext) private var modelContext

    @Query private var allScheduled: [ScheduledMessage]
    @State private var showCompose = false

    private var forThisPeer: [ScheduledMessage] {
        allScheduled
            .filter { $0.targetPeerUUID == peerUUID }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var pending: [ScheduledMessage] { forThisPeer.filter { $0.status == .pending } }
    private var history: [ScheduledMessage] { forThisPeer.filter { $0.status != .pending } }

    var body: some View {
        List {
            if pending.isEmpty && history.isEmpty {
                ContentUnavailableView(
                    "No scheduled messages",
                    systemImage: "clock.badge.questionmark",
                    description: Text("Tap + to schedule a message for when \(peerDisplayName) is nearby.")
                )
            }
            if !pending.isEmpty {
                Section("Pending") {
                    ForEach(pending) { scheduled in
                        ScheduledMessageRow(scheduled: scheduled)
                    }
                    .onDelete { offsets in
                        deleteScheduled(pending, at: offsets)
                    }
                }
            }
            if !history.isEmpty {
                Section("Sent / Cancelled") {
                    ForEach(history) { scheduled in
                        ScheduledMessageRow(scheduled: scheduled)
                    }
                }
            }
        }
        .navigationTitle("Scheduled for \(peerDisplayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCompose = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            ScheduleMessageView(
                peerUUID: peerUUID,
                peerDisplayName: peerDisplayName
            )
        }
    }

    private func deleteScheduled(_ messages: [ScheduledMessage], at offsets: IndexSet) {
        for index in offsets {
            try? scheduledMessageService.cancel(messages[index])
        }
        syncScanTargets()
    }

    private func syncScanTargets() {
        let pending = ScheduledMessageStatus.pending
        let all = (try? modelContext.fetch(
            FetchDescriptor<ScheduledMessage>(predicate: #Predicate { $0.status == pending })
        )) ?? []
        proximityBluetoothService.updateScanTargets(Array(Set(all.map(\.targetPeerUUID))))
    }
}

// MARK: - ScheduledMessageRow

private struct ScheduledMessageRow: View {
    let scheduled: ScheduledMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scheduled.text)
                .font(.body)
            HStack {
                statusBadge
                Spacer()
                if let sentAt = scheduled.sentAt {
                    Text(sentAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(scheduled.createdAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var statusBadge: some View {
        let (label, color): (String, Color) = switch scheduled.status {
        case .pending:   ("Pending", .orange)
        case .sent:      ("Sent", .green)
        case .cancelled: ("Cancelled", .gray)
        }
        return Text(label)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
