import AppKit
import SwiftUI

/// 720×520 titled window without a title: close button only, not resizable, centered on the main screen.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let model = OnboardingModel()
    private let timeline = DemoTimeline()
    private var activationObserver: NSObjectProtocol?

    /// Kept alive for as long as the window is on screen.
    private static var shared: OnboardingWindowController?

    convenience init() {
        let size = OnboardingView.windowSize
        let window = OnboardingWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.backgroundColor = .windowBackgroundColor
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace]
        self.init(window: window)

        window.delegate = self
        model.onFinish = { [weak self] in self?.close() }
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, timeline: timeline))
        window.setFrame(NSRect(origin: .zero, size: size), display: false)
        window.center()
    }

    /// Shown only on the first launch after install.
    @discardableResult
    static func presentIfNeeded() -> OnboardingWindowController? {
        guard !UserDefaults.standard.bool(forKey: Permissions.hasCompletedOnboardingKey) else { return nil }
        return present()
    }

    @discardableResult
    static func present() -> OnboardingWindowController {
        if let existing = shared {
            existing.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return existing
        }
        let controller = OnboardingWindowController()
        shared = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        return controller
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.center()
        model.refreshPolling()
        guard activationObserver == nil else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.model.checkPermissions() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.stopPolling()
        timeline.stop()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
        }
        activationObserver = nil
        Self.shared = nil
    }
}

/// Keeps the close button at (12, 8) in the 28 pt title-bar zone, as drawn in the artboards.
private final class OnboardingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        guard let close = standardWindowButton(.closeButton), let container = close.superview else { return }
        let origin = NSPoint(x: 12, y: container.bounds.height - 8 - close.bounds.height)
        if close.frame.origin != origin {
            close.setFrameOrigin(origin)
        }
    }
}
