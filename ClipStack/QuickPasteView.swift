import AppKit
import SwiftUI

@MainActor
final class QuickPasteSession: ObservableObject {
    static let pageSize = 10

    @Published var selectedID: UUID?
    @Published private(set) var visibleLimit = pageSize
    @Published private(set) var keyboardNavigationRevision = 0

    func reset(with sourceItems: [ClipboardItem]) {
        visibleLimit = min(Self.pageSize, sourceItems.count)
        selectedID = visibleItems(from: sourceItems).first?.id
        keyboardNavigationRevision = 0
    }

    func visibleItems(from sourceItems: [ClipboardItem]) -> [ClipboardItem] {
        Array(sourceItems.prefix(visibleLimit))
    }

    func hasEarlierItems(in sourceItems: [ClipboardItem]) -> Bool {
        visibleLimit < sourceItems.count
    }

    func nextPageCount(totalCount: Int) -> Int {
        min(Self.pageSize, max(0, totalCount - visibleLimit))
    }

    func loadEarlierItems(totalCount: Int) {
        visibleLimit = min(totalCount, visibleLimit + Self.pageSize)
    }

    func reconcile(with items: [ClipboardItem]) {
        guard !items.isEmpty else {
            selectedID = nil
            return
        }

        if let selectedID, items.contains(where: { $0.id == selectedID }) {
            return
        }

        selectedID = items.first?.id
    }

    func moveSelection(by offset: Int, within items: [ClipboardItem]) {
        guard !items.isEmpty else {
            selectedID = nil
            return
        }

        guard let selectedID,
              let selectedIndex = items.firstIndex(where: { $0.id == selectedID }) else {
            self.selectedID = items.first?.id
            keyboardNavigationRevision += 1
            return
        }

        let nextIndex = min(max(selectedIndex + offset, 0), items.count - 1)
        self.selectedID = items[nextIndex].id
        keyboardNavigationRevision += 1
    }

    func selectedItem(in items: [ClipboardItem]) -> ClipboardItem? {
        items.first(where: { $0.id == selectedID }) ?? items.first
    }
}

struct QuickPasteView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var session: QuickPasteSession
    let direction: QuickPasteDirection
    let onPaste: (ClipboardItem) -> Void
    let onDismiss: () -> Void

    private var items: [ClipboardItem] {
        session.visibleItems(from: store.items)
    }

    var body: some View {
        ZStack {
            QuickPasteBubbleShape(direction: direction)
                .fill(.ultraThinMaterial)

            content
                .padding(.top, direction == .below ? 8 : 0)
                .padding(.bottom, direction == .above ? 8 : 0)
        }
        .clipShape(QuickPasteBubbleShape(direction: direction))
        .onAppear {
            session.reconcile(with: items)
        }
        .onChange(of: store.items.map(\.id)) { _ in
            session.reconcile(with: items)
        }
        .onExitCommand(perform: onDismiss)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clipboard")
                    .font(.system(size: 24, weight: .medium))
                Text("No clipboard history yet")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(items) { item in
                            QuickPasteRow(
                                item: item,
                                isSelected: session.selectedID == item.id,
                                onSelect: {
                                    onPaste(item)
                                }
                            )
                            .id(item.id)
                            .scaleEffect(x: 1, y: -1)
                        }

                        if session.hasEarlierItems(in: store.items) {
                            loadEarlierButton
                                .scaleEffect(x: 1, y: -1)
                        }
                    }
                    .padding(7)
                }
                .scaleEffect(x: 1, y: -1)
                .onChange(of: session.keyboardNavigationRevision) { _ in
                    guard let selectedID = session.selectedID else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private var loadEarlierButton: some View {
        let count = session.nextPageCount(totalCount: store.items.count)

        return Button {
            session.loadEarlierItems(totalCount: store.items.count)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Show \(count) earlier")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Load older clipboard items")
    }
}

private struct QuickPasteRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                thumbnail

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.previewText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(Self.timeFormatter.string(from: item.timestamp))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 47, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(rowBackground)
        }
        .onHover { isHovered = $0 }
        .accessibilityLabel(item.previewText)
        .accessibilityHint("Paste this clipboard item")
    }

    private var rowBackground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.16)
        }
        return isHovered ? Color.primary.opacity(0.06) : .clear
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.imageValue {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(3)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct QuickPasteBubbleShape: Shape {
    let direction: QuickPasteDirection

    func path(in rect: CGRect) -> Path {
        let pointerHeight = CGFloat(8)
        let bubbleRect: CGRect
        switch direction {
        case .below:
            bubbleRect = CGRect(
                x: rect.minX,
                y: rect.minY + pointerHeight,
                width: rect.width,
                height: rect.height - pointerHeight
            )
        case .above:
            bubbleRect = CGRect(
                x: rect.minX,
                y: rect.minY,
                width: rect.width,
                height: rect.height - pointerHeight
            )
        }

        var path = Path(roundedRect: bubbleRect, cornerRadius: 16)
        var pointer = Path()
        let centerX = rect.minX + 32
        let halfWidth = CGFloat(9)

        switch direction {
        case .below:
            pointer.move(to: CGPoint(x: centerX, y: rect.minY))
            pointer.addLine(to: CGPoint(x: centerX + halfWidth, y: bubbleRect.minY + 1))
            pointer.addLine(to: CGPoint(x: centerX - halfWidth, y: bubbleRect.minY + 1))
        case .above:
            pointer.move(to: CGPoint(x: centerX - halfWidth, y: bubbleRect.maxY - 1))
            pointer.addLine(to: CGPoint(x: centerX + halfWidth, y: bubbleRect.maxY - 1))
            pointer.addLine(to: CGPoint(x: centerX, y: rect.maxY))
        }
        pointer.closeSubpath()
        path.addPath(pointer)
        return path
    }
}
