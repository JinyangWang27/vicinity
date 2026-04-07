import SwiftUI
import SwiftData

@main
struct VicinitApp: App {

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
            ContentView()
                .environmentObject(multipeerSession)
                .environmentObject(scheduledMessageService)
                .environmentObject(proximityBluetoothService)
        }
        .modelContainer(modelContainer)
    }
}
