import CoreGraphics
import Foundation

struct TextMarkerRange<Marker> {
    let start: Marker
    let end: Marker
}

/// Read-only view of the text geometry an editable element exposes through Accessibility.
/// Every rect is in Accessibility/Quartz coordinates (origin at the top-left of the primary display).
/// Implementations return `nil` whenever the underlying attribute is missing or empty.
protocol TextCaretGeometrySource {
    associatedtype Marker
    associatedtype Element

    var fieldFrame: CGRect? { get }

    func selectedTextRange() -> CFRange?
    func characterCount() -> Int?
    func bounds(for range: CFRange) -> CGRect?
    func string(for range: CFRange) -> String?

    func selectedMarkerRange() -> TextMarkerRange<Marker>?
    func marker(before marker: Marker) -> Marker?
    func marker(after marker: Marker) -> Marker?
    func bounds(for range: TextMarkerRange<Marker>) -> CGRect?
    func string(for range: TextMarkerRange<Marker>) -> String?
    func element(containing marker: Marker) -> Element?
    func frame(of element: Element) -> CGRect?
    func markerRange(of element: Element) -> TextMarkerRange<Marker>?
    func parent(of element: Element) -> Element?
    func isField(_ element: Element) -> Bool
}

enum TextCaretPath: String {
    case markerCollapsed = "marker.collapsed"
    case markerPreviousCharacter = "marker.previous-character"
    case markerNextCharacter = "marker.next-character"
    case markerEmptyContainer = "marker.empty-container"
    case markerMeasuredRun = "marker.measured-run"
    case rangePreviousCharacter = "range.previous-character"
    case rangeNextCharacter = "range.next-character"
    case rangeZeroLength = "range.zero-length"
    case rangeZeroLengthShifted = "range.zero-length-shifted"
}

struct TextCaretResolution: Equatable {
    let rect: CGRect
    let path: TextCaretPath
}

struct TextCaretReport {
    let resolution: TextCaretResolution?
    let trace: [String]
}

enum TextCaretGeometry {
    static let maximumCaretWidth: CGFloat = 4
    static let maximumUnknownGlyphWidth: CGFloat = 128

    static func isLineBreak(_ text: String?) -> Bool {
        guard let text, !text.isEmpty else {
            return false
        }
        return text.allSatisfy { $0.isNewline }
    }

    static func isSingleGlyph(_ text: String?) -> Bool {
        guard let text else {
            return false
        }
        return text.count == 1 && !text.unicodeScalars.contains("\u{FFFC}")
    }

    static func caret(x: CGFloat, line: CGRect) -> CGRect {
        CGRect(x: x, y: line.minY, width: 1, height: line.height)
    }

    /// Reasons a rect cannot stand for the line that contains the caret.
    static func lineRejection(_ rect: CGRect, field: CGRect?) -> String? {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite, rect.width.isFinite, rect.height.isFinite else {
            return "non-finite"
        }
        guard rect.height > 0, rect.width >= 0 else {
            return "empty"
        }
        guard let field else {
            return nil
        }
        if rect.height > field.height + 1 {
            return "taller than the field"
        }
        if !rect.intersects(field.insetBy(dx: -1, dy: -1)) {
            return "outside the field"
        }
        if rect.width >= field.width * 0.9, rect.height >= field.height * 0.9 {
            return "matches the whole field"
        }
        return nil
    }

    /// Reasons a rect cannot stand for the collapsed caret itself.
    static func caretRejection(_ rect: CGRect, field: CGRect?) -> String? {
        if let reason = lineRejection(rect, field: field) {
            return reason
        }
        if rect.width > maximumCaretWidth {
            return "wider than a caret"
        }
        return nil
    }

    /// Reasons a rect cannot stand for a single character next to the caret.
    static func glyphRejection(_ rect: CGRect, field: CGRect?, text: String?) -> String? {
        if let reason = lineRejection(rect, field: field) {
            return reason
        }
        if let text, !isSingleGlyph(text), !isLineBreak(text) {
            return "spans more than one character"
        }
        if isLineBreak(text) {
            // Line-break glyphs legitimately stretch to the end of their line.
            if let field, rect.width > field.width + 1 {
                return "wider than the field"
            }
            return nil
        }
        if rect.width > max(maximumUnknownGlyphWidth, rect.height * 3) {
            return "wider than a character"
        }
        return nil
    }

    static func describe(_ rect: CGRect) -> String {
        String(format: "(%.1f, %.1f, %.1f, %.1f)", rect.origin.x, rect.origin.y, rect.width, rect.height)
    }
}
