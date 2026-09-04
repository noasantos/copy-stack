import SwiftUI

/// The document the demos type into: 1320×760, radius 12, 52 pt title bar, 15/22 body.
/// Reports the caret's frame in scene coordinates so the Quick Paste panel can point at it.
struct NotesWindowMock: View {
    let insertedText: String?
    let highlightInsertion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
            documentBody
            Spacer(minLength: 0)
        }
        .frame(width: 1320, height: 760, alignment: .topLeading)
        .background(SceneTheme.control)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(SceneTheme.separator, lineWidth: 1))
        .shadow(color: .black.opacity(0.32), radius: 30, y: 22)
    }

    private var titleBar: some View {
        ZStack {
            Text(onboarding: "demo.notes.title")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SceneTheme.secondaryLabel)
            HStack(spacing: 8) {
                TrafficLights()
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(SceneTheme.windowBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(SceneTheme.separator).frame(height: 1) }
    }

    private var documentBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(onboarding: "demo.notes.title")
                .font(.system(size: 22, weight: .bold))
                .padding(.bottom, 14)

            HStack(alignment: .center, spacing: 0) {
                Text(onboarding: "demo.notes.line.prefix")
                // The panel points at the caret as it was *before* the paste, so the probe sits
                // ahead of the inserted run and never moves.
                CaretAnchorProbe()
                Text(insertedText ?? "")
                    .padding(.horizontal, insertedText == nil ? 0 : 1)
                    .background(highlightInsertion ? Color.accentColor.opacity(0.16) : .clear,
                                in: RoundedRectangle(cornerRadius: 3))
                    .animation(.easeOut(duration: 0.8).delay(0.3), value: highlightInsertion)
                Caret()
                Text(onboarding: "demo.notes.line.suffix")
            }
            .font(.system(size: 15))
            .lineSpacing(7)
            .fixedSize()

            VStack(alignment: .leading, spacing: 10) {
                skeleton(widthFraction: 0.78)
                skeleton(widthFraction: 0.62)
                skeleton(widthFraction: 0.70)
                skeleton(widthFraction: 0.44)
            }
            .padding(.top, 16)
        }
        .foregroundStyle(SceneTheme.label)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 40)
        .padding(.vertical, 32)
    }

    private func skeleton(widthFraction: CGFloat) -> some View {
        Capsule()
            .fill(SceneTheme.tertiaryFill)
            .frame(width: (1320 - 80) * widthFraction, height: 8)
    }
}

/// 2×19 pt, label color, hard on/off every 0.55 s (1.1 s period).
private struct Caret: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.55)) { context in
            Rectangle()
                .fill(SceneTheme.label)
                .frame(width: 2, height: 19)
                .padding(.horizontal, 0.5)
                .opacity(Int(context.date.timeIntervalSinceReferenceDate / 0.55) % 2 == 0 ? 1 : 0)
        }
    }
}

/// Zero-width stand-in for the caret that reports its frame in scene coordinates.
private struct CaretAnchorProbe: View {
    var body: some View {
        Color.clear
            .frame(width: 2, height: 19)
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: CaretFramePreference.self,
                                           value: proxy.frame(in: .named(DemoGeometry.spaceName)))
                }
            }
            .frame(width: 0)
    }
}

struct TrafficLights: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach([0xFF5F57, 0xFEBC2E, 0x28C840], id: \.self) { hex in
                Circle()
                    .fill(Color(hex: UInt32(hex)))
                    .frame(width: 12, height: 12)
            }
        }
    }
}
