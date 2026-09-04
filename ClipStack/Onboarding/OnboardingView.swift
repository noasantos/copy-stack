import SwiftUI

/// Window content. Geometry mirrors SPEC.md §2: MacBook at y 34, indicator y 348, title y 364,
/// aux row y 418, footer 60. The frame, the indicator and the footer never move between steps.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var timeline: DemoTimeline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let windowSize = CGSize(width: 720, height: 520)

    var body: some View {
        ZStack(alignment: .top) {
            OnboardingChrome.windowBackground

            MacBookFrame {
                DesktopScene(step: model.step, permission: model.permissionForCurrentStep, timeline: timeline)
                    .id(model.step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 34)

            PageIndicator(count: OnboardingModel.Step.allCases.count, current: model.step.rawValue)
                .padding(.top, 348)

            stepText
                .padding(.horizontal, 40)
                .padding(.top, 364)
                .id(model.step)
                .transition(pageTransition)

            auxiliaryRow
                .frame(height: 36)
                .padding(.horizontal, 40)
                .padding(.top, 418)
                .id(model.step)
                .transition(pageTransition)

            footer
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
        .animation(stepAnimation, value: model.step)
        .onAppear(perform: startTimeline)
        .onValueChange(of: model.step) { _ in startTimeline() }
        .onDisappear { timeline.stop() }
    }

    private var stepAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.38, dampingFraction: 0.86)
    }

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let dx = 18 * CGFloat(model.direction)
        return .asymmetric(insertion: .offset(x: dx).combined(with: .opacity),
                           removal: .offset(x: -dx).combined(with: .opacity))
    }

    private func startTimeline() {
        timeline.stop()
        switch model.step {
        case .quickPaste: timeline.startQuickPaste()
        case .capture: timeline.startCapture()
        default: break
        }
    }

    // MARK: Title + subtitle

    private var stepText: some View {
        VStack(spacing: 5) {
            Text(onboarding: copy.title)
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(OnboardingChrome.label)

            HStack(spacing: 5) {
                if let letter = copy.shortcutLetter {
                    Text(onboarding: copy.prefix ?? "")
                    ShortcutBadges(letter: letter, pressedKeys: timeline.pressedKeys)
                }
                Text(onboarding: copy.subtitle)
            }
            .font(.system(size: 13))
            .foregroundStyle(OnboardingChrome.secondary)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var copy: (title: String, subtitle: String, prefix: String?, shortcutLetter: String?) {
        switch model.step {
        case .welcome: return ("welcome.title", "welcome.promise", nil, nil)
        case .quickPaste: return ("paste.title", "paste.body.suffix", "paste.body.prefix", "V")
        case .capture: return ("capture.title", "capture.body.suffix", "capture.body.prefix", "S")
        case .accessibility: return ("access.title", "access.body", nil, nil)
        case .screenRecording: return ("screen.title", "screen.body", nil, nil)
        case .done: return ("done.title", "done.body", nil, nil)
        }
    }

    // MARK: Auxiliary row

    @ViewBuilder
    private var auxiliaryRow: some View {
        Group {
            switch model.step {
            case .welcome:
                HStack(spacing: 7) {
                    Image(systemName: "lock.fill").font(.system(size: 11))
                    Text(onboarding: "welcome.privacy")
                }
                .font(.system(size: 12))
                .foregroundStyle(OnboardingChrome.secondary)

            case .quickPaste:
                QuickPasteLegend(pressedKeys: timeline.pressedKeys)

            case .capture:
                CaptureConfirmationLine(visible: timeline.capture.landed)

            case .accessibility:
                PermissionStatusView(kind: .accessibility,
                                     state: model.accessibility,
                                     allow: model.allowCurrentPermission,
                                     notNow: model.notNow)

            case .screenRecording:
                PermissionStatusView(kind: .screenRecording,
                                     state: model.screenRecording,
                                     needsRelaunch: model.screenRecordingNeedsRelaunch,
                                     allow: model.allowCurrentPermission,
                                     notNow: model.notNow,
                                     relaunch: Permissions.relaunch)

            case .done:
                HStack(spacing: 22) {
                    shortcutSummary("V", "done.quickPaste")
                    shortcutSummary("S", "done.captureArea")
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func shortcutSummary(_ letter: String, _ key: String) -> some View {
        HStack(spacing: 7) {
            ShortcutBadges(letter: letter)
            Text(onboarding: key)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OnboardingChrome.label)
        }
    }

    // MARK: Footer

    private var footer: some View {
        ZStack {
            HStack {
                OnboardingPlainButton(titleKey: "nav.back", leadingChevron: true) { model.back() }
                    .keyboardShortcut("[", modifiers: .command)
                    .opacity(model.step == .welcome ? 0 : 1)
                    .disabled(model.step == .welcome)
                    .accessibilityHidden(model.step == .welcome)

                Spacer(minLength: 0)

                OnboardingPlainButton(titleKey: "nav.skip") { model.skipSetup() }
                    .keyboardShortcut(.cancelAction)
                    .opacity(model.step == .done ? 0 : 1)
                    .disabled(model.step == .done)
                    .accessibilityHidden(model.step == .done)
            }
            .padding(.horizontal, 20)

            Button { model.next() } label: {
                Text(onboarding: model.step == .done ? "done.cta" : "nav.continue")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .capsuleBorderIfAvailable()
            .frame(width: 220, height: 36)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.canContinue)
            .opacity(model.canContinue ? 1 : 0.45)
            .animation(.easeOut(duration: 0.25), value: model.canContinue)
        }
        .frame(height: 60)
    }
}
