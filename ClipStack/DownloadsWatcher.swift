import Darwin
import Foundation

final class DownloadsWatcher {
    private let directoryURL: URL
    private let store: DownloadsStore
    private let queue = DispatchQueue(label: "com.startapse.ClipStack.downloads-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var pendingScan: DispatchWorkItem?

    init(
        store: DownloadsStore,
        directoryURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    ) {
        self.store = store
        self.directoryURL = directoryURL
    }

    deinit {
        stop()
    }

    func start() {
        stop()
        scanNow()

        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            return
        }

        fileDescriptor = descriptor

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.scheduleDebouncedScan()
        }

        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }

        self.source = source
        source.resume()
    }

    func stop() {
        pendingScan?.cancel()
        pendingScan = nil
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    private func scheduleDebouncedScan() {
        pendingScan?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.scanNow()
        }

        pendingScan = workItem
        queue.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func scanNow() {
        let store = store
        Task { @MainActor in
            store.refresh()
        }
    }
}
