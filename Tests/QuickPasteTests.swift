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

    func testCaretUsesCharacterEdgeAndRejectsWholeLineBounds() throws {
        let characterBounds = CGRect(x: 120, y: 200, width: 9, height: 18)
        let caret = try XCTUnwrap(
            AccessibilityTextCaretLocator.caretRect(
                at: characterBounds.maxX,
                characterBounds: characterBounds
            )
        )

        XCTAssertEqual(caret, CGRect(x: 129, y: 200, width: 1, height: 18))
        XCTAssertNil(
            AccessibilityTextCaretLocator.caretRect(
                at: 500,
                characterBounds: CGRect(x: 100, y: 200, width: 700, height: 18)
            )
        )

        let collapsedCaret = try XCTUnwrap(
            AccessibilityTextCaretLocator.caretRect(
                at: 240,
                characterBounds: CGRect(x: 240, y: 200, width: 0, height: 18)
            )
        )
        XCTAssertEqual(collapsedCaret, CGRect(x: 240, y: 200, width: 1, height: 18))
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
