import AppKit
import SwiftUI

/// Compact sheet for the update case. 480 wide, height to fit. Deliberately unlike the onboarding
/// window: no MacBook, no page indicator, no footer — it reads as a system alert.
struct ReauthorizeAccessibilitySheet: View {
    var onLater: () -> Void
    var onGranted: () -> Void

    @State private var poll: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "accessibility")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 5) {
                    Text(onboarding: "reauth.title")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(OnboardingChrome.label)
                    Text(onboarding: "reauth.body")
                        .font(.system(size: 12))
                        .foregroundStyle(OnboardingChrome.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 0) {
                        stepRow(1, "reauth.step1", on: false)
                        Divider().padding(.leading, 44)
                        stepRow(2, "reauth.step2", on: true)
                    }
                    .background(OnboardingChrome.cardFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(OnboardingChrome.separator, lineWidth: 0.5))
                    .padding(.top, 9)
                }
            }

            HStack(spacing: 8) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(onboarding: "reauth.note")
                }
                .font(.system(size: 11))
                .foregroundStyle(OnboardingChrome.secondary)
                .lineLimit(1)
                .fixedSize()

                Spacer(minLength: 12)

                Button(action: onLater) { Text(onboarding: "reauth.later") }
                    .buttonStyle(.bordered)
                    .fixedSize()

                Button { Permissions.requestAccessibility() } label: {
                    Text(onboarding: "reauth.open")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .fixedSize()
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear(perform: startPolling)
        .onDisappear { poll?.cancel(); poll = nil }
    }

    private func startPolling() {
        poll?.cancel()
        poll = Task { @MainActor in
            while !Task.isCancelled {
                if Permissions.accessibilityGranted {
                    Permissions.rememberAccessibilityGrant()
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    onGranted()
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func stepRow(_ number: Int, _ key: String, on: Bool) -> some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(OnboardingChrome.label)
                .frame(width: 20, height: 20)
                .background(OnboardingChrome.hoverFill, in: Circle())

            Text(onboarding: key)
                .font(.system(size: 12))
                .foregroundStyle(OnboardingChrome.label)

            Spacer(minLength: 8)

            SwitchGlyph(on: on)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// 26×15 pictogram of the switch the user has to flip — not an interactive control.
private struct SwitchGlyph: View {
    let on: Bool

    var body: some View {
        Capsule()
            .fill(on ? Color.accentColor : OnboardingChrome.hoverFill)
            .overlay(Capsule().strokeBorder(OnboardingChrome.separator, lineWidth: on ? 0 : 0.5))
            .overlay(alignment: on ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.25), radius: 0.5, y: 0.5)
                    .frame(width: 11, height: 11)
                    .padding(.horizontal, 2)
            }
            .frame(width: 26, height: 15)
            .accessibilityHidden(true)
    }
}

/// Presented on a transparent borderless host so it reads as a system sheet, centered on screen.
@MainActor
enum ReauthorizePresenter {
    private static var host: NSWindow?
    private static var sheet: NSWindow?

    static func presentIfNeeded() {
        guard Permissions.needsReauthorization, host == nil else { return }

        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                            styleMask: [.borderless], backing: .buffered, defer: false)
        host.isOpaque = false
        host.backgroundColor = .clear
        host.hasShadow = false
        host.level = .floating
        host.center()

        let controller = NSHostingController(rootView: ReauthorizeAccessibilitySheet(
            onLater: { dismiss() },
            onGranted: { dismiss() }))
        let sheet = NSWindow(contentViewController: controller)
        sheet.styleMask = [.titled, .fullSizeContentView]
        sheet.titlebarAppearsTransparent = true
        sheet.titleVisibility = .hidden

        Self.host = host
        Self.sheet = sheet

        host.orderFront(nil)
        host.beginSheet(sheet)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func dismiss() {
        guard let host, let sheet else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            host.endSheet(sheet)
        } completionHandler: {
            MainActor.assumeIsolated {
                host.close()
                Self.host = nil
                Self.sheet = nil
            }
        }
    }
}
