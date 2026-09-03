import AppKit
import ApplicationServices

struct TextCaretAnchorReport {
    /// Caret rect in AppKit screen coordinates, or `nil` when no trustworthy caret exists.
    let rect: CGRect?
    let path: TextCaretPath?
    let trace: [String]
}

@MainActor
struct AccessibilityTextCaretLocator {
    var measurer: any TextRunMeasuring = TextKitRunMeasurer()

    func locate(applicationPID: pid_t?, requestPermission: Bool) -> TextCaretAnchorReport {
        guard Self.isTrusted(prompt: requestPermission) else {
            return TextCaretAnchorReport(rect: nil, path: nil, trace: ["accessibility access is not granted"])
        }

        let applicationElement = applicationPID.map(AXUIElementCreateApplication)
            ?? AXUIElementCreateSystemWide()
        guard let focusedElement = Self.focusedElement(of: applicationElement) else {
            return TextCaretAnchorReport(rect: nil, path: nil, trace: ["no focused accessibility element"])
        }
        let role = Self.role(of: focusedElement) ?? "unknown"
        guard Self.isEditableTextRole(role) else {
            return TextCaretAnchorReport(rect: nil, path: nil, trace: ["focused element role \(role) is not an editable text field"])
        }

        var trace: [String] = []
        var element: AXUIElement? = focusedElement
        for level in 0..<6 {
            guard let currentElement = element else {
                break
            }
            let geometry = AccessibilityTextGeometry(element: currentElement, field: focusedElement)
            // Ancestors are only consulted for document-level text markers; their character
            // ranges do not describe the focused field.
            if level > 0, geometry.selectedMarkerRange() == nil {
                element = Self.parent(of: currentElement)
                continue
            }

            var resolver = TextCaretResolver(source: geometry, measurer: measurer)
            resolver.includeCharacterRanges = level == 0
            let report = resolver.resolve()
            trace += report.trace.map { level == 0 ? $0 : "ancestor \(level): \($0)" }

            if let resolution = report.resolution {
                guard let anchor = Self.appKitRect(fromQuartzRect: resolution.rect) else {
                    trace.append("caret \(TextCaretGeometry.describe(resolution.rect)) could not be converted to AppKit coordinates")
                    return TextCaretAnchorReport(rect: nil, path: resolution.path, trace: trace)
                }
                return TextCaretAnchorReport(rect: anchor, path: resolution.path, trace: trace)
            }
            element = Self.parent(of: currentElement)
        }

        return TextCaretAnchorReport(rect: nil, path: nil, trace: trace)
    }

    nonisolated static func isTrusted(prompt: Bool) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    nonisolated static func appKitRect(fromQuartzRect rect: CGRect, primaryScreenMaxY: CGFloat? = nil) -> CGRect? {
        guard rect.origin.x.isFinite,
              rect.origin.y.isFinite,
              rect.width.isFinite,
              rect.height.isFinite else {
            return nil
        }

        let resolvedPrimaryScreenMaxY = primaryScreenMaxY ?? NSScreen.screens.first?.frame.maxY
        guard let resolvedPrimaryScreenMaxY else {
            return nil
        }

        let width = max(rect.width, 1)
        let height = max(rect.height, 1)
        return CGRect(
            x: rect.origin.x,
            y: resolvedPrimaryScreenMaxY - rect.origin.y - height,
            width: width,
            height: height
        )
    }

    nonisolated static func isEditableTextRole(_ role: String) -> Bool {
        ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
    }

    nonisolated static func focusedElement(of applicationElement: AXUIElement) -> AXUIElement? {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue,
        CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focusedValue as! AXUIElement)
    }

    nonisolated static func role(of element: AXUIElement) -> String? {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success else {
            return nil
        }
        return roleValue as? String
    }

    nonisolated static func parent(of element: AXUIElement) -> AXUIElement? {
        var parentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXParentAttribute as CFString, &parentValue) == .success,
              let parentValue,
              CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return (parentValue as! AXUIElement)
    }
}

/// `TextCaretGeometrySource` backed by the Accessibility API of one element inside a focused field.
struct AccessibilityTextGeometry: TextCaretGeometrySource {
    typealias Marker = AXTextMarker
    typealias Element = AXUIElement

    let element: AXUIElement
    let field: AXUIElement

    var fieldFrame: CGRect? {
        frame(of: field)
    }

    func selectedTextRange() -> CFRange? {
        Self.rangeValue(attribute(kAXSelectedTextRangeAttribute))
    }

    func characterCount() -> Int? {
        attribute(kAXNumberOfCharactersAttribute) as? Int
    }

    func bounds(for range: CFRange) -> CGRect? {
        guard let parameter = Self.rangeParameter(range) else {
            return nil
        }
        return Self.rectValue(parameterized(kAXBoundsForRangeParameterizedAttribute, parameter))
    }

    func string(for range: CFRange) -> String? {
        guard let parameter = Self.rangeParameter(range) else {
            return nil
        }
        return Self.stringValue(parameterized(kAXStringForRangeParameterizedAttribute, parameter))
    }

    func selectedMarkerRange() -> TextMarkerRange<AXTextMarker>? {
        guard let value = attribute("AXSelectedTextMarkerRange"),
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }
        let range = value as! AXTextMarkerRange
        return TextMarkerRange(
            start: AXTextMarkerRangeCopyStartMarker(range),
            end: AXTextMarkerRangeCopyEndMarker(range)
        )
    }

    func marker(before marker: AXTextMarker) -> AXTextMarker? {
        Self.markerValue(parameterized("AXPreviousTextMarkerForTextMarker", marker))
    }

    func marker(after marker: AXTextMarker) -> AXTextMarker? {
        Self.markerValue(parameterized("AXNextTextMarkerForTextMarker", marker))
    }

    func bounds(for range: TextMarkerRange<AXTextMarker>) -> CGRect? {
        let markerRange = AXTextMarkerRangeCreate(nil, range.start, range.end)
        return Self.rectValue(parameterized("AXBoundsForTextMarkerRange", markerRange))
    }

    func string(for range: TextMarkerRange<AXTextMarker>) -> String? {
        let markerRange = AXTextMarkerRangeCreate(nil, range.start, range.end)
        return Self.stringValue(parameterized("AXStringForTextMarkerRange", markerRange))
    }

    func element(containing marker: AXTextMarker) -> AXUIElement? {
        Self.elementValue(parameterized("AXUIElementForTextMarker", marker))
    }

    func frame(of element: AXUIElement) -> CGRect? {
        var frameValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFrame" as CFString, &frameValue) == .success else {
            return nil
        }
        return Self.rectValue(frameValue)
    }

    func markerRange(of element: AXUIElement) -> TextMarkerRange<AXTextMarker>? {
        guard let value = parameterized("AXTextMarkerRangeForUIElement", element),
              CFGetTypeID(value) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }
        let range = value as! AXTextMarkerRange
        return TextMarkerRange(
            start: AXTextMarkerRangeCopyStartMarker(range),
            end: AXTextMarkerRangeCopyEndMarker(range)
        )
    }

    func parent(of element: AXUIElement) -> AXUIElement? {
        AccessibilityTextCaretLocator.parent(of: element)
    }

    func isField(_ element: AXUIElement) -> Bool {
        CFEqual(element, field)
    }

    private func attribute(_ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    private func parameterized(_ name: String, _ parameter: CFTypeRef) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &value) == .success else {
            return nil
        }
        return value
    }

    private static func rangeParameter(_ range: CFRange) -> AXValue? {
        var mutableRange = range
        return AXValueCreate(.cfRange, &mutableRange)
    }

    private static func rangeValue(_ value: CFTypeRef?) -> CFRange? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    /// Empty rects are how AX reports "no geometry"; a zero-width rect with height is a caret.
    private static func rectValue(_ value: CFTypeRef?) -> CGRect? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return rect
    }

    private static func stringValue(_ value: CFTypeRef?) -> String? {
        guard let value else {
            return nil
        }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        return nil
    }

    private static func markerValue(_ value: CFTypeRef?) -> AXTextMarker? {
        guard let value, CFGetTypeID(value) == AXTextMarkerGetTypeID() else {
            return nil
        }
        return (value as! AXTextMarker)
    }

    private static func elementValue(_ value: CFTypeRef?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return nil
        }
        return (value as! AXUIElement)
    }
}
