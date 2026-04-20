import AppKit
import Darwin
import Foundation
import ImageIO
import os
@preconcurrency import UserNotifications

private let logger = Logger(subsystem: "com.startapse.ClipStack", category: "screenshot-watcher")
private let maxScreenshotFileSizeBytes = 50 * 1024 * 1024
private let maxScreenshotPixelDimension = 16_384

final class ScreenshotWatcher {
    struct ScreenshotCandidate {
        let url: URL
        let creationDate: Date
    }

    private enum ScreenshotLoadResult: Sendable {
        case loaded(Data)
        case skipped
        case failed
    }

    static let recentScreenshotInterval: TimeInterval = 3

    private let directoryURL: URL
    private let store: ClipboardStore
    private let queue = DispatchQueue(label: "com.startapse.ClipStack.screenshot-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var processedFileIdentifiers = Set<String>()

    init(
        store: ClipboardStore,
        directoryURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    ) {
        self.store = store
        self.directoryURL = directoryURL
    }

    deinit {
        stop()
    }

    func start() {
        stop()

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        fileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .attrib, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scanForRecentScreenshots()
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    static func filterRecentScreenshotFiles(
        _ candidates: [ScreenshotCandidate],
        now: Date = Date(),
        within interval: TimeInterval = recentScreenshotInterval
    ) -> [URL] {
        candidates
            .filter { candidate in
                isScreenshotFile(candidate.url) && now.timeIntervalSince(candidate.creationDate) >= 0 && now.timeIntervalSince(candidate.creationDate) <= interval
            }
            .map(\.url)
    }

    static func isScreenshotFile(_ url: URL) -> Bool {
        let fileName = url.lastPathComponent
        let lowercasedExtension = url.pathExtension.lowercased()

        guard lowercasedExtension == "png" else {
            return false
        }

        return fileName.hasPrefix("Screenshot") || fileName.hasPrefix("Screen Shot")
    }

    private func scanForRecentScreenshots() {
        let resourceKeys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey, .isRegularFileKey, .fileResourceIdentifierKey]
        let fileURLs: [URL]

        do {
            fileURLs = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles]
            )
        } catch {
            return
        }

        let candidates = fileURLs.compactMap { url -> ScreenshotCandidate? in
            guard let values = try? url.resourceValues(forKeys: resourceKeys), values.isRegularFile == true else {
                return nil
            }

            guard let date = values.creationDate ?? values.contentModificationDate else {
                return nil
            }

            return ScreenshotCandidate(url: url, creationDate: date)
        }

        let screenshotURLs = Self.filterRecentScreenshotFiles(candidates)

        for url in screenshotURLs {
            let identifier = fileIdentifier(for: url)
            guard !processedFileIdentifiers.contains(identifier) else {
                continue
            }

            processedFileIdentifiers.insert(identifier)
            copyScreenshot(at: url)
        }
    }

    private func fileIdentifier(for url: URL) -> String {
        if let values = try? url.resourceValues(forKeys: [.fileResourceIdentifierKey]), let identifier = values.fileResourceIdentifier {
            return String(describing: identifier)
        }

        return url.path
    }

    @discardableResult
    func copyScreenshot(at url: URL) -> Task<Void, Never> {
        let store = store

        return Task { @MainActor [store, url] in
            let loadResult = await Self.loadScreenshotDataIfSafe(at: url)

            guard case .loaded(let data) = loadResult else {
                if case .failed = loadResult {
                    logger.warning("ClipStack failed to load screenshot image")
                }
                return
            }

            guard let image = NSImage(data: data) else {
                logger.warning("ClipStack failed to load screenshot image")
                return
            }

            store.copyScreenshotImageToPasteboardAndHistory(image)
            Self.postScreenshotNotification()
        }
    }

    private static func loadScreenshotDataIfSafe(at url: URL) async -> ScreenshotLoadResult {
        await Task.detached {
            guard Self.isSafeScreenshotFile(at: url) else {
                return .skipped
            }

            guard let data = try? Data(contentsOf: url) else {
                return .failed
            }

            return .loaded(data)
        }.value
    }

    static func isSafeScreenshotFile(at url: URL) -> Bool {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize, fileSize > maxScreenshotFileSizeBytes {
                logger.warning("ClipStack skipped oversized screenshot file")
                return false
            }
        } catch {
            logger.warning("ClipStack failed to read screenshot file size: \(error, privacy: .private)")
            return false
        }

        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            logger.warning("ClipStack skipped malformed screenshot image")
            return false
        }

        guard width <= maxScreenshotPixelDimension, height <= maxScreenshotPixelDimension else {
            logger.warning("ClipStack skipped screenshot with oversized pixel dimensions")
            return false
        }

        return true
    }

    @MainActor
    private static func postScreenshotNotification() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                return
            }

            let content = UNMutableNotificationContent()
            content.title = "Screenshot copied to clipboard"
            content.body = "The latest screenshot image is ready to paste."

            let request = UNNotificationRequest(
                identifier: "clipstack.screenshot.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }
}
