import SwiftUI

/// Native-looking key cap. Pressed = accent 16% fill, +1 pt offset, 0.12 s.
struct KeyBadge: View {
    let glyph: String
    var pressed = false

    init(_ glyph: String, pressed: Bool = false) {
        self.glyph = glyph
        self.pressed = pressed
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 5, style: .continuous) }

    var body: some View {
        Text(verbatim: glyph)
            .font(.system(size: glyph == "esc" ? 10 : 12, weight: .medium))
            .foregroundStyle(OnboardingChrome.label)
            .padding(.horizontal, 5)
            .frame(minWidth: 22, minHeight: 22)
            .background(pressed ? Color.accentColor.opacity(0.16) : OnboardingChrome.keyCapFill, in: shape)
            .overlay(shape.strokeBorder(OnboardingChrome.keyCapHairline, lineWidth: 0.5))
            .shadow(color: OnboardingChrome.keyCapShadow, radius: 0, y: 1)
            .offset(y: pressed ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: pressed)
    }
}

/// ⇧ ⌘ + one letter, as used inline in the subtitle and on the Done step.
struct ShortcutBadges: View {
    let letter: String
    var pressedKeys: Set<DemoTimeline.Key> = []

    var body: some View {
        HStack(spacing: 3) {
            KeyBadge("⇧", pressed: pressedKeys.contains(.shift))
            KeyBadge("⌘", pressed: pressedKeys.contains(.command))
            KeyBadge(letter, pressed: pressedKeys.contains(letter == "V" ? .letterV : .letterS))
        }
    }
}

/// Six indicators; the current one is a 20×6 pill.
struct PageIndicator: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? OnboardingChrome.label : OnboardingChrome.tertiary)
                    .frame(width: index == current ? 20 : 6, height: 6)
            }
        }
        .animation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.3), value: current)
    }
}

/// ↑ ↓ Choose · ↩ Paste · esc Close. Badges light up from the demo timeline.
struct QuickPasteLegend: View {
    let pressedKeys: Set<DemoTimeline.Key>

    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 5) {
                KeyBadge("↑", pressed: pressedKeys.contains(.up))
                KeyBadge("↓", pressed: pressedKeys.contains(.down))
                Text(onboarding: "paste.legend.choose")
            }
            HStack(spacing: 5) {
                KeyBadge("↩", pressed: pressedKeys.contains(.return))
                Text(onboarding: "paste.legend.paste")
            }
            HStack(spacing: 5) {
                KeyBadge("esc")
                Text(onboarding: "paste.legend.close")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(OnboardingChrome.secondary)
    }
}

/// Fades in when the capture lands in the popover.
struct CaptureConfirmationLine: View {
    let visible: Bool

    var body: some View {
        HStack(spacing: 14) {
            item("capture.confirm.saved")
            item("capture.confirm.copied")
            item("capture.confirm.history")
        }
        .font(.system(size: 12))
        .foregroundStyle(OnboardingChrome.secondary)
        .opacity(visible ? 1 : 0)
        .animation(.easeOut(duration: 0.3), value: visible)
    }

    private func item(_ key: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
            Text(onboarding: key)
        }
    }
}

/// Waiting / granted / skipped row under the subtitle on the two permission steps.
struct PermissionStatusView: View {
    enum Kind { case accessibility, screenRecording }

    let kind: Kind
    let state: OnboardingModel.PermissionState
    var needsRelaunch = false
    let allow: () -> Void
    let notNow: () -> Void
    var relaunch: () -> Void = {}

    private var allowKey: String { kind == .accessibility ? "access.allow" : "screen.allow" }
    private var allowedKey: String { kind == .accessibility ? "access.allowed" : "screen.allowed" }
    private var waitingKey: String { kind == .accessibility ? "access.waiting" : "screen.waiting" }
    private var grantedKey: String { kind == .accessibility ? "access.grantedCaption" : "screen.grantedCaption" }
    private var skippedKey: String { kind == .accessibility ? "access.skipped" : "screen.skipped" }
    private var notNowKey: String { kind == .accessibility ? "access.notNow" : "screen.notNow" }

    var body: some View {
        HStack(spacing: 12) {
            switch state {
            case .waiting:
                if needsRelaunch {
                    Button(action: relaunch) {
                        Text(onboarding: "screen.relaunch")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .capsuleBorderIfAvailable()
                    .frame(height: 32)
                } else {
                    allowButton
                }
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text(onboarding: needsRelaunch ? "screen.relaunchNote" : waitingKey)
                }
                .font(.system(size: 12))
                .foregroundStyle(OnboardingChrome.secondary)
                OnboardingPlainButton(titleKey: notNowKey, action: notNow)

            case .granted:
                Button {} label: {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                        Text(onboarding: allowedKey)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .capsuleBorderIfAvailable()
                .frame(height: 32)
                .disabled(true)

                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.white, Color.accentColor)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                    Text(onboarding: grantedKey)
                        .font(.system(size: 13, weight: .semibold))
                        .transition(.opacity.animation(.easeOut(duration: 0.3).delay(0.15)))
                }
                .fixedSize()

            case .skipped:
                Button(action: allow) {
                    Text(onboarding: allowKey).font(.system(size: 13)).frame(maxHeight: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .capsuleBorderIfAvailable()
                .frame(height: 32)

                Text(onboarding: skippedKey)
                    .font(.system(size: 12))
                    .foregroundStyle(OnboardingChrome.secondary)
                    .lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var allowButton: some View {
        let label = Text(onboarding: allowKey).font(.system(size: 13, weight: .semibold)).frame(maxHeight: .infinity)
        if kind == .accessibility {
            Button(action: allow) { label }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .capsuleBorderIfAvailable()
                .frame(height: 32)
        } else {
            // Optional permission: bordered with accent text, never prominent.
            Button(action: allow) { label.foregroundStyle(Color.accentColor) }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .capsuleBorderIfAvailable()
                .frame(height: 32)
        }
    }
}

/// Back / Skip Setup / Not now: plain, 13 pt secondary, quaternary hover fill at radius 6.
struct OnboardingPlainButton: View {
    let titleKey: String
    var leadingChevron = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 2) {
                if leadingChevron {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium))
                }
                Text(onboarding: titleKey)
            }
            .font(.system(size: 13))
            .foregroundStyle(OnboardingChrome.secondary)
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(hovering ? OnboardingChrome.hoverFill : .clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

extension View {
    /// `ButtonBorderShape.capsule` is macOS 14+; on macOS 13 the system rounded rectangle is used.
    @ViewBuilder
    func capsuleBorderIfAvailable() -> some View {
        if #available(macOS 14.0, *) {
            self.buttonBorderShape(.capsule)
        } else {
            self
        }
    }
}
