import SwiftUI

/// The real product panel: 320 wide, radius 16, ultraThin material, 8×18 pointer whose tip sits
/// 32 pt from the left edge, five rows plus "Show N earlier".
struct QuickPastePanelMock: View {
    let cue: DemoTimeline.QuickPasteCue
    let items: [DemoData.Item]

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.demoReduceMotion) private var reduceMotion
    @Namespace private var selection

    private var selectedRow: Int? { cue.selectedRow }
    private var isOpen: Bool { cue.panelOpen }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Pointer()
                .fill(SceneTheme.glass)
                .frame(width: 18, height: 8)
                .padding(.leading, 23)
            panel
        }
        .frame(width: 320, alignment: .leading)
        .shadow(color: .black.opacity(0.28), radius: 12, y: 10)
        .opacity(isOpen ? 1 : 0)
        .scaleEffect(isOpen ? 1 : 0.96, anchor: UnitPoint(x: 32 / 320, y: 0))
        .animation(.easeOut(duration: 0.15), value: isOpen)
    }

    private var panel: some View {
        VStack(spacing: 3) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                row(item, index: index)
            }
            showEarlier
        }
        .padding(7)
        .background(glassBackground)
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(SceneTheme.hairline, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var glassBackground: some View {
        GlassPanelBackground(shape: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func row(_ item: DemoData.Item, index: Int) -> some View {
        HStack(spacing: 9) {
            Thumbnail(isImage: item.isImage, size: 34, cornerRadius: 8, lineSpacing: 2.5)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SceneTheme.label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(item.time)
                    .font(.system(size: 10.5))
                    .foregroundStyle(SceneTheme.secondaryLabel)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "return")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SceneTheme.secondaryLabel)
                .frame(width: 11)
                .opacity(selectedRow == index ? 1 : 0)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(minHeight: 47)
        .background {
            if selectedRow == index {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(SceneTheme.accentWash(colorScheme))
                    .matchedGeometryEffect(id: "quickPasteSelection", in: selection)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.12), value: selectedRow)
    }

    private var showEarlier: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 11))
            Text(verbatim: OnboardingStrings.string("paste.showEarlier", DemoData.earlierCount))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(SceneTheme.secondaryLabel)
        .frame(height: 30)
        .frame(maxWidth: .infinity)
    }
}

/// Upward-pointing triangle; the tip sits at the horizontal midpoint of its 18 pt width.
struct Pointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Row thumbnail: a mock page preview for images, a text-lines glyph otherwise.
struct Thumbnail: View {
    let isImage: Bool
    let size: CGFloat
    let cornerRadius: CGFloat
    let lineSpacing: CGFloat

    var body: some View {
        Group {
            if isImage {
                RoundedRectangle(cornerRadius: max(2, cornerRadius - 6), style: .continuous)
                    .fill(SceneTheme.control)
                    .overlay(ruledLines)
                    .clipShape(RoundedRectangle(cornerRadius: max(2, cornerRadius - 6), style: .continuous))
                    .padding(3)
                    .background(SceneTheme.desk, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(SceneTheme.hairline, lineWidth: 0.5))
            } else {
                VStack(spacing: lineSpacing) {
                    bar(width: size * 0.41)
                    bar(width: size * 0.29, trailingInset: size * 0.12)
                    bar(width: size * 0.41)
                    bar(width: size * 0.24, trailingInset: size * 0.18)
                }
                .frame(width: size, height: size)
                .background(SceneTheme.tertiaryFill, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }

    private var ruledLines: some View {
        GeometryReader { proxy in
            let step = size / 6.8
            VStack(spacing: step - 1) {
                ForEach(0..<Int(max(1, proxy.size.height / max(step, 1))), id: \.self) { _ in
                    Rectangle().fill(SceneTheme.separator).frame(height: 1)
                }
            }
            .padding(.top, step)
        }
    }

    private func bar(width: CGFloat, trailingInset: CGFloat = 0) -> some View {
        Rectangle()
            .fill(SceneTheme.secondaryLabel)
            .frame(width: width, height: size > 40 ? 2 : 1.5)
            .padding(.trailing, trailingInset)
    }
}
