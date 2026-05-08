import Foundation
import SwiftData
import Combine
import UserNotifications

/// Orchestrates delivery of scheduled messages when a target peer connects.
/// Also provides CRUD for scheduled messages and fires local notifications on send.
final class ScheduledMessageService: ObservableObject {

    private let modelContext: ModelContext
    private weak var multipeerSession: MultipeerSession?
    private var cancellables = Set<AnyCancellable>()

    init(modelContext: ModelContext, multipeerSession: MultipeerSession) {
        self.modelContext = modelContext
        self.multipeerSession = multipeerSession
        subscribeToHandshakes()
        requestNotificationPermission()
    }

    // MARK: - CRUD

    func schedule(text: String, forPeerUUID peerUUID: String) throws {
        let message = ScheduledMessage(targetPeerUUID: peerUUID, text: text)
        modelContext.insert(message)
        try modelContext.save()
    }

    func cancel(_ scheduledMessage: ScheduledMessage) throws {
        scheduledMessage.status = .cancelled
        try modelContext.save()
    }

    func pendingMessages(forPeerUUID peerUUID: String) throws -> [ScheduledMessage] {
        let pending = ScheduledMessageStatus.pending
        return try modelContext.fetch(
            FetchDescriptor<ScheduledMessage>(
                predicate: #Predicate { $0.targetPeerUUID == peerUUID && $0.status == pending }
            )
        )
    }

    // MARK: - Delivery

    /// Checks for pending scheduled messages for the connected peer and sends them.
    /// Called automatically via Combine subscription; also safe to call directly.
    ///
    /// Each message is moved through pending → sending → sent (or back to pending on
    /// failure). Marking as `.sending` before the transmit attempt prevents a
    /// synchronously-fired second handshake from re-fetching the same row. The wireID
    /// is generated once and reused across retries so the receiver can dedupe.
    func handleHandshake(peerIDString: String, uuid: String, displayName: String) {
        let pending = ScheduledMessageStatus.pending
        let messages = (try? modelContext.fetch(
            FetchDescriptor<ScheduledMessage>(
                predicate: #Predicate { $0.targetPeerUUID == uuid && $0.status == pending }
            )
        )) ?? []
        guard !messages.isEmpty else { return }

        // Stake a claim on each row so a re-entrant handshake doesn't double-fetch.
        for scheduled in messages {
            if scheduled.wireID == nil { scheduled.wireID = UUID() }
            scheduled.status = .sending
        }
        try? modelContext.save()

        var deliveredTexts: [String] = []
        for scheduled in messages {
            let result = multipeerSession?.send(
                text: scheduled.text,
                toPeerDisplayName: peerIDString,
                wireID: scheduled.wireID
            )
            if result != nil {
                scheduled.status = .sent
                scheduled.sentAt = Date()
                deliveredTexts.append(scheduled.text)
            } else {
                // Send refused (peer disconnected mid-handshake). Roll back so the next
                // handshake retries; the receiver dedupes by wireID if both attempts land.
                scheduled.status = .pending
            }
        }
        try? modelContext.save()

        if !deliveredTexts.isEmpty {
            fireNotification(text: deliveredTexts.joined(separator: ", "), toDisplayName: displayName)
        }
    }

    // MARK: - Private

    private func subscribeToHandshakes() {
        multipeerSession?.handshakePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                self?.handleHandshake(
                    peerIDString: event.peerID,
                    uuid: event.uuid,
                    displayName: event.displayName
                )
            }
            .store(in: &cancellables)
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func fireNotification(text: String, toDisplayName displayName: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Scheduled message sent")
        content.body = String(localized: "To \(displayName): \(text)")
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
