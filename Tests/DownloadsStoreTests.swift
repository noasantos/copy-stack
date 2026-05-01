@testable import ClipStack
import Foundation
import XCTest

@MainActor
final class DownloadsStoreTests: XCTestCase {
    func testRecentFileIsAccepted() {
        let now = Date(timeIntervalSince1970: 1_000)
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        let candidates = [
            DownloadsStore.DownloadCandidate(
                url: url,
                creationDate: now.addingTimeInterval(-30),
                contentModificationDate: now.addingTimeInterval(-20),
                fileSize: 42
            )
        ]

        let items = DownloadsStore.downloadItems(from: candidates, now: now)

        XCTAssertEqual(items, [
            DownloadItem(
                id: url.path,
                url: url,
                displayName: "report.pdf",
                activityDate: now.addingTimeInterval(-20),
                fileSize: 42
            )
        ])
    }

    func testOldFileIsRejected() {
        let now = Date(timeIntervalSince1970: 5_000)
        let candidates = [
            DownloadsStore.DownloadCandidate(
                url: URL(fileURLWithPath: "/tmp/old.pdf"),
                creationDate: now.addingTimeInterval(-3_601)
            )
        ]

        XCTAssertTrue(DownloadsStore.downloadItems(from: candidates, now: now).isEmpty)
    }

    func testDirectoryIsRejected() {
        let now = Date(timeIntervalSince1970: 1_000)
        let candidates = [
            DownloadsStore.DownloadCandidate(
                url: URL(fileURLWithPath: "/tmp/folder"),
                isRegularFile: false,
                isDirectory: true,
                creationDate: now
            )
        ]

        XCTAssertTrue(DownloadsStore.downloadItems(from: candidates, now: now).isEmpty)
    }

    func testPackageAndSafariDownloadPackageAreRejected() {
        let now = Date(timeIntervalSince1970: 1_000)
        let candidates = [
            DownloadsStore.DownloadCandidate(
                url: URL(fileURLWithPath: "/tmp/App.app"),
                isRegularFile: false,
                isDirectory: true,
                isPackage: true,
                creationDate: now
            ),
            DownloadsStore.DownloadCandidate(
                url: URL(fileURLWithPath: "/tmp/archive.zip.download"),
                isRegularFile: false,
                isDirectory: true,
                isPackage: true,
                creationDate: now
            )
        ]

        XCTAssertTrue(DownloadsStore.downloadItems(from: candidates, now: now).isEmpty)
    }

    func testTemporaryDownloadExtensionsAreRejected() {
        let now = Date(timeIntervalSince1970: 1_000)
        let extensions = ["crdownload", "download", "part", "partial", "tmp", "opdownload", "filepart"]
        let candidates = extensions.map { fileExtension in
            DownloadsStore.DownloadCandidate(
                url: URL(fileURLWithPath: "/tmp/file.\(fileExtension)"),
                creationDate: now
            )
        }

        XCTAssertTrue(DownloadsStore.downloadItems(from: candidates, now: now).isEmpty)
    }

    func testHiddenFileIsRejected() {
        let now = Date(timeIntervalSince1970: 1_000)
        let candidates = [
            DownloadsStore.DownloadCandidate(
                url: URL(fileURLWithPath: "/tmp/.hidden"),
                isHidden: true,
                creationDate: now
            )
        ]

        XCTAssertTrue(DownloadsStore.downloadItems(from: candidates, now: now).isEmpty)
    }

    func testItemsAreSortedNewestFirst() {
        let now = Date(timeIntervalSince1970: 1_000)
        let oldestURL = URL(fileURLWithPath: "/tmp/oldest.pdf")
        let newestURL = URL(fileURLWithPath: "/tmp/newest.pdf")
        let candidates = [
            DownloadsStore.DownloadCandidate(url: oldestURL, creationDate: now.addingTimeInterval(-50)),
            DownloadsStore.DownloadCandidate(url: newestURL, creationDate: now.addingTimeInterval(-10))
        ]

        let items = DownloadsStore.downloadItems(from: candidates, now: now)

        XCTAssertEqual(items.map(\.url), [newestURL, oldestURL])
    }

    func testItemsAreDeduplicatedByIdentity() {
        let now = Date(timeIntervalSince1970: 1_000)
        let olderURL = URL(fileURLWithPath: "/tmp/older-name.pdf")
        let newerURL = URL(fileURLWithPath: "/tmp/newer-name.pdf")
        let candidates = [
            DownloadsStore.DownloadCandidate(
                url: olderURL,
                creationDate: now.addingTimeInterval(-30),
                fileResourceIdentifier: "stable-id"
            ),
            DownloadsStore.DownloadCandidate(
                url: newerURL,
                creationDate: now.addingTimeInterval(-10),
                fileResourceIdentifier: "stable-id"
            )
        ]

        let items = DownloadsStore.downloadItems(from: candidates, now: now)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].url, newerURL)
        XCTAssertEqual(items[0].id, "stable-id")
    }

    func testItemsAreDeduplicatedByFallbackPath() {
        let now = Date(timeIntervalSince1970: 1_000)
        let url = URL(fileURLWithPath: "/tmp/same.pdf")
        let candidates = [
            DownloadsStore.DownloadCandidate(url: url, creationDate: now.addingTimeInterval(-30)),
            DownloadsStore.DownloadCandidate(url: url, creationDate: now.addingTimeInterval(-10))
        ]

        let items = DownloadsStore.downloadItems(from: candidates, now: now)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].id, url.path)
        XCTAssertEqual(items[0].activityDate, now.addingTimeInterval(-10))
    }

    func testExpirationAfterOneHour() throws {
        var now = Date()
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recent.pdf")
        try Data("recent".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.creationDate: now, .modificationDate: now],
            ofItemAtPath: fileURL.path
        )
        let store = DownloadsStore(directoryURL: directoryURL, currentDate: { now })

        store.refresh()
        XCTAssertEqual(store.items.count, 1)

        now = now.addingTimeInterval(3_601)
        store.pruneExpiredItemsAndMissingFiles()

        XCTAssertTrue(store.items.isEmpty)
    }

    func testMissingFileCleanup() throws {
        let now = Date()
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("deleted.pdf")
        try Data("deleted".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.creationDate: now, .modificationDate: now],
            ofItemAtPath: fileURL.path
        )
        let store = DownloadsStore(directoryURL: directoryURL, currentDate: { now })

        store.refresh()
        XCTAssertEqual(store.items.count, 1)

        try FileManager.default.removeItem(at: fileURL)
        store.pruneExpiredItemsAndMissingFiles()

        XCTAssertTrue(store.items.isEmpty)
    }

    func testClearRemovesItemsWithoutDeletingFilesAndSuppressesRescan() throws {
        let now = Date()
        let directoryURL = try makeTemporaryDirectory()
        let fileURL = directoryURL.appendingPathComponent("recent.pdf")
        try Data("recent".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.creationDate: now, .modificationDate: now],
            ofItemAtPath: fileURL.path
        )
        let store = DownloadsStore(directoryURL: directoryURL, currentDate: { now })

        store.refresh()
        XCTAssertEqual(store.items.count, 1)

        store.clear()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))

        store.refresh()
        XCTAssertTrue(store.items.isEmpty)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DownloadsStoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directoryURL)
        }

        return directoryURL
    }
}
