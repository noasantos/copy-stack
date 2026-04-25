import AppKit
import CryptoKit
import Foundation
import ImageIO

enum ClipboardImageEncoding: String, Codable, Sendable {
    case png
    case tiff
}

struct ClipboardImage: @unchecked Sendable {
    static let defaultPreviewMaxPixelSize = 512

    let preview: NSImage
    let pixelWidth: Int
    let pixelHeight: Int
    let fingerprint: String
    let originalData: Data?
    let originalFileURL: URL?
    let encoding: ClipboardImageEncoding?

    init(_ image: NSImage, maxPreviewPixelSize: Int = defaultPreviewMaxPixelSize) {
        let dimensions = image.pixelDimensions ?? CGSize(width: image.size.width, height: image.size.height)
        let originalData = image.bestAvailableData()
        let preview = originalData.flatMap {
            Self.makePreview(from: $0, maxPixelSize: maxPreviewPixelSize)?.image
        } ?? image.downsampled(maxPixelSize: maxPreviewPixelSize) ?? image

        self.preview = preview
        self.pixelWidth = max(1, Int(dimensions.width))
        self.pixelHeight = max(1, Int(dimensions.height))
        self.fingerprint = originalData.map(Self.fingerprint(for:)) ?? Self.fingerprint(for: preview)
        self.originalData = originalData
        self.originalFileURL = nil
        self.encoding = originalData.flatMap(Self.encoding(for:)) ?? .tiff
    }

    private init(
        preview: NSImage,
        pixelWidth: Int,
        pixelHeight: Int,
        fingerprint: String,
        originalData: Data?,
        originalFileURL: URL?,
        encoding: ClipboardImageEncoding?
    ) {
        self.preview = preview
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.fingerprint = fingerprint
        self.originalData = originalData
        self.originalFileURL = originalFileURL
        self.encoding = encoding
    }

    static func make(
        data: Data,
        encoding: ClipboardImageEncoding? = nil,
        maxPreviewPixelSize: Int = defaultPreviewMaxPixelSize
    ) -> ClipboardImage? {
        guard let preview = makePreview(from: data, maxPixelSize: maxPreviewPixelSize) else {
            return nil
        }

        return ClipboardImage(
            preview: preview.image,
            pixelWidth: preview.pixelWidth,
            pixelHeight: preview.pixelHeight,
            fingerprint: fingerprint(for: data),
            originalData: data,
            originalFileURL: nil,
            encoding: encoding ?? Self.encoding(for: data)
        )
    }

    static func make(
        fileURL: URL,
        maxPreviewPixelSize: Int = defaultPreviewMaxPixelSize
    ) -> ClipboardImage? {
        guard let preview = makePreview(from: fileURL, maxPixelSize: maxPreviewPixelSize),
              let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return ClipboardImage(
            preview: preview.image,
            pixelWidth: preview.pixelWidth,
            pixelHeight: preview.pixelHeight,
            fingerprint: fingerprint(for: data),
            originalData: nil,
            originalFileURL: fileURL,
            encoding: encoding(for: data)
        )
    }

    @MainActor
    static func make(pasteboard: NSPasteboard) -> ClipboardImage? {
        if let data = pasteboard.data(forType: .png), let image = make(data: data, encoding: .png) {
            return image
        }

        if let data = pasteboard.data(forType: .tiff), let image = make(data: data, encoding: .tiff) {
            return image
        }

        guard let image = NSImage(pasteboard: pasteboard) else {
            return nil
        }

        return ClipboardImage(image)
    }

    func payloadData() -> Data? {
        if let originalData {
            return originalData
        }

        if let originalFileURL, let data = try? Data(contentsOf: originalFileURL) {
            return data
        }

        return preview.pngData()
    }

    func write(to pasteboard: NSPasteboard) -> Bool {
        if let data = payloadData() {
            switch encoding ?? Self.encoding(for: data) ?? .png {
            case .png:
                return pasteboard.setData(data, forType: .png)
            case .tiff:
                return pasteboard.setData(data, forType: .tiff)
            }
        }

        return pasteboard.writeObjects([preview])
    }

    private static func makePreview(from data: Data, maxPixelSize: Int) -> (image: NSImage, pixelWidth: Int, pixelHeight: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }

        return makePreview(from: source, maxPixelSize: maxPixelSize)
    }

    private static func makePreview(from url: URL, maxPixelSize: Int) -> (image: NSImage, pixelWidth: Int, pixelHeight: Int)? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options) else {
            return nil
        }

        return makePreview(from: source, maxPixelSize: maxPixelSize)
    }

    private static func makePreview(from source: CGImageSource, maxPixelSize: Int) -> (image: NSImage, pixelWidth: Int, pixelHeight: Int)? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }

        return (
            NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height)),
            pixelWidth,
            pixelHeight
        )
    }

    private static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func fingerprint(for image: NSImage) -> String {
        guard let data = image.pngData() else {
            return UUID().uuidString
        }

        return fingerprint(for: data)
    }

    private static func encoding(for data: Data) -> ClipboardImageEncoding? {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return .png
        }

        if data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A]) {
            return .tiff
        }

        return nil
    }
}

enum ClipboardItem: Identifiable, @unchecked Sendable {
    case text(String, id: UUID = UUID(), timestamp: Date = Date())
    case image(ClipboardImage, id: UUID = UUID(), timestamp: Date = Date())

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
        return image.preview
    }

    var previewText: String {
        switch self {
        case .text(let text, id: _, timestamp: _):
            return text.truncatedPreview(maxLength: 60)
        case .image(let image, id: _, timestamp: _):
            return "Image (\(image.pixelWidth)x\(image.pixelHeight))"
        }
    }

    func isDuplicate(of other: ClipboardItem) -> Bool {
        switch (self, other) {
        case (.text(let lhs, id: _, timestamp: _), .text(let rhs, id: _, timestamp: _)):
            return lhs == rhs
        case (.image(let lhs, id: _, timestamp: _), .image(let rhs, id: _, timestamp: _)):
            return lhs.pixelWidth == rhs.pixelWidth
                && lhs.pixelHeight == rhs.pixelHeight
                && lhs.fingerprint == rhs.fingerprint
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

    func downsampled(maxPixelSize: Int) -> NSImage? {
        guard let data = bestAvailableData(),
              let preview = ClipboardImage.make(data: data, maxPreviewPixelSize: maxPixelSize)?.preview else {
            return nil
        }

        return preview
    }

    func bestAvailableData() -> Data? {
        pngData() ?? tiffRepresentation
    }

    func pngData() -> Data? {
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
