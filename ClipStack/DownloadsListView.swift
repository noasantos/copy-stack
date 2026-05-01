import AppKit
import SwiftUI

struct DownloadsListView: View {
    let items: [DownloadItem]

    var body: some View {
        if items.isEmpty {
            emptyState
        } else {
            downloadsList
        }
    }

    private var downloadsList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(items) { item in
                    DownloadItemRow(item: item)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 9)
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

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 32, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 58, height: 58)
                .clipStackGlass(cornerRadius: 16, interactive: false)

            Text("No recent downloads")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: .infinity)
    }
}

private struct DownloadItemRow: View {
    let item: DownloadItem

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .scaledToFit()
                .padding(5)
                .frame(width: 46, height: 46)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 0.5)
                }
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(metadataText)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
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
        .onDrag {
            if let provider = NSItemProvider(contentsOf: item.url) {
                return provider
            }

            return NSItemProvider(object: item.url as NSURL)
        }
    }

    private var rowFill: Color {
        isHovered
            ? Color(nsColor: .labelColor).opacity(0.10)
            : .clear
    }

    private var metadataText: String {
        let time = Self.timeFormatter.string(from: item.activityDate)
        guard let fileSize = item.fileSize else {
            return time
        }

        return "\(time) - \(Self.byteFormatter.string(fromByteCount: fileSize))"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}
