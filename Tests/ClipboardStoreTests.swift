import AppKit
@testable import ClipStack
import XCTest

@MainActor
final class ClipboardStoreTests: XCTestCase {
    override func tearDown() {
        NSPasteboard.general.clearContents()
        super.tearDown()
    }

    func testAddTextItem() {
        let store = ClipboardStore()

        store.add(.text("hello"))

        XCTAssertEqual(store.items.count, 1)
        if case .text(let text, id: _, timestamp: _) = store.items[0] {
            XCTAssertEqual(text, "hello")
        } else {
            XCTFail("Expected text item")
        }
    }

    func testDeduplication() {
        let store = ClipboardStore()

        store.add(.text("duplicate"))
        store.add(.text("duplicate"))

        XCTAssertEqual(store.items.count, 1)
    }

    func testDuplicateTextMovesExistingItemToTopWithLatestTimestampAndSameID() {
        let store = ClipboardStore()
        let originalID = UUID()
        let originalDate = Date(timeIntervalSince1970: 100)
        let latestDate = Date(timeIntervalSince1970: 200)

        store.add(.text("duplicate", id: originalID, timestamp: originalDate))
        store.add(.text("other"))
        store.add(.text("duplicate", timestamp: latestDate))

        XCTAssertEqual(store.items.count, 2)
        XCTAssertEqual(store.items[0].id, originalID)
        XCTAssertEqual(store.items[0].textValue, "duplicate")
        XCTAssertEqual(store.items[0].timestamp, latestDate)
        XCTAssertEqual(store.items[1].textValue, "other")
    }

    func testTextDeduplicationUsesExactEquality() {
        let store = ClipboardStore()

        store.add(.text("hello"))
        store.add(.text(" hello"))
        store.add(.text("Hello"))
        store.add(.text("hello\n"))

        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.items.map(\.textValue), ["hello\n", "Hello", " hello", "hello"])
    }

    func testCapAtMaxItems() {
        let store = ClipboardStore()

        for index in 0..<(ClipboardStore.defaultMaxItems + 1) {
            store.add(.text("item \(index)"))
        }

        XCTAssertEqual(store.items.count, ClipboardStore.defaultMaxItems)
    }

    func testAddingTextWhenHistoryIsFullDropsOldestItem() {
        let store = ClipboardStore(maxItems: 3)

        store.add(.text("oldest"))
        store.add(.text("middle"))
        store.add(.text("newest"))
        store.add(.text("incoming"))

        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.textValue), ["incoming", "newest", "middle"])
        XCTAssertFalse(store.items.contains { $0.textValue == "oldest" })
    }

    func testAddingImageWhenTotalHistoryIsFullDropsOldestItem() {
        let store = ClipboardStore(maxItems: 3, maxImageItems: 3)

        store.add(.text("oldest"))
        store.add(.text("middle"))
        store.add(.text("newest"))
        store.add(.image(.onePixelTestImage()))

        XCTAssertEqual(store.items.count, 3)
        XCTAssertNotNil(store.items[0].imageValue)
        XCTAssertEqual(store.items.compactMap(\.textValue), ["newest", "middle"])
        XCTAssertFalse(store.items.contains { $0.textValue == "oldest" })
    }

    func testAddingImageWhenImageHistoryIsFullDropsOldestImageButKeepsTexts() {
        let store = ClipboardStore(maxItems: 10, maxImageItems: 2)

        store.add(.image(.onePixelTestImage(color: .black)))
        store.add(.text("text 1"))
        store.add(.image(.onePixelTestImage(color: .white)))
        store.add(.text("text 2"))
        store.add(.image(.onePixelTestImage(color: .red)))

        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.items.filter { $0.imageValue != nil }.count, 2)
        XCTAssertEqual(store.items.compactMap(\.textValue), ["text 2", "text 1"])
    }

    func testDuplicateTextWhenHistoryIsFullMovesToTopWithoutDroppingAnotherItem() {
        let store = ClipboardStore(maxItems: 3)
        let originalID = UUID()
        let latestDate = Date(timeIntervalSince1970: 300)

        store.add(.text("oldest"))
        store.add(.text("middle", id: originalID, timestamp: Date(timeIntervalSince1970: 100)))
        store.add(.text("newest"))
        store.add(.text("middle", timestamp: latestDate))

        XCTAssertEqual(store.items.count, 3)
        XCTAssertEqual(store.items.map(\.textValue), ["middle", "newest", "oldest"])
        XCTAssertEqual(store.items[0].id, originalID)
        XCTAssertEqual(store.items[0].timestamp, latestDate)
    }

    func testCapsImagesSeparatelyFromTextHistory() {
        let store = ClipboardStore(maxItems: 100, maxImageItems: 2)

        store.add(.image(.onePixelTestImage()))
        store.add(.text("text 1"))
        store.add(.image(.onePixelTestImage(color: .white)))
        store.add(.text("text 2"))
        store.add(.image(.onePixelTestImage(color: .red)))

        XCTAssertEqual(store.items.count, 4)
        XCTAssertEqual(store.items.filter { $0.imageValue != nil }.count, 2)
        XCTAssertEqual(store.items.filter { $0.textValue != nil }.count, 2)
    }

    func testPersistentHistoryPrunesExtraImagesOnReload() throws {
        let persistence = try makeTemporaryPersistence()
        let firstStore = ClipboardStore(maxItems: 100, maxImageItems: 3, persistence: persistence)

        firstStore.add(.image(.onePixelTestImage()))
        firstStore.add(.image(.onePixelTestImage(color: .white)))
        firstStore.add(.image(.onePixelTestImage(color: .red)))
        firstStore.add(.image(.onePixelTestImage(color: .blue)))
        firstStore.add(.text("keep me"))

        let reloadedStore = ClipboardStore(maxItems: 100, maxImageItems: 2, persistence: persistence)
        XCTAssertEqual(reloadedStore.items.filter { $0.imageValue != nil }.count, 2)
        XCTAssertTrue(reloadedStore.items.contains { $0.textValue == "keep me" })
    }

    func testRestoreWritesToPasteboard() {
        let store = ClipboardStore()

        store.restore(.text("hello"))

        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "hello")
    }

    func testImageItemAdded() {
        let store = ClipboardStore()
        let image = NSImage.onePixelTestImage()

        store.add(.image(ClipboardImage(image)))

        XCTAssertEqual(store.items.count, 1)
        if case .image = store.items[0] {
            XCTAssertNotNil(store.items[0].imageValue)
        } else {
            XCTFail("Expected image item")
        }
    }

    func testPersistentTextHistoryReloads() throws {
        let persistence = try makeTemporaryPersistence()
        let firstStore = ClipboardStore(persistence: persistence)

        firstStore.add(.text("persist me"))

        let reloadedStore = ClipboardStore(persistence: persistence)
        XCTAssertEqual(reloadedStore.items.count, 1)
        XCTAssertEqual(reloadedStore.items[0].textValue, "persist me")
    }

    func testPersistentImageHistoryReloads() throws {
        let persistence = try makeTemporaryPersistence()
        let firstStore = ClipboardStore(persistence: persistence)

        firstStore.add(.image(.onePixelTestImage()))

        let reloadedStore = ClipboardStore(persistence: persistence)
        XCTAssertEqual(reloadedStore.items.count, 1)
        XCTAssertNotNil(reloadedStore.items[0].imageValue)
    }

    func testPersistentImageHistoryStoresPayloadOutsideJSON() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let persistence = ClipboardHistoryPersistence(fileURL: fileURL)

        persistence.saveItems([.image(.onePixelTestImage())])

        let historyData = try Data(contentsOf: fileURL)
        let historyText = String(decoding: historyData, as: UTF8.self)
        let imageFiles = try FileManager.default.contentsOfDirectory(
            at: directoryURL.appendingPathComponent("Images", isDirectory: true),
            includingPropertiesForKeys: nil
        )

        XCTAssertTrue(historyText.contains("\"version\" : 2"))
        XCTAssertTrue(historyText.contains("\"imageFileName\""))
        XCTAssertFalse(historyText.contains("\"imageData\""))
        XCTAssertEqual(imageFiles.count, 1)
    }

    func testPersistentImageHistoryLoadsLegacyInlineImageData() throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let imageData = try XCTUnwrap(NSImage.onePixelTestImage().tiffRepresentation)
        let itemID = UUID()
        let timestamp = "2026-04-25T12:00:00Z"
        let legacyJSON = """
        {
          "version": 1,
          "items": [
            {
              "kind": "image",
              "id": "\(itemID.uuidString)",
              "timestamp": "\(timestamp)",
              "imageData": "\(imageData.base64EncodedString())",
              "imageEncoding": "tiff"
            }
          ]
        }
        """
        try legacyJSON.data(using: .utf8)!.write(to: fileURL)
        let persistence = ClipboardHistoryPersistence(fileURL: fileURL)

        let loadedItems = persistence.loadItems()
        persistence.saveItems(loadedItems)

        let migratedHistory = String(decoding: try Data(contentsOf: fileURL), as: UTF8.self)
        let imageFiles = try FileManager.default.contentsOfDirectory(
            at: directoryURL.appendingPathComponent("Images", isDirectory: true),
            includingPropertiesForKeys: nil
        )

        XCTAssertEqual(loadedItems.count, 1)
        XCTAssertNotNil(loadedItems[0].imageValue)
        XCTAssertTrue(migratedHistory.contains("\"version\" : 2"))
        XCTAssertTrue(migratedHistory.contains("\"imageFileName\""))
        XCTAssertFalse(migratedHistory.contains("\"imageData\""))
        XCTAssertEqual(imageFiles.count, 1)
    }

    func testClearPersistsEmptyHistory() throws {
        let persistence = try makeTemporaryPersistence()
        let firstStore = ClipboardStore(persistence: persistence)

        firstStore.add(.text("remove me"))
        firstStore.clear()

        let reloadedStore = ClipboardStore(persistence: persistence)
        XCTAssertTrue(reloadedStore.items.isEmpty)
    }

    func testRemoveDeletesItemAndPersistsHistory() throws {
        let persistence = try makeTemporaryPersistence()
        let removedItem = ClipboardItem.text("remove me")
        let keptItem = ClipboardItem.text("keep me")
        let firstStore = ClipboardStore(persistence: persistence)

        firstStore.add(keptItem)
        firstStore.add(removedItem)
        firstStore.remove(id: removedItem.id)

        XCTAssertEqual(firstStore.items.map(\.id), [keptItem.id])

        let reloadedStore = ClipboardStore(persistence: persistence)
        XCTAssertEqual(reloadedStore.items.map(\.id), [keptItem.id])
        XCTAssertFalse(reloadedStore.items.contains { $0.id == removedItem.id })
    }

    func testRemoveUpdatesSemanticIndexAndActiveSearchResults() async throws {
        let semanticIndex = TestSemanticIndex()
        let removedItem = ClipboardItem.text("invoice to remove")
        let keptItem = ClipboardItem.text("invoice to keep")
        let store = ClipboardStore(semanticIndex: semanticIndex)

        store.add(keptItem)
        store.add(removedItem)
        store.searchQuery = "invoice"

        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(Set(store.searchResults.map(\.id)), Set([removedItem.id, keptItem.id]))

        store.remove(id: removedItem.id)

        XCTAssertEqual(store.searchResults.map(\.id), [keptItem.id])

        try await Task.sleep(nanoseconds: 50_000_000)
        let removedIDs = await semanticIndex.removedIDs
        XCTAssertTrue(removedIDs.contains(removedItem.id))
    }

    func testPersistentHistoryUsesOwnerOnlyFilePermissions() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStackPermissionTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileURL = directoryURL.appendingPathComponent("history.json")
        let persistence = ClipboardHistoryPersistence(fileURL: fileURL)

        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        persistence.saveItems([.text("secure history")])

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)

        let dirAttrs = try FileManager.default.attributesOfItem(atPath: directoryURL.path)
        XCTAssertEqual((dirAttrs[.posixPermissions] as? NSNumber)?.intValue, 0o700)
    }

    private func makeTemporaryPersistence() throws -> ClipboardHistoryPersistence {
        let directoryURL = try makeTemporaryDirectory()

        return ClipboardHistoryPersistence(fileURL: directoryURL.appendingPathComponent("history.json"))
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClipStackTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        return directoryURL
    }
}

private actor TestSemanticIndex: SemanticIndexing {
    private(set) var removedIDs: [UUID] = []

    func rebuild(items: [(id: UUID, text: String)]) async {}

    func add(id: UUID, text: String) async {}

    func remove(id: UUID) async {
        removedIDs.append(id)
    }

    func clear() async {}

    func search(query: String, allItems: [ClipboardItem]) async -> [ClipboardItem] {
        allItems.filter { item in
            item.textValue?.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
        }
    }
}

extension NSImage {
    static func onePixelTestImage(color: NSColor = .black) -> NSImage {
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        color.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        return image
    }
}

extension ClipboardImage {
    static func onePixelTestImage(color: NSColor = .black) -> ClipboardImage {
        ClipboardImage(NSImage.onePixelTestImage(color: color))
    }
}
