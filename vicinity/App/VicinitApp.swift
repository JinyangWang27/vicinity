import SwiftUI
import SwiftData

@main
struct VicinitApp: App {
    @StateObject private var multipeerSession = MultipeerSession()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(multipeerSession)
        }
        .modelContainer(for: Message.self)
    }
}
