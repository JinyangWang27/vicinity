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
        let deviceUUID: String   // this device's permanent UUID — use to restore identity on a new device
        let peer: String
        let peerUUID: String?    // peer's permanent UUID if known
        let messages: [ExportMessage]
    }

    /// Builds a temporary JSON file and returns its URL, or nil on failure.
    /// The file is written into a unique per-export subdirectory of the temp directory
    /// so callers can clean up the whole subdirectory once the share sheet dismisses
    /// without accidentally deleting unrelated temp files.
    static func exportJSON(peerName: String,
                           peerUUID: String?,
                           deviceUUID: String,
                           messages: [Message]) -> URL? {
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
            deviceUUID: deviceUUID,
            peer: peerName,
            peerUUID: peerUUID,
            messages: exportMessages
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        guard let data = try? encoder.encode(payload) else { return nil }

        let subdir = FileManager.default.temporaryDirectory
            .appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let safePeerName = peerName.replacingOccurrences(of: "/", with: "_")
        let fileURL = subdir.appendingPathComponent("vicinity-\(safePeerName).json")

        do {
            try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            print("[ExportManager] Failed to write export file: \(error)")
            return nil
        }
    }

    /// Best-effort cleanup of an export file's enclosing subdirectory. Call after the
    /// share sheet dismisses so the plaintext payload doesn't sit in /tmp until the
    /// OS reaps it.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
