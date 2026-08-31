@testable import ClipStack
import Carbon
import Foundation
import XCTest

@MainActor
final class InstantAreaCaptureTests: XCTestCase {
    func testCompletedCaptureProcessesSavedScreenshot() async {
        let destinationURL = URL(fileURLWithPath: "/tmp/Screenshot ClipStack completed.png")
        let processor = ScreenshotProcessorSpy()
        let controller = InstantAreaCaptureController(
            runner: ImmediateAreaCaptureRunner(result: .completed),
            screenshotProcessor: processor,
            destinationURLProvider: { destinationURL }
        )

        XCTAssertTrue(controller.captureArea())
        await waitUntilCaptureFinishes(controller)

        XCTAssertEqual(processor.processedURLs, [destinationURL])
        XCTAssertFalse(controller.isCapturing)
    }

    func testCancelledCaptureDoesNotProcessScreenshot() async {
        let processor = ScreenshotProcessorSpy()
        let controller = InstantAreaCaptureController(
            runner: ImmediateAreaCaptureRunner(result: .cancelled),
            screenshotProcessor: processor,
            destinationURLProvider: { URL(fileURLWithPath: "/tmp/unused.png") }
        )

        XCTAssertTrue(controller.captureArea())
        await waitUntilCaptureFinishes(controller)

        XCTAssertTrue(processor.processedURLs.isEmpty)
        XCTAssertFalse(controller.isCapturing)
    }

    func testRepeatedShortcutDoesNotStartConcurrentCapture() async {
        let runner = SuspendedAreaCaptureRunner()
        let processor = ScreenshotProcessorSpy()
        let controller = InstantAreaCaptureController(
            runner: runner,
            screenshotProcessor: processor,
            destinationURLProvider: { URL(fileURLWithPath: "/tmp/concurrent.png") }
        )

        XCTAssertTrue(controller.captureArea())
        XCTAssertFalse(controller.captureArea())
        await waitUntilInvocationCount(1, runner: runner)
        let firstInvocationCount = await runner.invocationCount
        XCTAssertEqual(firstInvocationCount, 1)

        await runner.finish(with: .cancelled)
        await waitUntilCaptureFinishes(controller)

        XCTAssertTrue(controller.captureArea())
        await waitUntilInvocationCount(2, runner: runner)
        let secondInvocationCount = await runner.invocationCount
        XCTAssertEqual(secondInvocationCount, 2)
        await runner.finish(with: .cancelled)
        await waitUntilCaptureFinishes(controller)
    }

    func testSystemRunnerUsesSelectionOnlyWithoutClipboardOrPostCaptureUIFlags() {
        let destinationURL = URL(fileURLWithPath: "/tmp/capture.png")

        let arguments = SystemAreaCaptureRunner.arguments(for: destinationURL)

        XCTAssertEqual(arguments, ["-i", "-s", destinationURL.path])
        XCTAssertFalse(arguments.contains("-c"))
        XCTAssertFalse(arguments.contains("-u"))
        XCTAssertFalse(arguments.contains("-U"))
    }

    func testGlobalHotKeyUsesShiftCommandS() {
        XCTAssertEqual(GlobalAreaCaptureHotKey.keyCode, UInt32(kVK_ANSI_S))
        XCTAssertEqual(GlobalAreaCaptureHotKey.modifiers, UInt32(cmdKey | shiftKey))
    }

    func testDefaultDestinationIsUniquePNGOnDesktop() {
        let firstURL = InstantAreaCaptureController.makeDestinationURL()
        let secondURL = InstantAreaCaptureController.makeDestinationURL()
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first

        XCTAssertEqual(firstURL.deletingLastPathComponent(), desktopURL)
        XCTAssertEqual(firstURL.pathExtension, "png")
        XCTAssertTrue(firstURL.lastPathComponent.hasPrefix("Screenshot ClipStack "))
        XCTAssertNotEqual(firstURL, secondURL)
    }

    private func waitUntilCaptureFinishes(_ controller: InstantAreaCaptureController) async {
        for _ in 0..<100 where controller.isCapturing {
            await Task.yield()
        }
        XCTAssertFalse(controller.isCapturing)
    }

    private func waitUntilInvocationCount(_ expectedCount: Int, runner: SuspendedAreaCaptureRunner) async {
        for _ in 0..<100 {
            if await runner.invocationCount == expectedCount {
                return
            }
            await Task.yield()
        }
        XCTFail("Capture runner did not reach invocation count \(expectedCount)")
    }
}

private struct ImmediateAreaCaptureRunner: AreaCaptureRunning {
    let result: AreaCaptureExecutionResult

    func captureArea(to destinationURL: URL) async -> AreaCaptureExecutionResult {
        result
    }
}

private actor SuspendedAreaCaptureRunner: AreaCaptureRunning {
    private(set) var invocationCount = 0
    private var continuation: CheckedContinuation<AreaCaptureExecutionResult, Never>?

    func captureArea(to destinationURL: URL) async -> AreaCaptureExecutionResult {
        invocationCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func finish(with result: AreaCaptureExecutionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

@MainActor
private final class ScreenshotProcessorSpy: ScreenshotProcessing {
    private(set) var processedURLs: [URL] = []

    func processScreenshot(at url: URL) async -> ScreenshotProcessingResult {
        processedURLs.append(url)
        return .added
    }
}
