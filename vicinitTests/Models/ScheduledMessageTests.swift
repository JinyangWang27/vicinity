import XCTest
import SwiftData
@testable import vicinity

final class ScheduledMessageTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([ScheduledMessage.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func test_init_setsPendingStatus() throws {
        let msg = ScheduledMessage(targetPeerUUID: "uuid-1", text: "hello")
        XCTAssertEqual(msg.targetPeerUUID, "uuid-1")
        XCTAssertEqual(msg.text, "hello")
        XCTAssertEqual(msg.status, .pending)
        XCTAssertNil(msg.sentAt)
    }

    func test_persist_andFetch() throws {
        let msg = ScheduledMessage(targetPeerUUID: "uuid-1", text: "hello")
        context.insert(msg)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ScheduledMessage>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "hello")
        XCTAssertEqual(fetched[0].status, .pending)
    }

    func test_status_canBeUpdatedToSent() throws {
        let msg = ScheduledMessage(targetPeerUUID: "uuid-1", text: "hello")
        context.insert(msg)
        msg.status = .sent
        msg.sentAt = Date()
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ScheduledMessage>())
        XCTAssertEqual(fetched[0].status, .sent)
        XCTAssertNotNil(fetched[0].sentAt)
    }

    func test_wireID_canBePersistedAndReused() throws {
        let msg = ScheduledMessage(targetPeerUUID: "uuid-1", text: "hello")
        context.insert(msg)
        XCTAssertNil(msg.wireID)

        let id = UUID()
        msg.wireID = id
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<ScheduledMessage>())
        XCTAssertEqual(fetched[0].wireID, id)
    }

    func test_sendingStatus_isDistinctFromPending() throws {
        let msg = ScheduledMessage(targetPeerUUID: "uuid-1", text: "hello")
        context.insert(msg)
        msg.status = .sending
        try context.save()

        let pending = ScheduledMessageStatus.pending
        let stillPending = try context.fetch(
            FetchDescriptor<ScheduledMessage>(
                predicate: #Predicate { $0.status == pending }
            )
        )
        XCTAssertTrue(stillPending.isEmpty, ".sending must not match a .pending predicate")
    }
}

// MARK: - Message dedupe

final class MessageDedupeTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func test_wireID_canBeFetched() throws {
        let wireID = UUID()
        let msg = Message(
            text: "hi",
            senderName: "Alice",
            isOutgoing: false,
            peerID: "Alice",
            peerUUID: "uuid-A",
            wireID: wireID
        )
        context.insert(msg)
        try context.save()

        let fetched = try context.fetch(
            FetchDescriptor<Message>(predicate: #Predicate { $0.wireID == wireID })
        )
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].text, "hi")
    }

    func test_deliveredAt_canBeMarked() throws {
        let msg = Message(
            text: "hi",
            senderName: "Me",
            isOutgoing: true,
            peerID: "Bob",
            peerUUID: "uuid-B",
            wireID: UUID()
        )
        context.insert(msg)
        XCTAssertNil(msg.deliveredAt)

        msg.deliveredAt = Date()
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Message>())
        XCTAssertNotNil(fetched[0].deliveredAt)
    }
}

// MARK: - KnownPeer uniqueness

final class KnownPeerUniqueTests: XCTestCase {

    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUpWithError() throws {
        let schema = Schema([KnownPeer.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    func test_uniqueConstraint_collapsesDuplicateInserts() throws {
        let a = KnownPeer(uuid: "uuid-1", displayName: "Alice")
        let b = KnownPeer(uuid: "uuid-1", displayName: "Alice2")
        context.insert(a)
        context.insert(b)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<KnownPeer>())
        // Unique attribute on uuid means SwiftData reconciles to a single row.
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].uuid, "uuid-1")
    }
}
