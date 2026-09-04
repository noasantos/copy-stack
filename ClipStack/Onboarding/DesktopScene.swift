import SwiftUI

/// Everything shown inside the 1512×982 display. Ordinary desktop-size views — no scaling here.
/// Layer order: wallpaper → menu bar → app window (Notes / System Settings) → capture overlay
/// → Quick Paste panel → popover.
struct DesktopScene: View {
    let step: OnboardingModel.Step
    let permission: OnboardingModel.PermissionState
    @ObservedObject var timeline: DemoTimeline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var caretFrame: CGRect = DemoGeometry.fallbackCaretFrame
    @State private var statusItemMidX: CGFloat = DemoGeometry.fallbackStatusItemMidX

    private var popoverOpen: Bool {
        step == .welcome || (step == .capture && timeline.capture.landed)
    }

    private var statusItemHighlighted: Bool { popoverOpen || step == .done }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("DemoWallpaper")
                .resizable()
                .scaledToFill()
                .frame(width: DemoGeometry.screen.width, height: DemoGeometry.screen.height)

            MenuBarMock(appName: appName, statusItemHighlighted: statusItemHighlighted)

            if step == .quickPaste || step == .capture {
                NotesWindowMock(insertedText: insertedText, highlightInsertion: timeline.quickPaste != .pasted)
                    .frame(width: 1320, height: 760)
                    .offset(x: 96, y: 111)
            }

            if step == .accessibility || step == .screenRecording {
                SystemSettingsMock(pane: step == .accessibility ? .accessibility : .screenRecording,
                                   clipStackOn: permission == .granted,
                                   highlightRow: permission == .waiting)
                    .frame(width: 715, height: 640)
                    .offset(x: 398, y: 120)
            }

            if step == .capture {
                SelectionOverlay(cue: timeline.capture,
                                 anchor: DemoGeometry.selectionAnchor,
                                 size: DemoGeometry.selectionSize)
            }

            if step == .quickPaste {
                QuickPastePanelMock(cue: timeline.quickPaste, items: Array(DemoData.items.prefix(5)))
                    .offset(x: panelAnchor.x, y: panelAnchor.y)
            }

            PopoverMock(items: popoverItems,
                        highlightFirst: step == .capture,
                        arrowMidX: statusItemMidX - popoverX)
                .frame(width: 380, alignment: .top)
                .offset(x: popoverX, y: 37)
                .opacity(popoverOpen ? 1 : 0)
                .scaleEffect(popoverOpen ? 1 : 0.96, anchor: .topLeading)
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.2), value: popoverOpen)
        }
        .environment(\.demoReduceMotion, reduceMotion)
        .frame(width: DemoGeometry.screen.width, height: DemoGeometry.screen.height, alignment: .topLeading)
        .clipped()
        .coordinateSpace(name: DemoGeometry.spaceName)
        .onPreferenceChange(CaretFramePreference.self) { frame in
            if let frame { caretFrame = frame }
        }
        .onPreferenceChange(StatusItemMidXPreference.self) { midX in
            if let midX { statusItemMidX = midX }
        }
    }

    /// Popover stays ≥ 8 pt inside the display; the arrow keeps pointing at the status item.
    private var popoverX: CGFloat {
        max(8, min(statusItemMidX - 190, DemoGeometry.screen.width - 8 - 380))
    }

    private var popoverItems: [DemoData.Item] {
        step == .capture ? [DemoData.captured] + DemoData.items : DemoData.items
    }

    private var appName: String {
        switch step {
        case .accessibility, .screenRecording: return "System Settings"
        case .quickPaste, .capture: return "Notes"
        case .welcome, .done: return "Finder"
        }
    }

    private var insertedText: String? {
        timeline.quickPaste == .pasted ? DemoData.items[1].title : nil
    }

    /// Pointer tip touches the caret: left = caret.midX − 32, top = caret.maxY + 8.
    private var panelAnchor: CGPoint {
        CGPoint(x: caretFrame.midX - 32, y: caretFrame.maxY + 8)
    }
}

enum DemoGeometry {
    static let spaceName = "clipstack.onboarding.scene"
    static let screen = CGSize(width: 1512, height: 982)
    static let selectionAnchor = CGPoint(x: 330, y: 290)
    static let selectionSize = CGSize(width: 590, height: 320)

    /// Used before the first layout pass reports real geometry.
    static let fallbackCaretFrame = CGRect(x: 300, y: 232, width: 2, height: 19)
    static let fallbackStatusItemMidX: CGFloat = 1300
}

enum DemoData {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let time: String
        var isImage = false
    }

    static let items: [Item] = [
        Item(title: OnboardingStrings.string("demo.item.1"), time: "10:52 AM"),
        Item(title: OnboardingStrings.string("demo.item.2"), time: "10:48 AM"),
        Item(title: OnboardingStrings.string("demo.item.3"), time: "10:41 AM", isImage: true),
        Item(title: OnboardingStrings.string("demo.item.4"), time: "10:22 AM"),
        Item(title: OnboardingStrings.string("demo.item.5"), time: "9:51 AM"),
        Item(title: OnboardingStrings.string("demo.item.6"), time: "9:12 AM", isImage: true)
    ]

    static let captured = Item(title: OnboardingStrings.string("demo.item.captured"), time: "Now", isImage: true)
    static let earlierCount = 12
}

struct CaretFramePreference: PreferenceKey {
    static let defaultValue: CGRect? = nil
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}

struct StatusItemMidXPreference: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

private struct DemoReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var demoReduceMotion: Bool {
        get { self[DemoReduceMotionKey.self] }
        set { self[DemoReduceMotionKey.self] = newValue }
    }
}
