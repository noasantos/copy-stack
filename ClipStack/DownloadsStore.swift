import Combine
import Foundation

@MainActor
final class DownloadsStore: ObservableObject {
    struct DownloadCandidate: Sendable {
        let url: URL
        let isRegularFile: Bool
        let isDirectory: Bool
        let isPackage: Bool
        let isHidden: Bool
        let creationDate: Date?
        let contentModificationDate: Date?
        let fileSize: Int64?
        let fileResourceIdentifier: String?

        init(
            url: URL,
            isRegularFile: Bool = true,
            isDirectory: Bool = false,
            isPackage: Bool = false,
            isHidden: Bool = false,
            creationDate: Date? = nil,
            contentModificationDate: Date? = nil,
            fileSize: Int64? = nil,
            fileResourceIdentifier: String? = nil
        ) {
            self.url = url
            self.isRegularFile = isRegularFile
            self.isDirectory = isDirectory
            self.isPackage = isPackage
            self.isHidden = isHidden
            self.creationDate = creationDate
            self.contentModificationDate = contentModificationDate
            self.fileSize = fileSize
            self.fileResourceIdentifier = fileResourceIdentifier
        }
    }

    nonisolated static let recentInterval: TimeInterval = 60 * 60

    @Published private(set) var items: [DownloadItem] = []

    private let directoryURL: URL
    private let fileManager: FileManager
    private let currentDate: () -> Date
    private var cleanupTask: Task<Void, Never>?
    private var clearedItemIDs = Set<String>()

    init(
        directoryURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!,
        fileManager: FileManager = .default,
        currentDate: @escaping () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL
        self.fileManager = fileManager
        self.currentDate = currentDate
    }

    deinit {
        cleanupTask?.cancel()
    }

    func refresh() {
        items = Self.downloadItems(from: scanDirectory(), now: currentDate())
            .filter { !clearedItemIDs.contains($0.id) }
        scheduleCleanup()
    }

    func pruneExpiredItemsAndMissingFiles() {
        let now = currentDate()
        items = items.filter { item in
            now.timeIntervalSince(item.activityDate) <= Self.recentInterval
                && fileManager.fileExists(atPath: item.url.path)
        }
        scheduleCleanup()
    }

    func clear() {
        clearedItemIDs.formUnion(items.map(\.id))
        items.removeAll()
        scheduleCleanup()
    }

    nonisolated static func downloadItems(
        from candidates: [DownloadCandidate],
        now: Date = Date(),
        recentInterval: TimeInterval = recentInterval
    ) -> [DownloadItem] {
        var itemsByID: [String: DownloadItem] = [:]

        for candidate in candidates {
            guard candidate.isRegularFile,
                  !candidate.isDirectory,
                  !candidate.isPackage,
                  !candidate.isHidden,
                  !isTemporaryDownload(candidate.url),
                  let activityDate = activityDate(for: candidate) else {
                continue
            }

            let age = now.timeIntervalSince(activityDate)
            guard age >= 0, age <= recentInterval else {
                continue
            }

            let id = candidate.fileResourceIdentifier ?? candidate.url.path
            let item = DownloadItem(
                id: id,
                url: candidate.url,
                displayName: candidate.url.lastPathComponent,
                activityDate: activityDate,
                fileSize: candidate.fileSize
            )

            if let existingItem = itemsByID[id], existingItem.activityDate >= item.activityDate {
                continue
            }

            itemsByID[id] = item
        }

        return itemsByID.values.sorted { lhs, rhs in
            if lhs.activityDate == rhs.activityDate {
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }

            return lhs.activityDate > rhs.activityDate
        }
    }

    private func scanDirectory() -> [DownloadCandidate] {
        let resourceKeys: Set<URLResourceKey> = [
            .creationDateKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey,
            .fileSizeKey,
            .isDirectoryKey,
            .isHiddenKey,
            .isPackageKey,
            .isRegularFileKey
        ]

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        ) else {
            return []
        }

        return fileURLs.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                return nil
            }

            return DownloadCandidate(
                url: url,
                isRegularFile: values.isRegularFile == true,
                isDirectory: values.isDirectory == true,
                isPackage: values.isPackage == true,
                isHidden: values.isHidden == true,
                creationDate: values.creationDate,
                contentModificationDate: values.contentModificationDate,
                fileSize: values.fileSize.map(Int64.init),
                fileResourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
            )
        }
    }

    nonisolated private static func activityDate(for candidate: DownloadCandidate) -> Date? {
        switch (candidate.creationDate, candidate.contentModificationDate) {
        case (.some(let creationDate), .some(let modificationDate)):
            return max(creationDate, modificationDate)
        case (.some(let creationDate), .none):
            return creationDate
        case (.none, .some(let modificationDate)):
            return modificationDate
        case (.none, .none):
            return nil
        }
    }

    nonisolated private static func isTemporaryDownload(_ url: URL) -> Bool {
        temporaryDownloadExtensions.contains(url.pathExtension.lowercased())
    }

    private func scheduleCleanup() {
        cleanupTask?.cancel()

        guard let nextExpirationDate = items
            .map({ $0.activityDate.addingTimeInterval(Self.recentInterval) })
            .filter({ $0 > currentDate() })
            .min() else {
            cleanupTask = nil
            return
        }

        cleanupTask = Task { [weak self, nextExpirationDate] in
            let delay = max(0, nextExpirationDate.timeIntervalSince(Date()))
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else {
                return
            }

            await self?.pruneExpiredItemsAndMissingFiles()
        }
    }

    nonisolated private static let temporaryDownloadExtensions: Set<String> = [
        "crdownload",
        "download",
        "filepart",
        "opdownload",
        "part",
        "partial",
        "tmp"
    ]
}
