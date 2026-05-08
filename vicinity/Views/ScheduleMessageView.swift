import SwiftUI
import SwiftData

/// Sheet for composing a new scheduled message targeting a specific peer.
struct ScheduleMessageView: View {

    let peerUUID: String
    let peerDisplayName: String

    @EnvironmentObject var scheduledMessageService: ScheduledMessageService
    @Environment(\.dismiss) private var dismiss

    @State private var messageText = ""
    @State private var errorMessage: String?

    private var isValid: Bool {
        !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Message to send on arrival", text: $messageText, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Message")
                } footer: {
                    Text("This message will be sent automatically when \(peerDisplayName) comes within Bluetooth range.")
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Schedule Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Schedule") { save() }
                        .disabled(!isValid)
                        .fontWeight(.semibold)
                }
            }
        }
    }

    private func save() {
        let trimmed = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try scheduledMessageService.schedule(text: trimmed, forPeerUUID: peerUUID)
            dismiss()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }
}
