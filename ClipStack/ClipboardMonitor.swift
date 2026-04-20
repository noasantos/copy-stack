import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    static let pollInterval: TimeInterval = 0.5

    private let store: ClipboardStore
    private let pasteboard: NSPasteboard
    private var timer: Timer?
    private var lastChangeCount: Int

    init(store: ClipboardStore, pasteboard: NSPasteboard = .general) {
        self.store = store
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        lastChangeCount = pasteboard.changeCount

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollOnce()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func pollOnce() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        lastChangeCount = currentChangeCount

        guard !store.isSelfWriting else {
            return
        }

        if let string = pasteboard.string(forType: .string), !string.isEmpty {
            store.add(.text(string))
            return
        }

        if let image = NSImage(pasteboard: pasteboard) {
            store.add(.image(image))
        }
    }
}
