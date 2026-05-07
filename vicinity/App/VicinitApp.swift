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

/// First versioned schema. Declaring a `VersionedSchema` lets SwiftData use lightweight
/// inferred migrations for additive changes (new optional fields, added unique constraints
/// on fields whose data is already unique). Without this, any schema change would fall
/// through to the destructive corruption path.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] = [
        Message.self, KnownPeer.self, ScheduledMessage.self
    ]
}

/// Migration plan placeholder. Future model changes that cannot be auto-migrated should
/// add a SchemaV2 (etc.) here together with a `MigrationStage`.
enum VicinityMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] = [SchemaV1.self]
    static var stages: [MigrationStage] = []
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
        modelContainer = Self.makeModelContainer()

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

    private static func makeModelContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        do {
            return try ModelContainer(for: schema, migrationPlan: VicinityMigrationPlan.self)
        } catch {
            print("[VicinitApp] ModelContainer failed (\(error)). Recreating store.")
            UserDefaults.standard.set(true, forKey: "storeWasReset")
            let supportDir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first!
            for name in ["default.store", "default.store-shm", "default.store-wal"] {
                try? FileManager.default.removeItem(at: supportDir.appendingPathComponent(name))
            }
            do {
                return try ModelContainer(for: schema, migrationPlan: VicinityMigrationPlan.self)
            } catch {
                // Disk full / sandbox issue / fundamentally broken environment.
                // Fall back to an in-memory container so the app still launches and the
                // user can read the warning banner instead of crashing in a boot loop.
                print("[VicinitApp] Recreate also failed (\(error)). Falling back to in-memory.")
                UserDefaults.standard.set(true, forKey: "storageUnavailable")
                return try! ModelContainer(
                    for: schema,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            }
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
