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
}
