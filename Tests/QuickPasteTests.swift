@testable import ClipStack
import Carbon
import XCTest

@MainActor
final class QuickPasteTests: XCTestCase {
    func testGlobalHotKeyUsesShiftCommandV() {
        XCTAssertEqual(GlobalQuickPasteHotKey.keyCode, UInt32(kVK_ANSI_V))
        XCTAssertEqual(GlobalQuickPasteHotKey.modifiers, UInt32(cmdKey | shiftKey))
        XCTAssertNotEqual(GlobalQuickPasteHotKey.modifiers, UInt32(cmdKey))
    }

    func testQuickPasteHotKeyIgnoresAreaCaptureEvents() {
        XCTAssertTrue(GlobalQuickPasteHotKey.matches(id: GlobalQuickPasteHotKey.hotKeyID))
        XCTAssertFalse(GlobalQuickPasteHotKey.matches(id: GlobalAreaCaptureHotKey.hotKeyID))
    }

    func testPlacementOpensBelowWhenRequestedHeightFits() {
        let placement = QuickPastePanelPlacement.make(
            anchor: CGRect(x: 500, y: 600, width: 2, height: 20),
            requestedSize: CGSize(width: 360, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900)
        )

        XCTAssertEqual(placement.direction, .below)
        XCTAssertEqual(placement.frame.maxY, 592, accuracy: 0.001)
        XCTAssertLessThanOrEqual(placement.frame.minY, 162)
    }

    func testPlacementOpensAboveNearBottomEdge() {
        let placement = QuickPastePanelPlacement.make(
            anchor: CGRect(x: 500, y: 40, width: 2, height: 20),
            requestedSize: CGSize(width: 360, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900)
        )

        XCTAssertEqual(placement.direction, .above)
        XCTAssertEqual(placement.frame.minY, 68, accuracy: 0.001)
    }

    func testPlacementClampsToVisibleRightEdge() {
        let placement = QuickPastePanelPlacement.make(
            anchor: CGRect(x: 1_190, y: 600, width: 2, height: 20),
            requestedSize: CGSize(width: 360, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 900)
        )

        XCTAssertEqual(placement.frame.maxX, 1_200, accuracy: 0.001)
    }

    func testPlacementShrinksToAvailableVerticalSpace() {
        let placement = QuickPastePanelPlacement.make(
            anchor: CGRect(x: 500, y: 350, width: 2, height: 20),
            requestedSize: CGSize(width: 360, height: 430),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_200, height: 600)
        )

        XCTAssertEqual(placement.direction, .below)
        XCTAssertEqual(placement.frame.height, 342, accuracy: 0.001)
        XCTAssertEqual(placement.frame.minY, 0, accuracy: 0.001)
    }

    func testAccessibilityCoordinatesConvertToAppKitCoordinates() throws {
        let converted = try XCTUnwrap(
            AccessibilityTextCaretLocator.appKitRect(
                fromQuartzRect: CGRect(x: 100, y: 200, width: 2, height: 18),
                primaryScreenMaxY: 900
            )
        )

        XCTAssertEqual(converted, CGRect(x: 100, y: 682, width: 2, height: 18))
    }

    func testQuickPasteOnlyAcceptsEditableTextRoles() {
        XCTAssertTrue(AccessibilityTextCaretLocator.isEditableTextRole("AXTextField"))
        XCTAssertTrue(AccessibilityTextCaretLocator.isEditableTextRole("AXTextArea"))
        XCTAssertTrue(AccessibilityTextCaretLocator.isEditableTextRole("AXComboBox"))
        XCTAssertFalse(AccessibilityTextCaretLocator.isEditableTextRole("AXButton"))
        XCTAssertFalse(AccessibilityTextCaretLocator.isEditableTextRole("AXWebArea"))
    }

    func testCaretGeometryRejectsWholeLineWholeFieldAndNonFiniteRects() {
        let field = CGRect(x: 181, y: 134, width: 656, height: 384)
        let glyph = CGRect(x: 220, y: 200, width: 9, height: 18)

        XCTAssertNil(TextCaretGeometry.glyphRejection(glyph, field: field, text: "o"))
        XCTAssertEqual(TextCaretGeometry.caret(x: glyph.maxX, line: glyph), CGRect(x: 229, y: 200, width: 1, height: 18))
        XCTAssertEqual(TextCaretGeometry.glyphRejection(CGRect(x: 120, y: 200, width: 9, height: 18), field: field, text: "o"), "outside the field")
        XCTAssertEqual(
            TextCaretGeometry.glyphRejection(CGRect(x: 191, y: 134, width: 636, height: 13), field: field, text: "x"),
            "wider than a character"
        )
        XCTAssertNil(TextCaretGeometry.glyphRejection(CGRect(x: 191, y: 134, width: 636, height: 13), field: field, text: "\n"))
        XCTAssertEqual(
            TextCaretGeometry.glyphRejection(CGRect(x: 191, y: 134, width: 636, height: 13), field: field, text: nil),
            "wider than a character"
        )
        XCTAssertEqual(
            TextCaretGeometry.caretRejection(CGRect(x: 191, y: 134, width: 636, height: 13), field: field),
            "wider than a caret"
        )
        XCTAssertEqual(TextCaretGeometry.caretRejection(field, field: field), "matches the whole field")
        XCTAssertEqual(TextCaretGeometry.lineRejection(CGRect(x: CGFloat.nan, y: 0, width: 1, height: 1), field: field), "non-finite")
        XCTAssertEqual(TextCaretGeometry.lineRejection(CGRect(x: 10, y: 10, width: 1, height: 13), field: field), "outside the field")
        XCTAssertEqual(TextCaretGeometry.lineRejection(CGRect(x: 200, y: 140, width: 1, height: 0), field: field), "empty")
        XCTAssertNil(TextCaretGeometry.caretRejection(CGRect(x: 240, y: 200, width: 0, height: 18), field: nil))
    }

    func testQuickPasteReopensAfterEscapeAndOutsideClickAtEachNewCaretPosition() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        let anchors = [
            CGRect(x: visible.minX + 200, y: visible.midY, width: 1, height: 18),
            CGRect(x: visible.minX + 500, y: visible.midY - 120, width: 1, height: 18),
            CGRect(x: visible.midX, y: visible.minY + 40, width: 1, height: 18)
        ]
        var anchorIndex = 0
        var locatedProcesses: [pid_t] = []
        let environment = QuickPasteEnvironment(
            frontmostTarget: { QuickPasteTarget(processIdentifier: 4242, application: nil) },
            isAccessibilityTrusted: { true },
            locateCaret: { processIdentifier in
                locatedProcesses.append(processIdentifier)
                return TextCaretAnchorReport(rect: anchors[anchorIndex], path: .rangePreviousCharacter, trace: [])
            }
        )
        let controller = QuickPasteController(store: ClipboardStore(), environment: environment)

        func expectedFrame(_ anchor: CGRect) -> CGRect {
            QuickPastePanelPlacement.make(
                anchor: anchor,
                requestedSize: QuickPasteController.requestedPanelSize,
                visibleFrame: visible
            ).frame
        }

        // AppKit snaps window origins to whole points, so compare with a one-point tolerance.
        func assertPanel(at expected: CGRect, line: UInt = #line) {
            guard let frame = controller.panelFrame else {
                XCTFail("panel not visible", line: line)
                return
            }
            XCTAssertEqual(frame.minX, expected.minX, accuracy: 1, line: line)
            XCTAssertEqual(frame.minY, expected.minY, accuracy: 1, line: line)
            XCTAssertEqual(frame.size, expected.size, line: line)
        }

        controller.toggle()
        XCTAssertTrue(controller.isPanelVisible)
        XCTAssertTrue(controller.hasEventMonitors)
        assertPanel(at: expectedFrame(anchors[0]))

        XCTAssertTrue(controller.handleKeyDown(keyCode: kVK_Escape))
        XCTAssertFalse(controller.isPanelVisible)
        XCTAssertFalse(controller.hasEventMonitors)

        anchorIndex = 1
        controller.toggle()
        XCTAssertTrue(controller.isPanelVisible)
        assertPanel(at: expectedFrame(anchors[1]))

        controller.handleOutsideClick()
        XCTAssertFalse(controller.isPanelVisible)
        XCTAssertFalse(controller.hasEventMonitors)

        anchorIndex = 2
        controller.toggle()
        XCTAssertTrue(controller.isPanelVisible)
        assertPanel(at: expectedFrame(anchors[2]))
        XCTAssertEqual(controller.lastAnchorReport?.path, .rangePreviousCharacter)

        controller.dismiss()
        XCTAssertFalse(controller.isPanelVisible)
        XCTAssertEqual(locatedProcesses, [4242, 4242, 4242])
    }

    func testRepeatedHotKeyFollowsTheCaretAcrossPositions() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        var anchor = CGRect(x: visible.minX + 100, y: visible.maxY - 100, width: 1, height: 16)
        let environment = QuickPasteEnvironment(
            frontmostTarget: { QuickPasteTarget(processIdentifier: 7, application: nil) },
            isAccessibilityTrusted: { true },
            locateCaret: { _ in TextCaretAnchorReport(rect: anchor, path: .markerMeasuredRun, trace: []) }
        )
        let controller = QuickPasteController(store: ClipboardStore(), environment: environment)

        for step in 0..<5 {
            anchor = CGRect(x: visible.minX + 100 + CGFloat(step) * 90, y: visible.maxY - 100 - CGFloat(step) * 60, width: 1, height: 16)
            controller.toggle()
            XCTAssertTrue(controller.isPanelVisible, "step \(step)")
            let expected = QuickPastePanelPlacement.make(
                anchor: anchor,
                requestedSize: QuickPasteController.requestedPanelSize,
                visibleFrame: visible
            )
            let frame = try XCTUnwrap(controller.panelFrame, "step \(step)")
            XCTAssertEqual(frame.minX, expected.frame.minX, accuracy: 1, "step \(step)")
            XCTAssertEqual(frame.minY, expected.frame.minY, accuracy: 1, "step \(step)")
            XCTAssertEqual(frame.size, expected.frame.size, "step \(step)")
            controller.toggle()
            XCTAssertFalse(controller.isPanelVisible, "step \(step)")
        }
    }

    private func makeController(
        anchor: @escaping @MainActor () -> CGRect?,
        store: ClipboardStore = ClipboardStore()
    ) -> QuickPasteController {
        let environment = QuickPasteEnvironment(
            frontmostTarget: { QuickPasteTarget(processIdentifier: 4242, application: nil) },
            isAccessibilityTrusted: { true },
            locateCaret: { _ in TextCaretAnchorReport(rect: anchor(), path: .rangePreviousCharacter, trace: []) }
        )
        return QuickPasteController(store: store, environment: environment)
    }

    func testUnhandledKeysCloseThePanelWhileModifiersDoNot() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        let controller = makeController(anchor: { CGRect(x: visible.midX, y: visible.midY, width: 1, height: 18) })

        controller.toggle()
        XCTAssertTrue(controller.isPanelVisible)
        XCTAssertFalse(controller.handleKeyDown(keyCode: kVK_Shift))
        XCTAssertFalse(controller.handleKeyDown(keyCode: kVK_Command))
        XCTAssertTrue(controller.isPanelVisible)

        XCTAssertFalse(controller.handleKeyDown(keyCode: kVK_ANSI_A))
        XCTAssertFalse(controller.isPanelVisible)
        XCTAssertFalse(controller.hasEventMonitors)
        XCTAssertEqual(controller.lastDismissReason, .unhandledKey)
    }

    func testFocusLossNotificationsCloseThePanel() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        let controller = makeController(anchor: { CGRect(x: visible.midX, y: visible.midY, width: 1, height: 18) })
        let workspace = NSWorkspace.shared.notificationCenter

        let cases: [(Notification.Name, NotificationCenter, QuickPasteDismissReason)] = [
            (NSWorkspace.activeSpaceDidChangeNotification, workspace, .spaceChanged),
            (NSWorkspace.didActivateApplicationNotification, workspace, .applicationSwitched),
            (NSWorkspace.didHideApplicationNotification, workspace, .applicationHidden),
            (NSWorkspace.sessionDidResignActiveNotification, workspace, .sessionInterrupted),
            (NSApplication.didChangeScreenParametersNotification, NotificationCenter.default, .screenChanged)
        ]
        for (name, center, reason) in cases {
            controller.toggle()
            XCTAssertTrue(controller.isPanelVisible, name.rawValue)
            center.post(name: name, object: nil)
            XCTAssertFalse(controller.isPanelVisible, name.rawValue)
            XCTAssertEqual(controller.lastDismissReason, reason, name.rawValue)
            XCTAssertFalse(controller.hasEventMonitors, name.rawValue)
        }

        controller.toggle()
        XCTAssertTrue(controller.isPanelVisible)
        controller.handleFocusLoss(.outsideInteraction)
        XCTAssertFalse(controller.isPanelVisible)
        XCTAssertEqual(controller.lastDismissReason, .outsideInteraction)

        // A notification that arrives after the panel closed must not disturb the next session.
        workspace.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        controller.toggle()
        XCTAssertTrue(controller.isPanelVisible)
        controller.dismiss()
    }

    func testPanelStaysOnTheCaretSpaceInsteadOfFollowingTheUser() {
        XCTAssertTrue(QuickPasteController.panelCollectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(QuickPasteController.panelCollectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertFalse(QuickPasteController.panelCollectionBehavior.contains(.canJoinAllSpaces))
    }

    func testArrowKeysWalkTowardsOlderItemsAwayFromTheCaret() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        let store = ClipboardStore()
        store.add(.text("oldest"))
        store.add(.text("middle"))
        store.add(.text("newest"))
        let newest = try XCTUnwrap(store.items.first)
        let middle = store.items[1]

        // Opens below the caret: newest at the top, so Down walks to older items.
        var anchor = CGRect(x: visible.midX, y: visible.maxY - 30, width: 1, height: 18)
        let controller = makeController(anchor: { anchor }, store: store)
        controller.toggle()
        XCTAssertEqual(controller.presentedDirection, .below)
        XCTAssertEqual(controller.selectedItemID, newest.id)
        XCTAssertTrue(controller.handleKeyDown(keyCode: kVK_DownArrow))
        XCTAssertEqual(controller.selectedItemID, middle.id)
        XCTAssertTrue(controller.handleKeyDown(keyCode: kVK_UpArrow))
        XCTAssertEqual(controller.selectedItemID, newest.id)
        XCTAssertTrue(controller.handleKeyDown(keyCode: kVK_UpArrow))
        XCTAssertEqual(controller.selectedItemID, newest.id)
        controller.dismiss()

        // Opens above the caret: newest at the bottom, so Up walks to older items.
        anchor = CGRect(x: visible.midX, y: visible.minY + 30, width: 1, height: 18)
        controller.toggle()
        XCTAssertEqual(controller.presentedDirection, .above)
        XCTAssertEqual(controller.selectedItemID, newest.id)
        XCTAssertTrue(controller.handleKeyDown(keyCode: kVK_UpArrow))
        XCTAssertEqual(controller.selectedItemID, middle.id)
        XCTAssertTrue(controller.handleKeyDown(keyCode: kVK_DownArrow))
        XCTAssertEqual(controller.selectedItemID, newest.id)
        controller.dismiss()
    }

    func testQuickPasteStaysClosedWithoutTrustworthyCaret() {
        let environment = QuickPasteEnvironment(
            frontmostTarget: { QuickPasteTarget(processIdentifier: 7, application: nil) },
            isAccessibilityTrusted: { true },
            locateCaret: { _ in
                TextCaretAnchorReport(rect: nil, path: nil, trace: ["marker: collapsed bounds unavailable", "range: no selected text range"])
            }
        )
        let controller = QuickPasteController(store: ClipboardStore(), environment: environment)

        controller.toggle()
        XCTAssertFalse(controller.isPanelVisible)
        XCTAssertFalse(controller.hasEventMonitors)
        XCTAssertFalse(controller.handleKeyDown(keyCode: kVK_Escape))
        XCTAssertEqual(controller.lastAnchorReport?.trace.count, 2)
        XCTAssertNil(controller.lastAnchorReport?.rect)
    }

    func testHistoryStartsWithTenNewestInBottomOriginOrder() {
        let sourceItems = (0..<12).map { ClipboardItem.text("Item \($0)") }
        let session = QuickPasteSession()
        session.reset(with: sourceItems)

        let visible = session.visibleItems(from: sourceItems)
        XCTAssertEqual(visible.count, 10)
        XCTAssertEqual(visible.first?.id, sourceItems[0].id)
        XCTAssertEqual(visible.last?.id, sourceItems[9].id)
        XCTAssertEqual(session.selectedID, sourceItems[0].id)
        XCTAssertTrue(session.hasEarlierItems(in: sourceItems))

        session.loadEarlierItems(totalCount: sourceItems.count)
        XCTAssertEqual(session.visibleItems(from: sourceItems).count, 12)
        XCTAssertFalse(session.hasEarlierItems(in: sourceItems))
    }

    func testKeyboardSelectionStopsAtListEdges() {
        let newest = ClipboardItem.text("Newest")
        let older = ClipboardItem.text("Older")
        let session = QuickPasteSession()
        session.reset(with: [newest, older])
        let visible = session.visibleItems(from: [newest, older])

        XCTAssertEqual(session.selectedID, newest.id)

        session.moveSelection(by: 1, within: visible)
        XCTAssertEqual(session.selectedID, older.id)

        session.moveSelection(by: 1, within: visible)
        XCTAssertEqual(session.selectedID, older.id)

        session.moveSelection(by: -1, within: visible)
        XCTAssertEqual(session.selectedID, newest.id)
    }
}
