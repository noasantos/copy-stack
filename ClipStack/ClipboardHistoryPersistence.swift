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
    }

    private let fileURL: URL
    private let fileManager: FileManager

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
            return migrate(from: history).compactMap(Self.makeClipboardItem(from:))
        } catch {
            logger.error("ClipStack failed to load clipboard history: \(error, privacy: .private)")
            return []
        }
    }

    func saveItems(_ items: [ClipboardItem]) {
        let storedItems = items.compactMap(Self.makeStoredItem(from:))
        let history = StoredHistory(version: 1, items: storedItems)

        do {
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            setOwnerOnlyDirectoryPermissions()

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(history)
            try data.write(to: fileURL, options: [.atomic])
            setOwnerOnlyFilePermissions()
        } catch {
            logger.error("ClipStack failed to save clipboard history: \(error, privacy: .private)")
        }
    }

    private func migrate(from history: StoredHistory) -> [StoredItem] {
        switch history.version {
        case 1:
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

    private static func makeClipboardItem(from storedItem: StoredItem) -> ClipboardItem? {
        switch storedItem.kind {
        case .text:
            guard let text = storedItem.text else {
                return nil
            }
            return .text(text, id: storedItem.id, timestamp: storedItem.timestamp)
        case .image:
            guard let imageData = storedItem.imageData, let image = NSImage(data: imageData) else {
                return nil
            }
            return .image(image, id: storedItem.id, timestamp: storedItem.timestamp)
        }
    }

    private static func makeStoredItem(from item: ClipboardItem) -> StoredItem? {
        switch item {
        case .text(let text, id: let id, timestamp: let timestamp):
            return StoredItem(
                kind: .text,
                id: id,
                timestamp: timestamp,
                text: text,
                imageData: nil,
                imageEncoding: nil
            )
        case .image(let image, id: let id, timestamp: let timestamp):
            guard let encodedImage = image.persistentImageData() else {
                return nil
            }

            return StoredItem(
                kind: .image,
                id: id,
                timestamp: timestamp,
                text: nil,
                imageData: encodedImage.data,
                imageEncoding: encodedImage.encoding
            )
        }
    }
}

private extension NSImage {
    func persistentImageData() -> (data: Data, encoding: ClipboardHistoryPersistence.StoredItem.ImageEncoding)? {
        guard let tiffData = tiffRepresentation else {
            return nil
        }

        if let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            return (pngData, .png)
        }

        return (tiffData, .tiff)
    }
}
