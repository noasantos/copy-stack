import AppKit
import ApplicationServices

@MainActor
struct AccessibilityTextCaretLocator {
    func anchorRect(applicationPID: pid_t?, requestPermission: Bool) -> CGRect? {
        guard Self.isTrusted(prompt: requestPermission) else {
            return nil
        }

        let applicationElement = applicationPID.map(AXUIElementCreateApplication)
            ?? AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
        let focusedValue else {
            return nil
        }

        let focusedElement = focusedValue as! AXUIElement
        guard Self.isEditableTextElement(focusedElement) else {
            return nil
        }
        var element: AXUIElement? = focusedElement

        for _ in 0..<6 {
            guard let currentElement = element else {
                break
            }

            if let rect = Self.webCaretRect(in: currentElement)
                ?? Self.standardCaretRect(in: currentElement) {
                return Self.appKitRect(fromQuartzRect: rect)
            }

            element = Self.parent(of: currentElement)
        }

        return nil
    }

    static func isTrusted(prompt: Bool) -> Bool {
        guard prompt else {
            return AXIsProcessTrusted()
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func appKitRect(fromQuartzRect rect: CGRect, primaryScreenMaxY: CGFloat? = nil) -> CGRect? {
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

    static func isEditableTextRole(_ role: String) -> Bool {
        ["AXTextField", "AXTextArea", "AXComboBox"].contains(role)
    }

    private static func standardCaretRect(in element: AXUIElement) -> CGRect? {
        var selectedRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &selectedRangeValue
        ) == .success,
        let selectedRangeValue else {
            return nil
        }

        guard CFGetTypeID(selectedRangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var selectedRange = CFRange()
        guard AXValueGetValue(selectedRangeValue as! AXValue, .cfRange, &selectedRange) else {
            return nil
        }

        var caretRange = CFRange(
            location: selectedRange.location + selectedRange.length,
            length: 0
        )
        guard let caretRangeValue = AXValueCreate(.cfRange, &caretRange) else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            caretRangeValue,
            &boundsValue
        ) == .success,
        let boundsValue else {
            return nil
        }

        guard let bounds = rect(from: boundsValue) else {
            return nil
        }
        return caretRect(at: bounds.minX, characterBounds: bounds)
    }

    private static func webCaretRect(in element: AXUIElement) -> CGRect? {
        var markerRangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXSelectedTextMarkerRange" as CFString,
            &markerRangeValue
        ) == .success,
        let markerRangeValue else {
            return nil
        }

        guard CFGetTypeID(markerRangeValue) == AXTextMarkerRangeGetTypeID() else {
            return nil
        }

        let markerRange = markerRangeValue as! AXTextMarkerRange
        let caretMarker = AXTextMarkerRangeCopyEndMarker(markerRange)

        let collapsedRange = AXTextMarkerRangeCreate(nil, caretMarker, caretMarker)
        if let collapsedBounds = markerBounds(for: collapsedRange, in: element),
           let caret = caretRect(at: collapsedBounds.minX, characterBounds: collapsedBounds) {
            return caret
        }

        if let previousMarker = adjacentMarker(
            named: "AXPreviousTextMarkerForTextMarker",
            from: caretMarker,
            in: element
        ),
        let characterBounds = markerBounds(
            from: previousMarker,
            to: caretMarker,
            in: element
        ),
        let caret = caretRect(at: characterBounds.maxX, characterBounds: characterBounds) {
            return caret
        }

        if let nextMarker = adjacentMarker(
            named: "AXNextTextMarkerForTextMarker",
            from: caretMarker,
            in: element
        ),
        let characterBounds = markerBounds(
            from: caretMarker,
            to: nextMarker,
            in: element
        ),
        let caret = caretRect(at: characterBounds.minX, characterBounds: characterBounds) {
            return caret
        }

        guard let selectedRange = selectedTextRange(in: element),
              selectedRange.location == 0,
              selectedRange.length == 0,
              let lineBounds = markerBounds(for: markerRange, in: element),
              let fieldBounds = elementFrame(element),
              lineBounds.intersects(fieldBounds),
              lineBounds.height > 0 else {
            return nil
        }

        return CGRect(
            x: lineBounds.minX,
            y: lineBounds.minY,
            width: 1,
            height: lineBounds.height
        )
    }

    private static func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
        let rangeValue,
        CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else {
            return nil
        }
        return range
    }

    static func caretRect(at x: CGFloat, characterBounds: CGRect) -> CGRect? {
        guard characterBounds.origin.x.isFinite,
              characterBounds.origin.y.isFinite,
              characterBounds.width.isFinite,
              characterBounds.height.isFinite,
              characterBounds.height > 0,
              characterBounds.width >= 0,
              characterBounds.width <= 128,
              x.isFinite else {
            return nil
        }

        return CGRect(
            x: x,
            y: characterBounds.minY,
            width: 1,
            height: characterBounds.height
        )
    }

    private static func adjacentMarker(
        named attribute: String,
        from marker: AXTextMarker,
        in element: AXUIElement
    ) -> AXTextMarker? {
        var markerValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            attribute as CFString,
            marker,
            &markerValue
        ) == .success,
        let markerValue,
        CFGetTypeID(markerValue) == AXTextMarkerGetTypeID() else {
            return nil
        }

        return (markerValue as! AXTextMarker)
    }

    private static func markerBounds(
        from startMarker: AXTextMarker,
        to endMarker: AXTextMarker,
        in element: AXUIElement
    ) -> CGRect? {
        let range = AXTextMarkerRangeCreate(nil, startMarker, endMarker)
        return markerBounds(for: range, in: element)
    }

    private static func markerBounds(
        for range: AXTextMarkerRange,
        in element: AXUIElement
    ) -> CGRect? {
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            range,
            &boundsValue
        ) == .success,
        let boundsValue else {
            return nil
        }

        return rect(from: boundsValue)
    }

    private static func elementFrame(_ element: AXUIElement) -> CGRect? {
        var frameValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            "AXFrame" as CFString,
            &frameValue
        ) == .success,
        let frameValue else {
            return nil
        }

        return rect(from: frameValue)
    }

    private static func isEditableTextElement(_ element: AXUIElement) -> Bool {
        var roleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &roleValue
        ) == .success,
        let role = roleValue as? String else {
            return false
        }

        return isEditableTextRole(role)
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var parentValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &parentValue
        ) == .success,
        let parentValue,
        CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
            return nil
        }

        return (parentValue as! AXUIElement)
    }

    private static func rect(from value: CFTypeRef) -> CGRect? {
        guard CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(value as! AXValue, .cgRect, &rect),
              rect.width > 0 || rect.height > 0 else {
            return nil
        }
        return rect
    }
}
