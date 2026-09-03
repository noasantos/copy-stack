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

    func testKeyboardSelectionStopsAtListEdges() {
        let first = ClipboardItem.text("First")
        let second = ClipboardItem.text("Second")
        let session = QuickPasteSession()
        session.reset(with: [first, second])

        session.moveSelection(by: 1, within: [first, second])
        XCTAssertEqual(session.selectedID, second.id)

        session.moveSelection(by: 1, within: [first, second])
        XCTAssertEqual(session.selectedID, second.id)

        session.moveSelection(by: -1, within: [first, second])
        XCTAssertEqual(session.selectedID, first.id)
    }
}
