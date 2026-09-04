import XCTest
@testable import ClipStack

@MainActor
final class DemoTimelineTests: XCTestCase {
    func testQuickPasteCuesMapToTheSelectedRow() {
        XCTAssertNil(DemoTimeline.QuickPasteCue.idle.selectedRow)
        XCTAssertNil(DemoTimeline.QuickPasteCue.keysDown.selectedRow)
        XCTAssertEqual(DemoTimeline.QuickPasteCue.open(selected: 0).selectedRow, 0)
        XCTAssertEqual(DemoTimeline.QuickPasteCue.down(selected: 2).selectedRow, 2)
        XCTAssertEqual(DemoTimeline.QuickPasteCue.up(selected: 1).selectedRow, 1)
        XCTAssertEqual(DemoTimeline.QuickPasteCue.returnKey.selectedRow, 1, "highlight stays put while ↩ is held")
        XCTAssertNil(DemoTimeline.QuickPasteCue.pasted.selectedRow, "panel is gone once the text lands")
    }

    func testPanelIsOpenExactlyWhileARowIsSelected() {
        XCTAssertFalse(DemoTimeline.QuickPasteCue.idle.panelOpen)
        XCTAssertFalse(DemoTimeline.QuickPasteCue.keysDown.panelOpen)
        XCTAssertTrue(DemoTimeline.QuickPasteCue.open(selected: 0).panelOpen)
        XCTAssertTrue(DemoTimeline.QuickPasteCue.returnKey.panelOpen)
        XCTAssertFalse(DemoTimeline.QuickPasteCue.pasted.panelOpen)
    }

    func testCaptureCueFlags() {
        XCTAssertFalse(DemoTimeline.CaptureCue.idle.dimmed)
        XCTAssertTrue(DemoTimeline.CaptureCue.crosshair.dimmed)
        XCTAssertTrue(DemoTimeline.CaptureCue.drag.dimmed)
        XCTAssertFalse(DemoTimeline.CaptureCue.release.dimmed, "the dim lifts on release")

        XCTAssertFalse(DemoTimeline.CaptureCue.crosshair.dragged)
        XCTAssertTrue(DemoTimeline.CaptureCue.drag.dragged)
        XCTAssertTrue(DemoTimeline.CaptureCue.landed.dragged)

        XCTAssertTrue(DemoTimeline.CaptureCue.landed.landed)
        XCTAssertFalse(DemoTimeline.CaptureCue.release.landed)
    }

    func testFreezeHoldsACueAndStopsTheLoop() {
        let timeline = DemoTimeline()
        timeline.startQuickPaste()
        timeline.freeze(quickPaste: .down(selected: 2), pressedKeys: [.down])

        XCTAssertEqual(timeline.quickPaste, .down(selected: 2))
        XCTAssertEqual(timeline.capture, .idle)
        XCTAssertEqual(timeline.pressedKeys, [.down])
    }
}
