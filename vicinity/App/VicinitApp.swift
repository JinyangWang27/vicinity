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
        let container = try! ModelContainer(for: schema)
        modelContainer = container

        let session = MultipeerSession()
        _multipeerSession = StateObject(wrappedValue: session)

        let sms = ScheduledMessageService(
            modelContext: container.mainContext,
            multipeerSession: session
        )
        _scheduledMessageService = StateObject(wrappedValue: sms)

        let pbs = ProximityBluetoothService(deviceUUID: session.myDeviceUUID)
        _proximityBluetoothService = StateObject(wrappedValue: pbs)
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
