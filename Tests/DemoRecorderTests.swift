import XCTest
@testable import ClipStack

@MainActor
final class DemoRecorderTests: XCTestCase {
    func testEveryDemoIsShotInBothAppearances() {
        let names = DemoRecorder.shots.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "shot names double as file names")
        for base in ["quick-paste", "area-capture", "history-popover", "hero"] {
            XCTAssertTrue(names.contains("\(base)-light"))
            XCTAssertTrue(names.contains("\(base)-dark"))
        }
        XCTAssertEqual(DemoRecorder.shots.filter(\.dark).count, DemoRecorder.shots.count / 2)
    }

    /// A clip that is not exactly one loop long does not loop seamlessly, so these have to stay
    /// pinned to the timeline's own totals.
    func testMotionDurationsMatchTheTimelineLoops() {
        XCTAssertEqual(DemoRecorder.Shot.Motion.quickPaste.durationMilliseconds, 7400)
        XCTAssertEqual(DemoRecorder.Shot.Motion.capture.durationMilliseconds, 6600)
        XCTAssertNil(DemoRecorder.Shot.Motion.still.durationMilliseconds)
    }

    func testOnlyTheMovingShotsCarryAShortcutCaption() {
        for shot in DemoRecorder.shots {
            switch shot.motion {
            case .quickPaste: XCTAssertEqual(shot.caption?.letter, "V")
            case .capture: XCTAssertEqual(shot.caption?.letter, "S")
            case .still: XCTAssertNil(shot.caption)
            }
        }
    }

    func testOutputDirectoryIsRequestedOnlyThroughTheEnvironment() {
        XCTAssertNil(DemoRecorder.requestedOutputDirectory,
                     "a test run must never start the recorder")
    }
}
