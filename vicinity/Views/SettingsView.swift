import SwiftUI
import SwiftData

/// Settings screen — lets users set their display name and export conversations.
struct SettingsView: View {
    @EnvironmentObject private var multipeerSession: MultipeerSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \KnownPeer.lastSeen, order: .reverse) private var knownPeers: [KnownPeer]

    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    @State private var displayName: String =
        UserDefaults.standard.string(forKey: "displayName") ?? ""
    @State private var exportURL: URL?
    @State private var showShareSheet = false
    @State private var showExportPicker = false
    @State private var didCopyUUID = false
    @State private var pendingDisplayName: String?

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
                        .accessibilityLabel(didCopyUUID
                            ? String(localized: "Device ID copied")
                            : String(localized: "Copy device ID"))
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
                    .disabled(knownPeers.isEmpty)
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
                            // Display-name change tears down and rebuilds the entire MC
                            // stack — peers vanish for several seconds. Confirm first.
                            pendingDisplayName = trimmed
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .confirmationDialog(
                "Change your display name?",
                isPresented: Binding(
                    get: { pendingDisplayName != nil },
                    set: { if !$0 { pendingDisplayName = nil } }
                ),
                titleVisibility: .visible,
                presenting: pendingDisplayName
            ) { trimmed in
                Button("Change") {
                    multipeerSession.updateDisplayName(trimmed)
                    UserDefaults.standard.set(trimmed, forKey: "displayName")
                    pendingDisplayName = nil
                    dismiss()
                }
                Button("Cancel", role: .cancel) { pendingDisplayName = nil }
            } message: { _ in
                Text("Vicinity will reconnect to nearby people. This takes a few seconds.")
            }
            .sheet(isPresented: $showExportPicker) {
                ExportPickerView(
                    knownPeers: knownPeers,
                    deviceUUID: multipeerSession.myDeviceUUID,
                    fetchMessages: { uuid in
                        (try? modelContext.fetch(
                            FetchDescriptor<Message>(
                                predicate: #Predicate { $0.peerUUID == uuid },
                                sortBy: [SortDescriptor(\.timestamp)]
                            )
                        )) ?? []
                    }
                ) { url in
                    exportURL = url
                    showExportPicker = false
                    showShareSheet = url != nil
                }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                if let url = exportURL { ExportManager.cleanup(url) }
                exportURL = nil
            }) {
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

/// Lets users pick which peer's conversation to export. The picker reads from
/// KnownPeer rather than scanning every Message, and only fetches messages for
/// the chosen peer when the user actually taps a row.
private struct ExportPickerView: View {
    let knownPeers: [KnownPeer]
    let deviceUUID: String
    let fetchMessages: (String) -> [Message]
    let onSelect: (URL?) -> Void

    var body: some View {
        NavigationStack {
            List(knownPeers) { known in
                Button(known.displayName) {
                    let msgs = fetchMessages(known.uuid)
                    onSelect(ExportManager.exportJSON(
                        peerName: known.displayName,
                        peerUUID: known.uuid,
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
