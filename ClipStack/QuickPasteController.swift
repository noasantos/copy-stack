import AppKit
import Carbon
import SwiftUI
import os

private let quickPasteLogger = Logger(subsystem: "com.startapse.ClipStack", category: "quick-paste")

@MainActor
final class QuickPasteController: NSObject {
    static let requestedPanelSize = CGSize(width: 320, height: 300)

    private let store: ClipboardStore
    private let caretLocator = AccessibilityTextCaretLocator()
    private let session = QuickPasteSession()
    private var panel: QuickPastePanel?
    private var targetApplication: NSRunningApplication?
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?

    init(store: ClipboardStore) {
        self.store = store
    }

    func toggle() {
        if panel?.isVisible == true {
            dismiss()
        } else {
            present()
        }
    }

    func dismiss() {
        panel?.orderOut(nil)
        removeEventMonitors()
        targetApplication = nil
    }

    private func present() {
        guard let targetApplication = Self.frontmostTargetApplication() else {
            return
        }
        self.targetApplication = targetApplication

        guard let anchor = caretLocator.anchorRect(
            applicationPID: targetApplication.processIdentifier,
            requestPermission: true
        ) else {
            self.targetApplication = nil
            return
        }
        guard let screen = Self.screen(containing: anchor) else {
            self.targetApplication = nil
            return
        }

        let placement = QuickPastePanelPlacement.make(
            anchor: anchor,
            requestedSize: Self.requestedPanelSize,
            visibleFrame: screen.visibleFrame
        )
        session.reset(with: store.items)

        let rootView = QuickPasteView(
            store: store,
            session: session,
            direction: placement.direction,
            onPaste: { [weak self] item in
                self?.paste(item)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        let panel = panel ?? makePanel()
        panel.contentViewController = ClearHostingController(rootView: rootView)
        panel.setFrame(placement.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installEventMonitors()
    }

    private func paste(_ item: ClipboardItem) {
        let targetApplication = targetApplication
        store.restore(item)
        dismiss()

        guard AccessibilityTextCaretLocator.isTrusted(prompt: false),
              let targetApplication,
              !targetApplication.isTerminated else {
            return
        }

        targetApplication.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            Self.sendPasteCommand()
        }
    }

    private func makePanel() -> QuickPastePanel {
        let panel = QuickPastePanel(
            contentRect: CGRect(origin: .zero, size: Self.requestedPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary]
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func installEventMonitors() {
        removeEventMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else {
                return event
            }

            switch Int(event.keyCode) {
            case kVK_UpArrow:
                session.moveSelection(by: -1, within: visibleItems)
                return nil
            case kVK_DownArrow:
                session.moveSelection(by: 1, within: visibleItems)
                return nil
            case kVK_Return, kVK_ANSI_KeypadEnter:
                if let item = session.selectedItem(in: visibleItems) {
                    paste(item)
                }
                return nil
            case kVK_Escape:
                dismiss()
                return nil
            default:
                return event
            }
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private var visibleItems: [ClipboardItem] {
        session.visibleItems(from: store.items)
    }

    private func removeEventMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }
    }

    private static func screen(containing anchor: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { screen in
            screen.frame.intersects(anchor) || screen.frame.contains(anchor.origin)
        }) ?? NSScreen.main ?? NSScreen.screens.first
    }

    private static func frontmostTargetApplication() -> NSRunningApplication? {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return nil
        }
        return application
    }

    private static func sendPasteCommand() {
        guard let keyDown = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: nil,
            virtualKey: CGKeyCode(kVK_ANSI_V),
            keyDown: false
        ) else {
            quickPasteLogger.error("ClipStack failed to create the quick-paste keyboard event")
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cgSessionEventTap)
        keyUp.post(tap: .cgSessionEventTap)
    }
}

private final class QuickPastePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
