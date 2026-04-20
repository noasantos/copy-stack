import AppKit
@testable import ClipStack
import XCTest

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        NSPasteboard.general.clearContents()
    }

    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testDetectsTextChange() {
        let store = ClipboardStore()
        let monitor = ClipboardMonitor(store: store)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("hello", forType: .string)
        monitor.pollOnce()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].textValue, "hello")
    }

    func testIgnoresSelfWrite() {
        let store = ClipboardStore()
        let monitor = ClipboardMonitor(store: store)

        store.isSelfWriting = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("self write", forType: .string)
        monitor.pollOnce()
        store.isSelfWriting = false

        XCTAssertTrue(store.items.isEmpty)
    }

    func testSequentialPasteboardChangesStayWithinHistoryLimitAndDoNotDuplicate() {
        let store = ClipboardStore(semanticIndex: MonitorTestSemanticIndex())
        let monitor = ClipboardMonitor(store: store)
        let expectation = expectation(description: "processed pasteboard changes")

        for index in 0..<200 {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("stress \(index)", forType: .string)
            monitor.pollOnce()
        }

        expectation.fulfill()
        wait(for: [expectation], timeout: 1)

        XCTAssertLessThanOrEqual(store.items.count, ClipboardStore.defaultMaxItems)

        let textValues = store.items.compactMap(\.textValue)
        XCTAssertEqual(Set(textValues).count, textValues.count)
        XCTAssertEqual(textValues.count, 200)
    }

    func testSelfWritingResetsAfterRestoreDelay() async throws {
        let store = ClipboardStore(semanticIndex: MonitorTestSemanticIndex())
        let monitor = ClipboardMonitor(store: store)

        store.restore(.text("restored"))
        monitor.pollOnce()

        XCTAssertTrue(store.items.isEmpty)

        try await Task.sleep(nanoseconds: 650_000_000)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("after reset", forType: .string)
        monitor.pollOnce()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(store.items[0].textValue, "after reset")
    }

    func testDetectsImageChange() {
        let store = ClipboardStore()
        let monitor = ClipboardMonitor(store: store)
        let image = NSImage.onePixelTestImage()

        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        monitor.pollOnce()

        XCTAssertEqual(store.items.count, 1)
        XCTAssertNotNil(store.items[0].imageValue)
    }
}

private actor MonitorTestSemanticIndex: SemanticIndexing {
    func rebuild(items: [(id: UUID, text: String)]) async {}

    func add(id: UUID, text: String) async {}

    func remove(id: UUID) async {}

    func clear() async {}

    func search(query: String, allItems: [ClipboardItem]) async -> [ClipboardItem] {
        []
    }
}
