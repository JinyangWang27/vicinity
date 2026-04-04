import SwiftUI
import SwiftData

/// Settings screen — lets users set their display name and export conversations.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allMessages: [Message]

    @State private var displayName: String =
        UserDefaults.standard.string(forKey: "displayName") ?? ""
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showExportPicker = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Your name", text: $displayName)
                        .autocorrectionDisabled()
                        .onChange(of: displayName) { _, newValue in
                            UserDefaults.standard.set(newValue, forKey: "displayName")
                        }
                    Text("This name is visible to nearby peers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Export") {
                    Button("Export Conversation as JSON") {
                        showExportPicker = true
                    }
                    .disabled(allMessages.isEmpty)
                    Text("Share a full conversation log as a JSON file.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Privacy", value: "No data leaves your device except to nearby peers.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showExportPicker) {
                ExportPickerView(allMessages: allMessages) { url in
                    exportURL = url
                    showExportPicker = false
                    showShareSheet = url != nil
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportURL {
                    ShareSheet(items: [url])
                }
            }
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
}

// MARK: - ExportPickerView

/// Lets users pick which peer's conversation to export.
private struct ExportPickerView: View {
    let allMessages: [Message]
    let onSelect: (URL?) -> Void

    private var peers: [String] {
        Array(Set(allMessages.map { $0.peerID })).sorted()
    }

    var body: some View {
        NavigationStack {
            List(peers, id: \.self) { peerID in
                Button(peerID) {
                    let msgs = allMessages
                        .filter { $0.peerID == peerID }
                        .sorted { $0.timestamp < $1.timestamp }
                    onSelect(ExportManager.exportJSON(peerName: peerID, messages: msgs))
                }
            }
            .navigationTitle("Choose Conversation")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onSelect(nil) }
                }
            }
        }
    }
}

// MARK: - ShareSheet (UIActivityViewController wrapper)

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController,
                                context: Context) {}
}
