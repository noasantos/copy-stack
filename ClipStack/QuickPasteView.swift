import AppKit
import SwiftUI

@MainActor
final class QuickPasteSession: ObservableObject {
    @Published var selectedID: UUID?

    func reset(with items: [ClipboardItem]) {
        selectedID = items.first?.id
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
            return
        }

        let nextIndex = min(max(selectedIndex + offset, 0), items.count - 1)
        self.selectedID = items[nextIndex].id
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
        store.items
    }

    var body: some View {
        VStack(spacing: 0) {
            if direction == .below {
                pointer(edge: .top)
            }

            VStack(spacing: 0) {
                header
                Divider()
                content
                Divider()
                footer
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.75)
            }

            if direction == .above {
                pointer(edge: .bottom)
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            session.reconcile(with: items)
        }
        .onChange(of: store.items.map(\.id)) { _ in
            session.reconcile(with: items)
        }
        .onExitCommand(perform: onDismiss)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Clipboard history")
                .font(.system(size: 13, weight: .semibold))

            Text("\(store.items.count)")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(.horizontal, 13)
        .frame(height: 42)
    }

    @ViewBuilder
    private var content: some View {
        if items.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "clipboard")
                    .font(.system(size: 25, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("No clipboard history yet")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(items) { item in
                            QuickPasteRow(
                                item: item,
                                isSelected: session.selectedID == item.id,
                                onSelect: {
                                    onPaste(item)
                                },
                                onHover: { hovering in
                                    if hovering {
                                        session.selectedID = item.id
                                    }
                                }
                            )
                            .id(item.id)
                        }
                    }
                    .padding(7)
                }
                .onChange(of: session.selectedID) { selectedID in
                    guard let selectedID else {
                        return
                    }
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "return")
            Text("↑↓ to navigate · Return to paste")
            Spacer(minLength: 4)
            Text("⇧⌘V")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .frame(height: 39)
    }

    private func pointer(edge: Edge) -> some View {
        QuickPastePointer(edge: edge)
            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
            .frame(width: 18, height: 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 15)
    }

}

private struct QuickPasteRow: View {
    let item: ClipboardItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onHover: (Bool) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                thumbnail

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.previewText)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(Self.timeFormatter.string(from: item.timestamp))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "return")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : .clear)
        }
        .onHover(perform: onHover)
        .accessibilityLabel(item.previewText)
        .accessibilityHint("Paste this clipboard item")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.imageValue {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(3)
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        } else {
            Image(systemName: "text.alignleft")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct QuickPastePointer: Shape {
    let edge: Edge

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch edge {
        case .top:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        default:
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
