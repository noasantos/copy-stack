import AppKit
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var downloadsStore: DownloadsStore
    @State private var selectedTab: MenuBarTab = .clipboard
    @Namespace private var tabSelectionNamespace
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Hairline()

            content
                .id(selectedTab)
                .transition(tabContentTransition)
                .animation(tabTransitionAnimation, value: selectedTab)

            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .onAppear {
            focusSearchIfNeeded()
        }
        .onChange(of: selectedTab) { _ in
            focusSearchIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                if selectedTab == .clipboard {
                    searchField
                        .transition(tabHeaderTransition)
                } else {
                    downloadsHeaderLabel
                        .transition(tabHeaderTransition)
                }
            }
            .animation(tabTransitionAnimation, value: selectedTab)

            modeToggle
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            Rectangle()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.10))
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            TextField("Search...", text: $store.searchQuery)
                .textFieldStyle(.plain)
                .focused($isSearchFocused)
                .font(.system(size: 14, weight: .regular))

            if !store.searchQuery.isEmpty {
                Button {
                    store.searchQuery = ""
                    isSearchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Circle())
                .help("Clear search")
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
        .contentShape(Capsule())
        .clipStackGlass(cornerRadius: 999, interactive: true)
        .overlay {
            Capsule()
                .stroke(searchFieldStroke, lineWidth: 0.75)
        }
        .onTapGesture {
            isSearchFocused = true
        }
    }

    private var downloadsHeaderLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 13, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            Text("Downloads")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 36)
        .clipStackGlass(cornerRadius: 999, interactive: false)
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.75)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 2) {
            modeButton(.clipboard, systemImage: "clipboard", help: "Clipboard")
            modeButton(.downloads, systemImage: "arrow.down.circle", help: "Downloads")
        }
        .padding(3)
        .frame(height: 36)
        .clipStackGlass(cornerRadius: 999, interactive: true)
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        }
        .animation(tabTransitionAnimation, value: selectedTab)
    }

    private func modeButton(_ tab: MenuBarTab, systemImage: String, help: String) -> some View {
        Button {
            withAnimation(tabTransitionAnimation) {
                selectedTab = tab
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                .frame(width: 30, height: 28)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .background {
            if selectedTab == tab {
                Capsule()
                    .fill(Color(nsColor: .labelColor).opacity(0.12))
                    .matchedGeometryEffect(id: "selectedTab", in: tabSelectionNamespace)
            }
        }
        .help(help)
    }

    private var tabTransitionAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0.08)
    }

    private var tabHeaderTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98, anchor: .center)),
            removal: .opacity.combined(with: .scale(scale: 1.02, anchor: .center))
        )
    }

    private var tabContentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.985, anchor: .top)),
            removal: .opacity.combined(with: .scale(scale: 1.005, anchor: .top))
        )
    }

    private var clipboardCounterBadge: some View {
        Text("\(store.items.count)/\(ClipboardStore.defaultMaxItems)")
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.55), in: Capsule())
    }

    private var searchFieldStroke: Color {
        isSearchFocused
            ? Color.accentColor.opacity(0.46)
            : Color.white.opacity(0.16)
    }

    private var isSearching: Bool {
        !store.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var displayItems: [ClipboardItem] {
        isSearching ? store.searchResults : store.items
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .clipboard:
            if isSearching && displayItems.isEmpty {
                searchEmptyState
            } else if store.items.isEmpty {
                emptyState
            } else {
                historyList
            }
        case .downloads:
            DownloadsListView(items: downloadsStore.items)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "clipboard")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .clipStackGlass(cornerRadius: 16, interactive: false)

            Text("No clipboard history yet")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private var searchEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)

            Text("No matches")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(displayItems) { item in
                    ClipboardItemRow(
                        item: item,
                        onCopy: {
                            copyToClipboard(item)
                        },
                        onDelete: {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                store.remove(id: item.id)
                            }
                        }
                    )
                    .transition(
                        .asymmetric(
                            insertion: .opacity,
                            removal: .opacity
                                .combined(with: .scale(scale: 0.98))
                                .combined(with: .move(edge: .trailing))
                        )
                    )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
            .animation(.easeInOut(duration: 0.18), value: displayItems.map(\.id))
        }
        .frame(maxHeight: .infinity)
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.025),
                    .init(color: .black, location: 0.975),
                    .init(color: .clear, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func copyToClipboard(_ item: ClipboardItem) {
        store.restore(item)
    }

    private var footer: some View {
        HStack {
            GlassFooterButton(title: "Clear All", systemImage: "trash", isDisabled: isClearDisabled) {
                clearCurrentTab()
            }

            Spacer()

            GlassFooterButton(title: "Quit", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var isClearDisabled: Bool {
        switch selectedTab {
        case .clipboard:
            return store.items.isEmpty
        case .downloads:
            return downloadsStore.items.isEmpty
        }
    }

    private func clearCurrentTab() {
        switch selectedTab {
        case .clipboard:
            store.clear()
        case .downloads:
            downloadsStore.clear()
        }
    }

    private func focusSearchIfNeeded() {
        DispatchQueue.main.async {
            isSearchFocused = selectedTab == .clipboard
        }
    }
}

private enum MenuBarTab: Equatable {
    case clipboard
    case downloads
}

private struct ClipboardItemRow: View {
    let item: ClipboardItem
    let onCopy: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isCopyFeedbackVisible = false
    @State private var isDeleteHovered = false
    @State private var copyFeedbackResetTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                guard !isDeleteHovered else {
                    return
                }

                copyWithFeedback()
            } label: {
                HStack(spacing: 12) {
                    thumbnail
                        .overlay {
                            copyOverlay
                        }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.previewText)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)

                        Text(Self.timeFormatter.string(from: item.timestamp))
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .padding(.trailing, 34)
                .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")

            deleteButton
                .padding(.trailing, 9)
        }
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(rowFill)
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .onDisappear {
            copyFeedbackResetTask?.cancel()
        }
    }

    private var rowFill: Color {
        isHovered
            ? Color(nsColor: .labelColor).opacity(0.10)
            : .clear
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = item.imageValue {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(3)
                .frame(width: 46, height: 46)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.quaternary.opacity(0.55))
                Image(systemName: "text.alignleft")
                    .font(.system(size: 20, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 46, height: 46)
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(.white.opacity(0.16), lineWidth: 0.5)
            }
        }
    }

    private var copyOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(copyOverlayFill)
                .opacity(copyOverlayOpacity)

            Image(systemName: isCopyFeedbackVisible ? "checkmark.circle.fill" : "doc.on.doc")
                .font(.system(size: isCopyFeedbackVisible ? 19 : 17, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(copyIconColor)
                .opacity(copyOverlayOpacity)
                .scaleEffect(isCopyFeedbackVisible ? 1.18 : (isHovered ? 1 : 0.88))
        }
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isCopyFeedbackVisible)
        .allowsHitTesting(false)
    }

    private var copyOverlayOpacity: Double {
        isHovered || isCopyFeedbackVisible ? 1 : 0
    }

    private var copyOverlayFill: Color {
        isCopyFeedbackVisible
            ? Color(nsColor: .systemGreen).opacity(0.48)
            : Color.black.opacity(0.18)
    }

    private var copyIconColor: Color {
        isCopyFeedbackVisible
            ? Color.white.opacity(0.98)
            : Color.white.opacity(0.96)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(deleteIconColor)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle()
                        .fill(deleteHoverFill)
                }
                .overlay {
                    Circle()
                        .stroke(deleteStrokeColor, lineWidth: 0.5)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .opacity(isHovered ? 1 : 0)
        .scaleEffect(isHovered ? 1 : 0.92)
        .offset(x: isHovered ? 0 : 5)
        .allowsHitTesting(isHovered)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) {
                isDeleteHovered = hovering
            }
        }
        .help("Delete")
    }

    private var deleteIconColor: Color {
        isDeleteHovered
            ? Color(nsColor: .systemRed).opacity(0.88)
            : Color(nsColor: .labelColor).opacity(0.86)
    }

    private var deleteHoverFill: Color {
        isDeleteHovered
            ? Color(nsColor: .systemRed).opacity(0.13)
            : Color(nsColor: .labelColor).opacity(0.02)
    }

    private var deleteStrokeColor: Color {
        isDeleteHovered
            ? Color(nsColor: .systemRed).opacity(0.20)
            : Color.white.opacity(0.10)
    }

    private func copyWithFeedback() {
        copyFeedbackResetTask?.cancel()

        withAnimation(.spring(response: 0.24, dampingFraction: 0.72)) {
            isCopyFeedbackVisible = true
        }

        copyFeedbackResetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else {
                return
            }

            withAnimation(.easeInOut(duration: 0.22)) {
                isCopyFeedbackVisible = false
            }
        }

        onCopy()
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private struct GlassFooterButton: View {
    let title: String
    let systemImage: String
    var isDisabled = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .foregroundStyle(.primary)
        .clipStackGlass(cornerRadius: 999, interactive: !isDisabled)
        .overlay {
            Capsule()
                .fill(buttonHoverFill)
                .allowsHitTesting(false)
        }
        .overlay {
            Capsule()
                .stroke(.white.opacity(isHovered && !isDisabled ? 0.22 : 0.10), lineWidth: 0.5)
        }
        .onHover { isHovered = $0 }
    }

    private var buttonHoverFill: Color {
        guard isHovered, !isDisabled else {
            return .clear
        }

        return Color(nsColor: .labelColor).opacity(0.07)
    }
}

private struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor).opacity(0.55))
            .frame(height: 0.5)
    }
}

extension View {
    @ViewBuilder
    func clipStackGlass(cornerRadius: CGFloat, interactive: Bool) -> some View {
        if #available(macOS 26.0, *) {
            if interactive {
                glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
            } else {
                glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }
}
