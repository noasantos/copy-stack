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

            if let rect = Self.standardCaretRect(in: currentElement)
                ?? Self.webCaretRect(in: currentElement) {
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

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRangeValue,
            &boundsValue
        ) == .success,
        let boundsValue else {
            return nil
        }

        return rect(from: boundsValue)
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

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            markerRangeValue,
            &boundsValue
        ) == .success,
        let boundsValue else {
            return nil
        }

        return rect(from: boundsValue)
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
