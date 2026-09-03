import CoreGraphics
import Foundation

struct TextCaretResolver<Source: TextCaretGeometrySource> {
    let source: Source
    let measurer: any TextRunMeasuring
    var includeCharacterRanges = true

    func resolve() -> TextCaretReport {
        var trace: [String] = []
        let field = source.fieldFrame

        if let resolution = resolveMarkers(field: field, trace: &trace) {
            return TextCaretReport(resolution: resolution, trace: trace)
        }
        if includeCharacterRanges, let resolution = resolveCharacterRanges(field: field, trace: &trace) {
            return TextCaretReport(resolution: resolution, trace: trace)
        }
        return TextCaretReport(resolution: nil, trace: trace)
    }

    private func resolveMarkers(field: CGRect?, trace: inout [String]) -> TextCaretResolution? {
        guard let selection = source.selectedMarkerRange() else {
            trace.append("marker: no selected text marker range")
            return nil
        }
        let caret = selection.end
        let container = source.element(containing: caret)
        let containerFrame = container.flatMap { source.frame(of: $0) }

        // Neighbouring glyphs must share the vertical band of the element that holds the caret;
        // otherwise a marker that jumped to another block would anchor the wrong line.
        func rejection(_ rect: CGRect, text: String?, collapsed: Bool) -> String? {
            if let reason = collapsed
                ? TextCaretGeometry.caretRejection(rect, field: field)
                : TextCaretGeometry.glyphRejection(rect, field: field, text: text) {
                return reason
            }
            if let containerFrame, rect.maxY < containerFrame.minY - 1 || rect.minY > containerFrame.maxY + 1 {
                return "outside the caret container"
            }
            return nil
        }

        if let rect = source.bounds(for: TextMarkerRange(start: caret, end: caret)) {
            if let reason = rejection(rect, text: nil, collapsed: true) {
                trace.append("marker: collapsed bounds \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
            } else {
                return TextCaretResolution(rect: TextCaretGeometry.caret(x: rect.minX, line: rect), path: .markerCollapsed)
            }
        } else {
            trace.append("marker: collapsed bounds unavailable")
        }

        if let previous = source.marker(before: caret) {
            let range = TextMarkerRange(start: previous, end: caret)
            let text = source.string(for: range)
            if TextCaretGeometry.isLineBreak(text) {
                trace.append("marker: previous character is a line break")
            } else if let rect = source.bounds(for: range) {
                if let reason = rejection(rect, text: text, collapsed: false) {
                    trace.append("marker: previous character bounds \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
                } else {
                    return TextCaretResolution(rect: TextCaretGeometry.caret(x: rect.maxX, line: rect), path: .markerPreviousCharacter)
                }
            } else {
                trace.append("marker: previous character bounds unavailable")
            }
        } else {
            trace.append("marker: no previous text marker")
        }

        if let next = source.marker(after: caret) {
            let range = TextMarkerRange(start: caret, end: next)
            let text = source.string(for: range)
            if let rect = source.bounds(for: range) {
                if let reason = rejection(rect, text: text, collapsed: false) {
                    trace.append("marker: next character bounds \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
                } else {
                    return TextCaretResolution(rect: TextCaretGeometry.caret(x: rect.minX, line: rect), path: .markerNextCharacter)
                }
            } else {
                trace.append("marker: next character bounds unavailable")
            }
        } else {
            trace.append("marker: no next text marker")
        }

        return resolveContainer(container, frame: containerFrame, caret: caret, field: field, trace: &trace)
    }

    // Chromium-based apps expose no per-character geometry unless a screen reader is
    // running, but the element that contains the caret still has a frame and a text range.
    private func resolveContainer(
        _ container: Source.Element?,
        frame: CGRect?,
        caret: Source.Marker,
        field: CGRect?,
        trace: inout [String]
    ) -> TextCaretResolution? {
        guard let container else {
            trace.append("marker: no element contains the caret")
            return nil
        }
        guard belongsToField(container) else {
            trace.append("marker: caret container is outside the focused field")
            return nil
        }
        guard let frame else {
            trace.append("marker: caret container has no frame")
            return nil
        }
        if let reason = TextCaretGeometry.lineRejection(frame, field: field) {
            trace.append("marker: caret container frame \(TextCaretGeometry.describe(frame)) rejected: \(reason)")
            return nil
        }
        guard let range = source.markerRange(of: container) else {
            trace.append("marker: caret container has no text marker range")
            return nil
        }

        let text = source.string(for: range) ?? ""
        let content = trimmingTrailingLineBreaks(text)
        if content.isEmpty {
            return TextCaretResolution(rect: TextCaretGeometry.caret(x: frame.minX, line: frame), path: .markerEmptyContainer)
        }

        let prefix = source.string(for: TextMarkerRange(start: range.start, end: caret)) ?? ""
        let prefixLength = min(prefix.utf16.count, content.utf16.count)
        let wrapWidth = source.parent(of: container).flatMap { source.frame(of: $0)?.width } ?? field?.width ?? frame.width
        guard let rect = measurer.caretRect(prefixLength: prefixLength, in: content, runFrame: frame, wrapWidth: wrapWidth) else {
            trace.append("marker: caret could not be measured inside text run \(TextCaretGeometry.describe(frame)) (prefix \(prefixLength)/\(content.utf16.count))")
            return nil
        }
        if let reason = TextCaretGeometry.caretRejection(rect, field: field) {
            trace.append("marker: measured caret \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
            return nil
        }
        return TextCaretResolution(rect: rect, path: .markerMeasuredRun)
    }

    private func belongsToField(_ element: Source.Element) -> Bool {
        var current: Source.Element? = element
        for _ in 0..<12 {
            guard let candidate = current else {
                return false
            }
            if source.isField(candidate) {
                return true
            }
            current = source.parent(of: candidate)
        }
        return false
    }

    private func resolveCharacterRanges(field: CGRect?, trace: inout [String]) -> TextCaretResolution? {
        guard let selection = source.selectedTextRange(), selection.location >= 0, selection.length >= 0 else {
            trace.append("range: no selected text range")
            return nil
        }
        let offset = selection.location + selection.length
        let count = source.characterCount()
        var previousLineBreak: CGRect?

        if offset > 0 {
            let range = CFRange(location: offset - 1, length: 1)
            let text = source.string(for: range)
            if let rect = source.bounds(for: range) {
                if TextCaretGeometry.isLineBreak(text) {
                    previousLineBreak = rect
                    trace.append("range: previous character is a line break")
                } else if let reason = TextCaretGeometry.glyphRejection(rect, field: field, text: text) {
                    trace.append("range: previous character bounds \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
                } else {
                    return TextCaretResolution(rect: TextCaretGeometry.caret(x: rect.maxX, line: rect), path: .rangePreviousCharacter)
                }
            } else {
                trace.append("range: previous character bounds unavailable")
            }
        }

        if count == nil || offset < count! {
            let range = CFRange(location: offset, length: 1)
            let text = source.string(for: range)
            if let rect = source.bounds(for: range) {
                if let reason = TextCaretGeometry.glyphRejection(rect, field: field, text: text) {
                    trace.append("range: next character bounds \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
                } else {
                    return TextCaretResolution(rect: TextCaretGeometry.caret(x: rect.minX, line: rect), path: .rangeNextCharacter)
                }
            } else {
                trace.append("range: next character bounds unavailable")
            }
        } else {
            trace.append("range: caret is at the end of the text")
        }

        // AppKit reports zero-length bounds one line above the caret. Shift them down only
        // when the reported rect contradicts the field frame or the preceding line break.
        guard let raw = source.bounds(for: CFRange(location: offset, length: 0)) else {
            trace.append("range: zero-length bounds unavailable")
            return nil
        }
        var rect = raw
        var shifted = false
        if let field, rect.minY < field.minY - 1 || rect.maxY > field.maxY + 1 {
            rect.origin.y += rect.height
            shifted = true
            trace.append("range: zero-length bounds \(TextCaretGeometry.describe(raw)) fall outside the field; shifted down one line")
        } else if let previousLineBreak, rect.minY < previousLineBreak.maxY - 0.5 {
            rect.origin.y += rect.height
            shifted = true
            trace.append("range: zero-length bounds \(TextCaretGeometry.describe(raw)) overlap the previous line break; shifted down one line")
        }
        if let reason = TextCaretGeometry.caretRejection(rect, field: field) {
            trace.append("range: zero-length bounds \(TextCaretGeometry.describe(rect)) rejected: \(reason)")
            return nil
        }
        return TextCaretResolution(
            rect: TextCaretGeometry.caret(x: rect.minX, line: rect),
            path: shifted ? .rangeZeroLengthShifted : .rangeZeroLength
        )
    }

    private func trimmingTrailingLineBreaks(_ text: String) -> String {
        var scalars = Substring(text)
        while let last = scalars.last, last.isNewline {
            scalars = scalars.dropLast()
        }
        return String(scalars)
    }
}
