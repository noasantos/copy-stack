import AppKit
import CryptoKit
import Foundation

/// Model for a single clipboard history entry.
enum ClipboardItem: Identifiable, @unchecked Sendable {
    case text(String, id: UUID = UUID(), timestamp: Date = Date())
    case image(NSImage, id: UUID = UUID(), timestamp: Date = Date())

    var id: UUID {
        switch self {
        case .text(_, id: let id, timestamp: _), .image(_, id: let id, timestamp: _):
            return id
        }
    }

    var timestamp: Date {
        switch self {
        case .text(_, id: _, timestamp: let timestamp), .image(_, id: _, timestamp: let timestamp):
            return timestamp
        }
    }

    var textValue: String? {
        guard case .text(let text, id: _, timestamp: _) = self else {
            return nil
        }
        return text
    }

    var imageValue: NSImage? {
        guard case .image(let image, id: _, timestamp: _) = self else {
            return nil
        }
        return image
    }

    var previewText: String {
        switch self {
        case .text(let text, id: _, timestamp: _):
            return text.truncatedPreview(maxLength: 60)
        case .image(let image, id: _, timestamp: _):
            return "Image (\(Int(image.size.width))x\(Int(image.size.height)))"
        }
    }

    func isDuplicate(of other: ClipboardItem) -> Bool {
        switch (self, other) {
        case (.text(let lhs, id: _, timestamp: _), .text(let rhs, id: _, timestamp: _)):
            return lhs == rhs
        case (.image(let lhs, id: _, timestamp: _), .image(let rhs, id: _, timestamp: _)):
            guard lhs.pixelDimensions == rhs.pixelDimensions,
                  let lhsData = lhs.pngDataForDeduplication(),
                  let rhsData = rhs.pngDataForDeduplication() else {
                return false
            }
            return SHA256.hash(data: lhsData) == SHA256.hash(data: rhsData)
        default:
            return false
        }
    }
}

private extension NSImage {
    var pixelDimensions: CGSize? {
        if let bitmap = representations.compactMap({ $0 as? NSBitmapImageRep }).first {
            return CGSize(width: bitmap.pixelsWide, height: bitmap.pixelsHigh)
        }

        var proposedRect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        return CGSize(width: cgImage.width, height: cgImage.height)
    }

    func pngDataForDeduplication() -> Data? {
        var proposedRect = NSRect(origin: .zero, size: size)
        guard let cgImage = cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }
}

private extension String {
    func truncatedPreview(maxLength: Int) -> String {
        let flattened = replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")

        guard flattened.count > maxLength else {
            return flattened
        }

        return String(flattened.prefix(maxLength)) + "..."
    }
}
