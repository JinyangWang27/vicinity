import XCTest
import SwiftData
import Combine
@testable import vicinity

final class ScheduledMessageServiceTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!
    private var session: MultipeerSession!
    private var service: ScheduledMessageService!
    private var cancellables = Set<AnyCancellable>()

    override func setUpWithError() throws {
        let schema = Schema([ScheduledMessage.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
        session = MultipeerSession()
        service = ScheduledMessageService(modelContext: context, multipeerSession: session)
    }

    override func tearDownWithError() throws {
        cancellables.removeAll()
        service = nil
        session = nil
        container = nil
        context = nil
    }

    func test_schedule_createsPendingMessage() throws {
        try service.schedule(text: "hi", forPeerUUID: "uuid-a")
        let messages = try context.fetch(
            FetchDescriptor<ScheduledMessage>(
                predicate: #Predicate { $0.targetPeerUUID == "uuid-a" }
            )
        )
        XCTAssertEqual(messages.count, 1)
        XCTAssertEqual(messages[0].status, .pending)
        XCTAssertEqual(messages[0].text, "hi")
    }

    func test_cancel_setsCancelledStatus() throws {
        try service.schedule(text: "hi", forPeerUUID: "uuid-a")
        let messages = try context.fetch(FetchDescriptor<ScheduledMessage>())
        try service.cancel(messages[0])
        XCTAssertEqual(messages[0].status, .cancelled)
    }

    func test_pendingMessages_onlyReturnsPending() throws {
        try service.schedule(text: "msg1", forPeerUUID: "uuid-a")
        try service.schedule(text: "msg2", forPeerUUID: "uuid-a")
        let all = try context.fetch(FetchDescriptor<ScheduledMessage>())
        try service.cancel(all[0])

        let pending = try service.pendingMessages(forPeerUUID: "uuid-a")
        XCTAssertEqual(pending.count, 1)
        XCTAssertEqual(pending[0].text, "msg2")
    }

    func test_handleHandshake_marksPendingMessageAsSent() throws {
        try service.schedule(text: "hi", forPeerUUID: "peer-uuid-123")
        // send is a no-op when the peer isn't in the MPC session, but status still updates
        service.handleHandshake(peerIDString: "SomePeer", uuid: "peer-uuid-123", displayName: "Alice")
        let messages = try context.fetch(FetchDescriptor<ScheduledMessage>())
        XCTAssertEqual(messages[0].status, .sent)
        XCTAssertNotNil(messages[0].sentAt)
    }

    func test_handleHandshake_ignoresNonMatchingUUID() throws {
        try service.schedule(text: "hi", forPeerUUID: "uuid-A")
        service.handleHandshake(peerIDString: "SomePeer", uuid: "uuid-B", displayName: "Bob")
        let messages = try context.fetch(FetchDescriptor<ScheduledMessage>())
        XCTAssertEqual(messages[0].status, .pending)
    }

    func test_handleHandshake_ignoresAlreadySentMessages() throws {
        try service.schedule(text: "hi", forPeerUUID: "uuid-A")
        service.handleHandshake(peerIDString: "SomePeer", uuid: "uuid-A", displayName: "Alice")
        service.handleHandshake(peerIDString: "SomePeer", uuid: "uuid-A", displayName: "Alice")
        let messages = try context.fetch(FetchDescriptor<ScheduledMessage>())
        XCTAssertEqual(messages.count, 1)  // no duplicate sends
    }
}
