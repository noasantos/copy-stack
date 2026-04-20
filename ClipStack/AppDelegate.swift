import AppKit
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var store = ClipboardStore(persistence: ClipboardHistoryPersistence.applicationSupport())

    private var clipboardMonitor: ClipboardMonitor?
    private var screenshotWatcher: ScreenshotWatcher?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else {
            return
        }

        NSApp.setActivationPolicy(.accessory)
        requestNotificationPermission()
        registerLoginItem()
        configureStatusItem()

        let clipboardMonitor = ClipboardMonitor(store: store)
        clipboardMonitor.start()
        self.clipboardMonitor = clipboardMonitor

        let screenshotWatcher = ScreenshotWatcher(store: store)
        screenshotWatcher.start()
        self.screenshotWatcher = screenshotWatcher
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor?.stop()
        screenshotWatcher?.stop()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func registerLoginItem() {
        let service = SMAppService.mainApp
        guard service.status == .notRegistered else { return }
        try? service.register()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        guard let button = statusItem.button else {
            return
        }

        let image = NSImage(systemSymbolName: "clipboard.fill", accessibilityDescription: "ClipStack")
        image?.isTemplate = true
        button.image = image
        button.title = ""
        button.toolTip = "ClipStack Clipboard History"
        button.target = self
        button.action = #selector(togglePopover(_:))

        configurePopover()
    }

    private func configurePopover() {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 560)
        popover.contentViewController = ClearHostingController(rootView: MenuBarView(store: store))
        self.popover = popover
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover else {
            return
        }

        if popover.isShown {
            closePopover()
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    private func closePopover() {
        popover?.performClose(nil)
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}

private final class ClearHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        super.loadView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
    }
}
