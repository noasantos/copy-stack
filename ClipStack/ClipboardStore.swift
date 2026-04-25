import AppKit
import Combine
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    nonisolated static let defaultMaxItems = 1_000
    nonisolated static let defaultMaxImageItems = 25

    @Published private(set) var items: [ClipboardItem] = []
    @Published private(set) var searchResults: [ClipboardItem] = []
    @Published var searchQuery: String = "" {
        didSet {
            scheduleSearch()
        }
    }

    private let pasteboard: NSPasteboard
    private let maxItems: Int
    private let maxImageItems: Int
    private let persistence: ClipboardHistoryPersisting?
    private let semanticIndex: any SemanticIndexing
    private var searchTask: Task<Void, Never>?

    var isSelfWriting = false

    init(
        maxItems: Int = ClipboardStore.defaultMaxItems,
        maxImageItems: Int = ClipboardStore.defaultMaxImageItems,
        pasteboard: NSPasteboard = .general,
        persistence: ClipboardHistoryPersisting? = nil,
        semanticIndex: any SemanticIndexing = SemanticIndex()
    ) {
        self.maxItems = maxItems
        self.maxImageItems = maxImageItems
        self.pasteboard = pasteboard
        self.persistence = persistence
        self.semanticIndex = semanticIndex
        self.items = Self.prunedItems(persistence?.loadItems() ?? [], maxItems: maxItems, maxImageItems: maxImageItems)
        rebuildSemanticIndex()
    }

    func add(_ item: ClipboardItem) {
        let previousIDs = Set(items.map(\.id))

        if case .text(let text, id: _, timestamp: let timestamp) = item,
           let existingIndex = items.firstIndex(where: { $0.textValue == text }) {
            let existingID = items[existingIndex].id
            items.remove(at: existingIndex)
            items.insert(.text(text, id: existingID, timestamp: timestamp), at: 0)
            items = Self.prunedItems(items, maxItems: maxItems, maxImageItems: maxImageItems)
            persist()
            syncSemanticIndex(addedItem: items.first, removedIDs: previousIDs.subtracting(Set(items.map(\.id))))
            scheduleSearchIfNeeded()
            return
        }

        items.removeAll { $0.isDuplicate(of: item) }
        items.insert(item, at: 0)
        items = Self.prunedItems(items, maxItems: maxItems, maxImageItems: maxImageItems)

        persist()
        let currentIDs = Set(items.map(\.id))
        let addedItem = currentIDs.contains(item.id) ? item : nil
        syncSemanticIndex(addedItem: addedItem, removedIDs: previousIDs.subtracting(currentIDs))
        scheduleSearchIfNeeded()
    }

    func clear() {
        items.removeAll()
        searchResults.removeAll()
        persist()
        Task { [semanticIndex] in
            await semanticIndex.clear()
        }
    }

    func remove(_ item: ClipboardItem) {
        remove(id: item.id)
    }

    func remove(id: UUID) {
        guard items.contains(where: { $0.id == id }) else {
            return
        }

        items.removeAll { $0.id == id }
        searchResults.removeAll { $0.id == id }
        persist()

        Task { [semanticIndex] in
            await semanticIndex.remove(id: id)
        }

        scheduleSearchIfNeeded()
    }

    func restore(_ item: ClipboardItem) {
        writeToPasteboard(item)
    }

    func copyScreenshotImageToPasteboardAndHistory(_ image: ClipboardImage) {
        let item = ClipboardItem.image(image)
        writeToPasteboard(item)
        add(item)
    }

    private func writeToPasteboard(_ item: ClipboardItem) {
        isSelfWriting = true
        pasteboard.clearContents()

        switch item {
        case .text(let text, id: _, timestamp: _):
            pasteboard.setString(text, forType: .string)
        case .image(let image, id: _, timestamp: _):
            _ = image.write(to: pasteboard)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.isSelfWriting = false
        }
    }

    private func persist() {
        persistence?.saveItems(items)
    }

    private func rebuildSemanticIndex() {
        let textItems = Self.textIndexItems(from: items)
        Task { [semanticIndex] in
            await semanticIndex.rebuild(items: textItems)
        }
    }

    private func syncSemanticIndex(addedItem: ClipboardItem?, removedIDs: Set<UUID>) {
        let textEntry = addedItem.flatMap { item -> (id: UUID, text: String)? in
            guard let text = item.textValue else {
                return nil
            }

            return (item.id, text)
        }

        Task { [semanticIndex] in
            for id in removedIDs {
                await semanticIndex.remove(id: id)
            }

            if let textEntry {
                await semanticIndex.add(id: textEntry.id, text: textEntry.text)
            }
        }
    }

    private func scheduleSearchIfNeeded() {
        guard !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        scheduleSearch()
    }

    private func scheduleSearch() {
        searchTask?.cancel()

        let query = searchQuery
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else {
                return
            }

            await self?.performSearch(matching: query)
        }
    }

    private func performSearch(matching query: String) async {
        guard query == searchQuery else {
            return
        }

        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            searchResults = []
            return
        }

        let currentItems = items
        let results = await semanticIndex.search(query: query, allItems: currentItems)

        guard query == searchQuery else {
            return
        }

        searchResults = results
    }

    private static func prunedItems(_ items: [ClipboardItem], maxItems: Int, maxImageItems: Int) -> [ClipboardItem] {
        var keptItems: [ClipboardItem] = []
        var keptImageCount = 0

        for item in items {
            guard keptItems.count < maxItems else {
                break
            }

            if item.imageValue != nil {
                guard keptImageCount < maxImageItems else {
                    continue
                }
                keptImageCount += 1
            }

            keptItems.append(item)
        }

        return keptItems
    }

    private static func textIndexItems(from items: [ClipboardItem]) -> [(id: UUID, text: String)] {
        items.compactMap { item in
            guard let text = item.textValue else {
                return nil
            }

            return (item.id, text)
        }
    }
}
