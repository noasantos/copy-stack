import AppKit
import Foundation
import os

private let logger = Logger(subsystem: "com.startapse.ClipStack", category: "persistence")

protocol ClipboardHistoryPersisting {
    func loadItems() -> [ClipboardItem]
    func saveItems(_ items: [ClipboardItem])
}

struct ClipboardHistoryPersistence: ClipboardHistoryPersisting {
    private struct StoredHistory: Codable {
        let version: Int
        let items: [StoredItem]
    }

    fileprivate struct StoredItem: Codable {
        enum Kind: String, Codable {
            case text
            case image
        }

        enum ImageEncoding: String, Codable {
            case png
            case tiff
        }

        let kind: Kind
        let id: UUID
        let timestamp: Date
        let text: String?
        let imageData: Data?
        let imageEncoding: ImageEncoding?
        let imageFileName: String?
    }

    private static let currentHistoryVersion = 2

    private let fileURL: URL
    private let fileManager: FileManager
    private var imageDirectoryURL: URL {
        fileURL.deletingLastPathComponent().appendingPathComponent("Images", isDirectory: true)
    }

    init(fileURL: URL, fileManager: FileManager = .default) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    static func applicationSupport(fileManager: FileManager = .default) -> ClipboardHistoryPersistence {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return ClipboardHistoryPersistence(
            fileURL: baseURL
                .appendingPathComponent("ClipStack", isDirectory: true)
                .appendingPathComponent("history.json"),
            fileManager: fileManager
        )
    }

    func loadItems() -> [ClipboardItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let history = try decoder.decode(StoredHistory.self, from: data)
            return migrate(from: history).compactMap(makeClipboardItem(from:))
        } catch {
            logger.error("ClipStack failed to load clipboard history: \(error, privacy: .private)")
            return []
        }
    }

    func saveItems(_ items: [ClipboardItem]) {
        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(
                at: imageDirectoryURL,
                withIntermediateDirectories: true
            )
            setOwnerOnlyDirectoryPermissions()

            let storedItems = items.compactMap(makeStoredItem(from:))
            let history = StoredHistory(version: Self.currentHistoryVersion, items: storedItems)

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: [.atomic])
            setOwnerOnlyFilePermissions()
            removeOrphanedImageFiles(keeping: Set(storedItems.compactMap(\.imageFileName)))
        } catch {
            logger.error("ClipStack failed to save clipboard history: \(error, privacy: .private)")
        }
    }

    private func migrate(from history: StoredHistory) -> [StoredItem] {
        switch history.version {
        case 1, Self.currentHistoryVersion:
            return history.items
        case ..<1:
            backupHistoryFile()
            logger.warning("ClipStack refusing to load clipboard history with unsupported version \(history.version, privacy: .public)")
            return []
        default:
            backupHistoryFile()
            logger.warning("ClipStack refusing to load clipboard history with unsupported version \(history.version, privacy: .public)")
            return []
        }
    }

    private func backupHistoryFile() {
        let backupURL = fileURL.deletingLastPathComponent().appendingPathComponent("\(fileURL.lastPathComponent).bak")

        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }

            try fileManager.copyItem(at: fileURL, to: backupURL)
        } catch {
            logger.warning("ClipStack failed to back up clipboard history before migration: \(error, privacy: .private)")
        }
    }

    private func setOwnerOnlyDirectoryPermissions() {
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: fileURL.deletingLastPathComponent().path
            )
            if fileManager.fileExists(atPath: imageDirectoryURL.path) {
                try fileManager.setAttributes(
                    [.posixPermissions: 0o700],
                    ofItemAtPath: imageDirectoryURL.path
                )
            }
        } catch {
            logger.warning("ClipStack failed to restrict clipboard history directory permissions: \(error, privacy: .private)")
        }
    }

    private func setOwnerOnlyFilePermissions() {
        do {
            try fileManager.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: fileURL.path
            )
        } catch {
            logger.warning("ClipStack failed to restrict clipboard history file permissions: \(error, privacy: .private)")
        }
    }

    private func setOwnerOnlyImageFilePermissions(_ url: URL) {
        do {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            logger.warning("ClipStack failed to restrict clipboard image file permissions: \(error, privacy: .private)")
        }
    }

    private func removeOrphanedImageFiles(keeping fileNames: Set<String>) {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: imageDirectoryURL,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        for url in urls where !fileNames.contains(url.lastPathComponent) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                logger.warning("ClipStack failed to remove orphaned clipboard image file: \(error, privacy: .private)")
            }
        }
    }

    private func makeClipboardItem(from storedItem: StoredItem) -> ClipboardItem? {
        switch storedItem.kind {
        case .text:
            guard let text = storedItem.text else {
                return nil
            }
            return .text(text, id: storedItem.id, timestamp: storedItem.timestamp)
        case .image:
            if let imageFileName = storedItem.imageFileName,
               let image = ClipboardImage.make(fileURL: imageDirectoryURL.appendingPathComponent(imageFileName)) {
                return .image(image, id: storedItem.id, timestamp: storedItem.timestamp)
            }

            guard let imageData = storedItem.imageData,
                  let image = ClipboardImage.make(
                    data: imageData,
                    encoding: storedItem.imageEncoding.map(\.clipboardImageEncoding)
                  ) else {
                return nil
            }
            return .image(image, id: storedItem.id, timestamp: storedItem.timestamp)
        }
    }

    private func makeStoredItem(from item: ClipboardItem) -> StoredItem? {
        switch item {
        case .text(let text, id: let id, timestamp: let timestamp):
            return StoredItem(
                kind: .text,
                id: id,
                timestamp: timestamp,
                text: text,
                imageData: nil,
                imageEncoding: nil,
                imageFileName: nil
            )
        case .image(let image, id: let id, timestamp: let timestamp):
            guard let fileName = persistImagePayload(image, id: id) else {
                return nil
            }

            return StoredItem(
                kind: .image,
                id: id,
                timestamp: timestamp,
                text: nil,
                imageData: nil,
                imageEncoding: image.encoding.map(Self.StoredItem.ImageEncoding.init),
                imageFileName: fileName
            )
        }
    }

    private func persistImagePayload(_ image: ClipboardImage, id: UUID) -> String? {
        guard let data = image.payloadData() else {
            return nil
        }

        let fileName = "\(id.uuidString).\(image.encoding?.rawValue ?? "png")"
        let targetURL = imageDirectoryURL.appendingPathComponent(fileName)

        do {
            try data.write(to: targetURL, options: [.atomic])
            setOwnerOnlyImageFilePermissions(targetURL)
            return fileName
        } catch {
            logger.warning("ClipStack failed to save clipboard image payload: \(error, privacy: .private)")
            return nil
        }
    }
}

private extension ClipboardHistoryPersistence.StoredItem.ImageEncoding {
    init(_ encoding: ClipboardImageEncoding) {
        switch encoding {
        case .png:
            self = .png
        case .tiff:
            self = .tiff
        }
    }

    var clipboardImageEncoding: ClipboardImageEncoding {
        switch self {
        case .png:
            return .png
        case .tiff:
            return .tiff
        }
    }
}
