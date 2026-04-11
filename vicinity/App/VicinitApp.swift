import SwiftUI
import SwiftData

enum AppColorScheme: String {
    case system, light, dark

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

@main
struct VicinitApp: App {

    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("appColorScheme") private var appColorScheme: AppColorScheme = .system

    private let modelContainer: ModelContainer
    @StateObject private var multipeerSession: MultipeerSession
    @StateObject private var scheduledMessageService: ScheduledMessageService
    @StateObject private var proximityBluetoothService: ProximityBluetoothService

    init() {
        let schema = Schema([Message.self, KnownPeer.self, ScheduledMessage.self])
        modelContainer = Self.makeModelContainer(schema: schema)

        let session = MultipeerSession()
        _multipeerSession = StateObject(wrappedValue: session)

        let sms = ScheduledMessageService(
            modelContext: modelContainer.mainContext,
            multipeerSession: session
        )
        _scheduledMessageService = StateObject(wrappedValue: sms)

        let pbs = ProximityBluetoothService(deviceUUID: session.myDeviceUUID)
        _proximityBluetoothService = StateObject(wrappedValue: pbs)
    }

    private static func makeModelContainer(schema: Schema) -> ModelContainer {
        do {
            return try ModelContainer(for: schema)
        } catch {
            // Schema changed without a migration plan, or the store is corrupted.
            // Delete all three SQLite files and recreate from scratch — the app
            // recovers rather than crashing in a boot loop on every launch.
            print("[VicinitApp] ModelContainer failed (\(error)). Recreating store.")
            let supportDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(name))
            }
            // If this also fails the device/environment is fundamentally broken.
            return try! ModelContainer(for: schema)
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if hasCompletedOnboarding {
                    ContentView()
                        .environmentObject(multipeerSession)
                        .environmentObject(scheduledMessageService)
                        .environmentObject(proximityBluetoothService)
                } else {
                    OnboardingView()
                        .environmentObject(multipeerSession)
                }
            }
            .preferredColorScheme(appColorScheme.colorScheme)
        }
        .modelContainer(modelContainer)
    }
}
