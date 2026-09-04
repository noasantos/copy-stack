#if DEBUG
import SwiftUI

/// Mirrors the artboards in `reference-html/ClipStack Onboarding v2.dc.html`: every step, both
/// appearances, and all three permission states for the two permission steps.
private struct OnboardingPreview: View {
    let step: OnboardingModel.Step
    var permission: OnboardingModel.PermissionState = .waiting

    @StateObject private var timeline = DemoTimeline()
    @StateObject private var model = OnboardingModel()

    var body: some View {
        OnboardingView(model: model, timeline: timeline)
            .onAppear {
                model.step = step
                model.accessibility = permission
                model.screenRecording = permission
                model.stopPolling()
            }
    }
}

private struct PreviewPair<Content: View>: View {
    let label: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 40) {
            content().preferredColorScheme(.light)
            content().preferredColorScheme(.dark)
        }
        .padding(40)
        .previewDisplayName(label)
        .previewLayout(.sizeThatFits)
    }
}

struct Onboarding_Welcome_Previews: PreviewProvider {
    static var previews: some View {
        PreviewPair(label: "1 · Welcome") { OnboardingPreview(step: .welcome) }
    }
}

struct Onboarding_QuickPaste_Previews: PreviewProvider {
    static var previews: some View {
        PreviewPair(label: "2 · Quick Paste demo") { OnboardingPreview(step: .quickPaste) }
    }
}

struct Onboarding_Capture_Previews: PreviewProvider {
    static var previews: some View {
        PreviewPair(label: "3 · Area capture demo") { OnboardingPreview(step: .capture) }
    }
}

struct Onboarding_Accessibility_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewPair(label: "4 · Accessibility — waiting") {
                OnboardingPreview(step: .accessibility, permission: .waiting)
            }
            PreviewPair(label: "4 · Accessibility — granted") {
                OnboardingPreview(step: .accessibility, permission: .granted)
            }
            PreviewPair(label: "4 · Accessibility — skipped") {
                OnboardingPreview(step: .accessibility, permission: .skipped)
            }
        }
    }
}

struct Onboarding_ScreenRecording_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            PreviewPair(label: "5 · Screen Recording — waiting") {
                OnboardingPreview(step: .screenRecording, permission: .waiting)
            }
            PreviewPair(label: "5 · Screen Recording — granted") {
                OnboardingPreview(step: .screenRecording, permission: .granted)
            }
            PreviewPair(label: "5 · Screen Recording — skipped") {
                OnboardingPreview(step: .screenRecording, permission: .skipped)
            }
        }
    }
}

struct Onboarding_Done_Previews: PreviewProvider {
    static var previews: some View {
        PreviewPair(label: "6 · Done") { OnboardingPreview(step: .done) }
    }
}

struct Onboarding_ReauthorizeSheet_Previews: PreviewProvider {
    static var previews: some View {
        PreviewPair(label: "Re-authorize Accessibility") {
            ReauthorizeAccessibilitySheet(onLater: {}, onGranted: {})
                .background(OnboardingChrome.windowBackground)
        }
    }
}

struct Onboarding_MacBookScale_Previews: PreviewProvider {
    static var previews: some View {
        // The laptop is authored once and only its outer scale changes.
        VStack(spacing: 24) {
            ForEach([0.28, 0.42], id: \.self) { scale in
                MacBookFrame {
                    DesktopScene(step: .welcome, permission: .waiting, timeline: DemoTimeline())
                }
                .scaleEffect(scale / MacBookFrame<EmptyView>.scale, anchor: .topLeading)
                .frame(width: MacBookFrame<EmptyView>.canonicalSize.width * scale,
                       height: MacBookFrame<EmptyView>.canonicalSize.height * scale)
            }
        }
        .padding(40)
        .previewDisplayName("MacBook frame — any container size")
        .previewLayout(.sizeThatFits)
    }
}
#endif
