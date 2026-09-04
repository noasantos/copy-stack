import XCTest
@testable import ClipStack

@MainActor
final class OnboardingModelTests: XCTestCase {
    private var savedCompleted: Any?
    private var savedBuild: Any?

    override func setUp() {
        super.setUp()
        savedCompleted = UserDefaults.standard.object(forKey: Permissions.hasCompletedOnboardingKey)
        savedBuild = UserDefaults.standard.object(forKey: Permissions.lastGrantedAccessibilityBuildKey)
    }

    override func tearDown() {
        UserDefaults.standard.set(savedCompleted, forKey: Permissions.hasCompletedOnboardingKey)
        UserDefaults.standard.set(savedBuild, forKey: Permissions.lastGrantedAccessibilityBuildKey)
        super.tearDown()
    }

    private func makeModel() -> OnboardingModel {
        let model = OnboardingModel()
        model.stopPolling()
        return model
    }

    func testStepOrderPutsDemosBeforePermissions() {
        XCTAssertEqual(OnboardingModel.Step.allCases,
                       [.welcome, .quickPaste, .capture, .accessibility, .screenRecording, .done])
    }

    func testContinueIsBlockedOnlyWhileAccessibilityIsWaiting() {
        let model = makeModel()
        model.accessibility = .waiting
        model.screenRecording = .waiting

        for step in OnboardingModel.Step.allCases {
            model.step = step
            XCTAssertEqual(model.canContinue, step != .accessibility, "step \(step)")
        }
    }

    func testSkippingAccessibilityUnblocksContinue() {
        let model = makeModel()
        model.step = .accessibility
        model.accessibility = .waiting
        XCTAssertFalse(model.canContinue)

        model.notNow()
        XCTAssertEqual(model.accessibility, .skipped)
        XCTAssertTrue(model.canContinue)
    }

    func testNextAndBackTrackDirection() {
        let model = makeModel()
        model.accessibility = .granted

        model.next()
        XCTAssertEqual(model.step, .quickPaste)
        XCTAssertEqual(model.direction, 1)

        model.back()
        XCTAssertEqual(model.step, .welcome)
        XCTAssertEqual(model.direction, -1)

        model.back()
        XCTAssertEqual(model.step, .welcome, "Welcome is the first step")
    }

    func testNextDoesNothingWhileAccessibilityIsWaiting() {
        let model = makeModel()
        model.step = .accessibility
        model.accessibility = .waiting

        model.next()
        XCTAssertEqual(model.step, .accessibility)
    }

    func testFinishMarksOnboardingComplete() {
        UserDefaults.standard.removeObject(forKey: Permissions.hasCompletedOnboardingKey)
        var finished = false
        let model = makeModel()
        model.onFinish = { finished = true }

        model.finish()

        XCTAssertTrue(finished)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Permissions.hasCompletedOnboardingKey))
    }

    func testSkipSetupFinishesAndRecordsTheSkip() {
        UserDefaults.standard.removeObject(forKey: Permissions.hasCompletedOnboardingKey)
        let model = makeModel()
        model.skipSetup()

        XCTAssertTrue(model.skippedOnboarding)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: Permissions.hasCompletedOnboardingKey))
    }

    func testScreenRecordingAsksBeforeFallingBackToSettings() {
        let model = makeModel()
        model.step = .screenRecording
        XCTAssertFalse(model.screenRecordingNeedsRelaunch)

        model.allowCurrentPermission()

        // The relaunch affordance appears only when macOS refused to prompt, which is exactly
        // when System Settings — and therefore a restart — is the only remaining route.
        XCTAssertEqual(model.screenRecordingNeedsRelaunch, !Permissions.screenRecordingGranted)
    }

    func testReauthorizationOnlyAppliesAfterABuildChange() {
        UserDefaults.standard.removeObject(forKey: Permissions.lastGrantedAccessibilityBuildKey)
        XCTAssertFalse(Permissions.needsReauthorization, "never granted, so nothing was lost")

        Permissions.rememberAccessibilityGrant()
        XCTAssertFalse(Permissions.needsReauthorization, "same build")

        UserDefaults.standard.set(Permissions.currentBuild + ".old", forKey: Permissions.lastGrantedAccessibilityBuildKey)
        XCTAssertEqual(Permissions.needsReauthorization, !Permissions.accessibilityGranted)
    }
}
