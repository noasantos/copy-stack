import AppKit
import Carbon
import SwiftUI
import os

private let quickPasteLogger = Logger(subsystem: "com.clipstack.app", category: "quick-paste")

struct QuickPasteTarget {
    let processIdentifier: pid_t
    let application: NSRunningApplication?
}

@MainActor
struct QuickPasteEnvironment {
    var frontmostTarget: @MainActor () -> QuickPasteTarget?
    var isAccessibilityTrusted: @MainActor () -> Bool
    var locateCaret: @MainActor (pid_t) -> TextCaretAnchorReport

    static func live() -> QuickPasteEnvironment {
        let locator = AccessibilityTextCaretLocator()
        return QuickPasteEnvironment(
            frontmostTarget: {
                guard let application = NSWorkspace.shared.frontmostApplication,
                      application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
                    return nil
                }
                return QuickPasteTarget(processIdentifier: application.processIdentifier, application: application)
            },
            isAccessibilityTrusted: {
                AccessibilityTextCaretLocator.isTrusted(prompt: false)
            },
            locateCaret: { processIdentifier in
                locator.locate(applicationPID: processIdentifier, requestPermission: false)
            }
        )
    }
}

enum QuickPasteDismissReason: String {
    case toggle
    case escape
    case paste
    case unhandledKey = "unhandled-key"
    case outsideInteraction = "outside-interaction"
    case spaceChanged = "space-changed"
    case applicationSwitched = "application-switched"
    case applicationHidden = "application-hidden"
    case targetTerminated = "target-terminated"
    case panelResignedKey = "panel-resigned-key"
    case panelOccluded = "panel-occluded"
    case screenChanged = "screen-changed"
    case sessionInterrupted = "session-interrupted"
    case programmatic
}

@MainActor
final class QuickPasteController: NSObject {
    static let requestedPanelSize = CGSize(width: 320, height: 300)
    // The panel belongs to the Space where the caret lives; it must never follow the user elsewhere.
    static let panelCollectionBehavior: NSWindow.CollectionBehavior = [
        .moveToActiveSpace, .transient, .fullScreenAuxiliary, .ignoresCycle
    ]

    private let store: ClipboardStore
    private let environment: QuickPasteEnvironment
    private let session = QuickPasteSession()
    private var panel: QuickPastePanel?
    private var targetApplication: NSRunningApplication?
    private var targetProcessIdentifier: pid_t?
    private var localKeyMonitor: Any?
    private var globalInteractionMonitor: Any?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var hasRequestedAccessibilityPermission = false
    private(set) var lastAnchorReport: TextCaretAnchorReport?
    private(set) var lastDismissReason: QuickPasteDismissReason?
    private(set) var presentedDirection: QuickPasteDirection?

    init(store: ClipboardStore, environment: QuickPasteEnvironment? = nil) {
        self.store = store
        self.environment = environment ?? .live()
    }

    var isPanelVisible: Bool {
        panel?.isVisible == true
    }

    var panelFrame: CGRect? {
        isPanelVisible ? panel?.frame : nil
    }

    var hasEventMonitors: Bool {
        localKeyMonitor != nil && globalInteractionMonitor != nil && !observers.isEmpty
    }

    var selectedItemID: UUID? {
        session.selectedID
    }

    func toggle() {
        if isPanelVisible {
            dismiss(reason: .toggle)
        } else {
            present()
        }
    }

    func dismiss() {
        dismiss(reason: .programmatic)
    }

    func dismiss(reason: QuickPasteDismissReason) {
        removeEventMonitors()
        guard let panel, panel.isVisible else {
            targetApplication = nil
            targetProcessIdentifier = nil
            return
        }
        panel.orderOut(nil)
        targetApplication = nil
        targetProcessIdentifier = nil
        presentedDirection = nil
        lastDismissReason = reason
        quickPasteLogger.info("Quick paste panel dismissed: \(reason.rawValue, privacy: .public)")
    }

    private func present() {
        guard let target = environment.frontmostTarget() else {
            quickPasteLogger.notice("Quick paste ignored because no external frontmost application was found")
            return
        }
        targetApplication = target.application
        targetProcessIdentifier = target.processIdentifier

        guard environment.isAccessibilityTrusted() else {
            quickPasteLogger.notice("Quick paste requires Accessibility permission")
            requestAccessibilityPermission()
            targetApplication = nil
            targetProcessIdentifier = nil
            return
        }

        let report = environment.locateCaret(target.processIdentifier)
        lastAnchorReport = report
        guard let anchor = report.rect else {
            let trace = report.trace.joined(separator: "; ")
            quickPasteLogger.notice("Quick paste ignored because the focused element has no supported text caret: \(trace, privacy: .public)")
            targetApplication = nil
            targetProcessIdentifier = nil
            return
        }
        quickPasteLogger.info("Quick paste caret resolved via \(report.path?.rawValue ?? "unknown", privacy: .public) at \(TextCaretGeometry.describe(anchor), privacy: .public)")
        guard let screen = Self.screen(containing: anchor) else {
            quickPasteLogger.error("Quick paste could not resolve a screen for the focused text caret")
            targetApplication = nil
            targetProcessIdentifier = nil
            return
        }

        let placement = QuickPastePanelPlacement.make(
            anchor: anchor,
            requestedSize: Self.requestedPanelSize,
            visibleFrame: screen.visibleFrame
        )
        session.reset(with: store.items)
        presentedDirection = placement.direction

        let rootView = QuickPasteView(
            store: store,
            session: session,
            direction: placement.direction,
            onPaste: { [weak self] item in
                self?.paste(item)
            },
            onDismiss: { [weak self] in
                self?.dismiss(reason: .escape)
            }
        )

        let panel = panel ?? makePanel()
        panel.contentViewController = ClearHostingController(rootView: rootView)
        panel.setFrame(placement.frame, display: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installEventMonitors(for: panel)
        quickPasteLogger.info("Quick paste panel opened \(placement.direction == .below ? "below" : "above", privacy: .public) the caret")
    }

    private func requestAccessibilityPermission() {
        if !hasRequestedAccessibilityPermission {
            hasRequestedAccessibilityPermission = true
            _ = AccessibilityTextCaretLocator.isTrusted(prompt: true)
            return
        }

        let alert = NSAlert()
        alert.messageText = "Allow ClipStack to access the text cursor"
        alert.informativeText = "Open Accessibility settings and turn ClipStack on. If it is already on after an update, turn it off and on once."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Accessibility Settings")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              let settingsURL = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
              ) else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }

    private func paste(_ item: ClipboardItem) {
        let targetApplication = targetApplication
        store.restore(item)
        dismiss(reason: .paste)

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
        panel.collectionBehavior = Self.panelCollectionBehavior
        panel.animationBehavior = .utilityWindow
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isExcludedFromWindowsMenu = true
        return panel
    }

    private func installEventMonitors(for panel: QuickPastePanel) {
        removeEventMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, handleKeyDown(keyCode: Int(event.keyCode)) else {
                return event
            }
            return nil
        }

        // Any interaction that reaches another app means the user moved on.
        globalInteractionMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel, .swipe]
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleFocusLoss(.outsideInteraction)
            }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification, reason: .spaceChanged)
        observeApplication(workspace, NSWorkspace.didActivateApplicationNotification, reason: .applicationSwitched) { process, target in
            process != target
        }
        observeApplication(workspace, NSWorkspace.didHideApplicationNotification, reason: .applicationHidden) { process, target in
            process == nil || process == target
        }
        observeApplication(workspace, NSWorkspace.didTerminateApplicationNotification, reason: .targetTerminated) { process, target in
            process == target
        }
        observe(workspace, NSWorkspace.willSleepNotification, reason: .sessionInterrupted)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, reason: .sessionInterrupted)
        observe(workspace, NSWorkspace.willPowerOffNotification, reason: .sessionInterrupted)
        let center = NotificationCenter.default
        observe(center, NSApplication.didChangeScreenParametersNotification, reason: .screenChanged)
        observe(center, NSWindow.didResignKeyNotification, object: panel, reason: .panelResignedKey)
        observers.append((center, center.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            Self.onMainActor {
                guard let self, let panel = self.panel, panel.isVisible,
                      !panel.occlusionState.contains(.visible) else {
                    return
                }
                self.handleFocusLoss(.panelOccluded)
            }
        }))
    }

    /// Application notifications carry the process they concern; `applies` decides whether that
    /// process (nil when unknown) and the current target mean the user has moved on.
    private func observeApplication(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        reason: QuickPasteDismissReason,
        applies: @escaping @Sendable (pid_t?, pid_t?) -> Bool
    ) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: nil) { [weak self] notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let process = application?.processIdentifier
            Self.onMainActor {
                guard let self, applies(process, self.targetProcessIdentifier) else {
                    return
                }
                self.handleFocusLoss(reason)
            }
        }))
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        object: AnyObject? = nil,
        reason: QuickPasteDismissReason
    ) {
        observers.append((center, center.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            Self.onMainActor {
                self?.handleFocusLoss(reason)
            }
        }))
    }

    private static func onMainActor(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            Task { @MainActor in
                work()
            }
        }
    }

    /// Returns `true` when the key was consumed by the panel. Keys the panel does not
    /// understand close it, so typing continues in the target application.
    @discardableResult
    func handleKeyDown(keyCode: Int) -> Bool {
        guard isPanelVisible else {
            return false
        }

        let olderStep = presentedDirection == .below ? 1 : -1
        switch keyCode {
        case kVK_UpArrow:
            session.moveSelection(by: -olderStep, within: visibleItems)
        case kVK_DownArrow:
            session.moveSelection(by: olderStep, within: visibleItems)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if let item = session.selectedItem(in: visibleItems) {
                paste(item)
            }
        case kVK_Escape:
            dismiss(reason: .escape)
        case kVK_Shift, kVK_Command, kVK_Option, kVK_Control, kVK_CapsLock, kVK_Function,
             kVK_RightShift, kVK_RightCommand, kVK_RightOption, kVK_RightControl:
            return false
        default:
            dismiss(reason: .unhandledKey)
            return false
        }
        return true
    }

    func handleFocusLoss(_ reason: QuickPasteDismissReason) {
        guard isPanelVisible else {
            return
        }
        dismiss(reason: reason)
    }

    func handleOutsideClick() {
        handleFocusLoss(.outsideInteraction)
    }

    private var visibleItems: [ClipboardItem] {
        session.visibleItems(from: store.items)
    }

    private func removeEventMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let globalInteractionMonitor {
            NSEvent.removeMonitor(globalInteractionMonitor)
            self.globalInteractionMonitor = nil
        }

        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers.removeAll()
    }

    private static func screen(containing anchor: CGRect) -> NSScreen? {
        NSScreen.screens.first(where: { screen in
            screen.frame.intersects(anchor) || screen.frame.contains(anchor.origin)
        }) ?? NSScreen.main ?? NSScreen.screens.first
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
