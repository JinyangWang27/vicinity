import SwiftUI
import SwiftData

/// Settings screen — lets users set their display name and export conversations.
struct SettingsView: View {
    @EnvironmentObject private var multipeerSession: MultipeerSession
    @Environment(\.dismiss) private var dismiss
    @Query private var allMessages: [Message]

    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    @State private var displayName: String =
        UserDefaults.standard.string(forKey: "displayName") ?? ""
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showExportPicker = false
    @State private var didCopyUUID = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Display Name") {
                    TextField("Your name", text: $displayName)
                        .autocorrectionDisabled()
                    Text("This name is visible to nearby peers.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Device ID")
                            Text("…" + multipeerSession.myDeviceUUID.suffix(8))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = multipeerSession.myDeviceUUID
                            didCopyUUID = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                didCopyUUID = false
                            }
                        } label: {
                            Image(systemName: didCopyUUID ? "checkmark" : "doc.on.doc")
                                .foregroundStyle(didCopyUUID ? .green : .blue)
                        }
                        .buttonStyle(.plain)
                    }
                    Text("Share this ID to restore your identity on a new device.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Identity")
                }

                Section("Export") {
                    Button("Export Conversation as JSON") {
                        showExportPicker = true
                    }
                    .disabled(allMessages.isEmpty)
                    Text("Share a full conversation log as a JSON file. Your Device ID is included so your identity can be restored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Appearance") {
                    Picker("Theme", selection: $appColorScheme) {
                        Text("Light").tag(AppColorScheme.light)
                        Text("Dark").tag(AppColorScheme.dark)
                        Text("System").tag(AppColorScheme.system)
                    }
                    .pickerStyle(.segmented)
                }

                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Privacy", value: "No data leaves your device except to nearby peers.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && trimmed != multipeerSession.myDisplayName {
                            multipeerSession.updateDisplayName(trimmed)
                            UserDefaults.standard.set(trimmed, forKey: "displayName")
                        }
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showExportPicker) {
                ExportPickerView(
                    allMessages: allMessages,
                    deviceUUID: multipeerSession.myDeviceUUID
                ) { url in
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
    let deviceUUID: String
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
                    let peerUUID = msgs.first?.peerUUID
                    onSelect(ExportManager.exportJSON(
                        peerName: peerID,
                        peerUUID: peerUUID,
                        deviceUUID: deviceUUID,
                        messages: msgs
                    ))
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
