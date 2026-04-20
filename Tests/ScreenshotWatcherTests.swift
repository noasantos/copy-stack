@testable import ClipStack
import AppKit
import Foundation
import XCTest

@MainActor
final class ScreenshotWatcherTests: XCTestCase {
    func testFiltersRecentScreenshot() {
        let now = Date()
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-04-20 at 12.00.00.png")
        let candidates = [ScreenshotWatcher.ScreenshotCandidate(url: url, creationDate: now.addingTimeInterval(-1))]

        let result = ScreenshotWatcher.filterRecentScreenshotFiles(candidates, now: now)

        XCTAssertEqual(result, [url])
    }

    func testFiltersTooOldScreenshot() {
        let now = Date()
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-04-20 at 12.00.00.png")
        let candidates = [ScreenshotWatcher.ScreenshotCandidate(url: url, creationDate: now.addingTimeInterval(-10))]

        let result = ScreenshotWatcher.filterRecentScreenshotFiles(candidates, now: now)

        XCTAssertTrue(result.isEmpty)
    }

    func testFiltersNonPNGFile() {
        let now = Date()
        let url = URL(fileURLWithPath: "/tmp/Screenshot 2026-04-20 at 12.00.00.jpg")
        let candidates = [ScreenshotWatcher.ScreenshotCandidate(url: url, creationDate: now.addingTimeInterval(-1))]

        let result = ScreenshotWatcher.filterRecentScreenshotFiles(candidates, now: now)

        XCTAssertTrue(result.isEmpty)
    }

    func testFiltersWrongFilenamePrefix() {
        let now = Date()
        let url = URL(fileURLWithPath: "/tmp/Photo 2026-04-20.png")
        let candidates = [ScreenshotWatcher.ScreenshotCandidate(url: url, creationDate: now.addingTimeInterval(-1))]

        let result = ScreenshotWatcher.filterRecentScreenshotFiles(candidates, now: now)

        XCTAssertTrue(result.isEmpty)
    }

    func testAcceptsLegacyScreenShotPrefix() {
        let now = Date()
        let url = URL(fileURLWithPath: "/tmp/Screen Shot 2026-04-20 at 12.00.00.png")
        let candidates = [ScreenshotWatcher.ScreenshotCandidate(url: url, creationDate: now.addingTimeInterval(-1))]

        let result = ScreenshotWatcher.filterRecentScreenshotFiles(candidates, now: now)

        XCTAssertEqual(result, [url])
    }

    func testCopyScreenshotRejectsMalformedPNG() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("Screenshot 2026-01-01 at 12.00.00.png")
        try Data("not a png".utf8).write(to: fileURL)
        let store = ClipboardStore()
        let watcher = ScreenshotWatcher(store: store, directoryURL: directoryURL)

        let task = watcher.copyScreenshot(at: fileURL)
        await task.value

        XCTAssertTrue(store.items.isEmpty)
    }

    func testCopyScreenshotRejectsOversizedPNG() async throws {
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("Screenshot 2026-01-01 at 12.00.01.png")
        FileManager.default.createFile(atPath: fileURL.path, contents: Data())
        let handle = try FileHandle(forWritingTo: fileURL)
        handle.truncateFile(atOffset: UInt64(50 * 1024 * 1024 + 1))
        handle.closeFile()
        let store = ClipboardStore()
        let watcher = ScreenshotWatcher(store: store, directoryURL: directoryURL)

        let task = watcher.copyScreenshot(at: fileURL)
        await task.value

        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScreenshotWatcherTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        return directoryURL
    }
}
