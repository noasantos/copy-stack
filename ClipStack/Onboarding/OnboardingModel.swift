import AppKit
import ApplicationServices
import SwiftUI

/// Source of truth for the onboarding window. Steps are ordered: demos first, permissions after.
@MainActor
final class OnboardingModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome, quickPaste, capture, accessibility, screenRecording, done
    }

    enum PermissionState { case waiting, granted, skipped }

    @Published var step: Step = .welcome
    /// +1 when moving forward, -1 when moving back. Drives the slide direction of the page transition.
    @Published var direction: Int = 1
    @Published var accessibility: PermissionState = .waiting
    @Published var screenRecording: PermissionState = .waiting
    /// macOS only forces a restart when the grant is flipped in System Settings behind a running
    /// app — which happens only after the in-app request has already been denied once.
    @Published var screenRecordingNeedsRelaunch = false
    @Published var skippedOnboarding = false

    var onFinish: (() -> Void)?

    private var pollTask: Task<Void, Never>?

    init() {
        accessibility = Permissions.accessibilityGranted ? .granted : .waiting
        screenRecording = Permissions.screenRecordingGranted ? .granted : .waiting
    }

    // MARK: Navigation

    var canContinue: Bool { !(step == .accessibility && accessibility == .waiting) }

    var permissionForCurrentStep: PermissionState {
        switch step {
        case .accessibility: return accessibility
        case .screenRecording: return screenRecording
        default: return .waiting
        }
    }

    func next() {
        guard canContinue else { return }
        if step == .done {
            finish()
            return
        }
        direction = 1
        step = Step(rawValue: step.rawValue + 1) ?? .done
        refreshPolling()
    }

    func back() {
        guard step != .welcome else { return }
        direction = -1
        step = Step(rawValue: step.rawValue - 1) ?? .welcome
        refreshPolling()
    }

    func skipSetup() {
        skippedOnboarding = true
        finish()
    }

    func finish() {
        pollTask?.cancel()
        pollTask = nil
        UserDefaults.standard.set(true, forKey: Permissions.hasCompletedOnboardingKey)
        if accessibility == .granted { Permissions.rememberAccessibilityGrant() }
        onFinish?()
    }

    // MARK: Permissions

    func allowCurrentPermission() {
        switch step {
        case .accessibility:
            Permissions.requestAccessibility()
        case .screenRecording:
            // Ask first, and only fall back to System Settings — the route that costs a
            // relaunch — when the system refuses to prompt because it was denied before.
            if !Permissions.requestScreenRecording() { screenRecordingNeedsRelaunch = true }
        default:
            break
        }
    }

    func notNow() {
        switch step {
        case .accessibility: accessibility = .skipped
        case .screenRecording: screenRecording = .skipped
        default: break
        }
    }

    /// Poll every 0.5 s while a permission step is visible; also re-checked on app activation.
    func refreshPolling() {
        pollTask?.cancel()
        guard step == .accessibility || step == .screenRecording else {
            pollTask = nil
            return
        }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.checkPermissions()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func checkPermissions() {
        let animation = Animation.spring(response: 0.45, dampingFraction: 0.55)
        if accessibility != .granted, Permissions.accessibilityGranted {
            withAnimation(animation) { accessibility = .granted }
            Permissions.rememberAccessibilityGrant()
        }
        if screenRecording != .granted, Permissions.screenRecordingGranted {
            withAnimation(animation) { screenRecording = .granted }
            screenRecordingNeedsRelaunch = false
        }
    }
}

enum Permissions {
    static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    static let lastGrantedAccessibilityBuildKey = "lastGrantedAccessibilityBuild"

    static var accessibilityGranted: Bool { AccessibilityTextCaretLocator.isTrusted(prompt: false) }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    @MainActor
    static func requestAccessibility() {
        _ = AccessibilityTextCaretLocator.isTrusted(prompt: true)
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    /// Returns false when macOS declined to show its prompt, meaning the answer is already on
    /// record and only System Settings can change it. Opening that pane is what makes macOS
    /// demand a relaunch, so it is a fallback, never the first move.
    @MainActor
    @discardableResult
    static func requestScreenRecording() -> Bool {
        if CGRequestScreenCaptureAccess() { return true }
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        return false
    }

    /// Relaunches the app so a Screen Recording grant made in System Settings takes effect.
    @MainActor
    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }

    @MainActor
    private static func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }

    // Update case: macOS silently drops the Accessibility grant when the ad-hoc signature changes.
    static var currentBuild: String { Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0" }

    static func rememberAccessibilityGrant() {
        UserDefaults.standard.set(currentBuild, forKey: lastGrantedAccessibilityBuildKey)
    }

    static var needsReauthorization: Bool {
        guard let last = UserDefaults.standard.string(forKey: lastGrantedAccessibilityBuildKey) else { return false }
        return last != currentBuild && !accessibilityGranted
    }
}
