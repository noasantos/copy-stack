import SwiftUI

/// The real product popover at 380 pt: header, N/1000 counter, 58 pt rows, Clear All / Quit footer.
/// The 24×11 arrow keeps pointing at the status item even when the body slides to stay on screen.
struct PopoverMock: View {
    let items: [DemoData.Item]
    let highlightFirst: Bool
    let arrowMidX: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Pointer()
                .fill(SceneTheme.glass)
                .frame(width: 24, height: 11)
                .padding(.leading, max(0, arrowMidX - 12))
            popoverBody
        }
        .frame(width: 380, alignment: .leading)
        .shadow(color: .black.opacity(0.32), radius: 18, y: 16)
    }

    private var popoverBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            counter
            rows
            footer
        }
        .foregroundStyle(SceneTheme.label)
        .frame(width: 380)
        .background(glassBackground)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(SceneTheme.hairline, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var glassBackground: some View {
        GlassPanelBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium))
                Text(verbatim: "Search...")
                    .font(.system(size: 14))
                    .foregroundStyle(SceneTheme.secondaryLabel)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .frame(minHeight: 36)
            .background(capsuleControl)

            Text(verbatim: "Select")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(capsuleControl)

            HStack(spacing: 2) {
                Image(systemName: "clipboard")
                    .font(.system(size: 13))
                    .frame(width: 30, height: 28)
                    .background(SceneTheme.tertiaryFill, in: Capsule())
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(SceneTheme.secondaryLabel)
                    .frame(width: 30, height: 28)
            }
            .padding(3)
            .frame(height: 36)
            .background(capsuleControl)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(SceneTheme.quaternaryFill)
    }

    private var counter: some View {
        Text(verbatim: "\(items.count)/1000")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SceneTheme.secondaryLabel)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(SceneTheme.tertiaryFill, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.top, 8)
    }

    private var rows: some View {
        VStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Thumbnail(isImage: item.isImage, size: 46, cornerRadius: 11, lineSpacing: 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Text(item.time)
                            .font(.system(size: 12))
                            .foregroundStyle(SceneTheme.secondaryLabel)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .frame(minHeight: 58)
                .background(highlightFirst && index == 0 ? SceneTheme.accentWash(colorScheme) : .clear,
                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
    }

    private var footer: some View {
        HStack {
            footerButton("trash", "Clear All")
            Spacer(minLength: 0)
            footerButton("power", "Quit")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    private func footerButton(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium))
            Text(verbatim: title).font(.system(size: 14, weight: .semibold))
        }
        .padding(.horizontal, 16)
        .frame(height: 36)
        .background(capsuleControl)
    }

    private var capsuleControl: some View {
        Capsule()
            .fill(SceneTheme.control)
            .overlay(Capsule().strokeBorder(SceneTheme.separator, lineWidth: 0.5))
    }
}
