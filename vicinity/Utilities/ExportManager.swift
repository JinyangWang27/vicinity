import Foundation

/// Exports a conversation as a JSON file suitable for sharing via the system Share Sheet.
struct ExportManager {

    struct ExportMessage: Codable {
        let sender: String
        let text: String
        let timestamp: String
        let direction: String
    }

    struct ExportPayload: Codable {
        let exportedAt: String
        let peer: String
        let messages: [ExportMessage]
    }

    /// Builds a temporary JSON file and returns its URL, or nil on failure.
    static func exportJSON(peerName: String, messages: [Message]) -> URL? {
        let formatter = ISO8601DateFormatter()

        let exportMessages = messages.map { msg in
            ExportMessage(
                sender: msg.senderName,
                text: msg.text,
                timestamp: formatter.string(from: msg.timestamp),
                direction: msg.isOutgoing ? "outgoing" : "incoming"
            )
        }

        let payload = ExportPayload(
            exportedAt: formatter.string(from: Date()),
            peer: peerName,
            messages: exportMessages
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("vicinity-\(peerName)-\(Date().timeIntervalSince1970).json")

        do {
            try data.write(to: tempURL, options: .atomic)
            return tempURL
        } catch {
            print("[ExportManager] Failed to write export file: \(error)")
            return nil
        }
    }
}
