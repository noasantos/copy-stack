import Carbon
import Foundation
import os

private let areaCaptureLogger = Logger(subsystem: "com.startapse.ClipStack", category: "area-capture")

enum AreaCaptureExecutionResult: Equatable, Sendable {
    case completed
    case cancelled
    case failed
}

protocol AreaCaptureRunning: Sendable {
    func captureArea(to destinationURL: URL) async -> AreaCaptureExecutionResult
}

struct SystemAreaCaptureRunner: AreaCaptureRunning {
    static let executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")

    static func arguments(for destinationURL: URL) -> [String] {
        ["-i", "-s", destinationURL.path]
    }

    func captureArea(to destinationURL: URL) async -> AreaCaptureExecutionResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = Self.executableURL
            process.arguments = Self.arguments(for: destinationURL)
            process.terminationHandler = { process in
                let fileExists = FileManager.default.fileExists(atPath: destinationURL.path)

                if process.terminationReason == .exit,
                   process.terminationStatus == 0,
                   fileExists {
                    continuation.resume(returning: .completed)
                    return
                }

                if fileExists {
                    try? FileManager.default.removeItem(at: destinationURL)
                }

                let result: AreaCaptureExecutionResult = fileExists ? .failed : .cancelled
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                areaCaptureLogger.error("ClipStack failed to start area capture: \(error, privacy: .private)")
                continuation.resume(returning: .failed)
            }
        }
    }
}

@MainActor
final class InstantAreaCaptureController {
    private let runner: any AreaCaptureRunning
    private let screenshotProcessor: any ScreenshotProcessing
    private let destinationURLProvider: @MainActor () -> URL
    private var captureTask: Task<Void, Never>?

    private(set) var isCapturing = false

    init(
        runner: any AreaCaptureRunning = SystemAreaCaptureRunner(),
        screenshotProcessor: any ScreenshotProcessing,
        destinationURLProvider: @escaping @MainActor () -> URL = InstantAreaCaptureController.makeDestinationURL
    ) {
        self.runner = runner
        self.screenshotProcessor = screenshotProcessor
        self.destinationURLProvider = destinationURLProvider
    }

    @discardableResult
    func captureArea() -> Bool {
        guard !isCapturing else {
            return false
        }

        isCapturing = true
        let destinationURL = destinationURLProvider()
        let runner = runner
        let screenshotProcessor = screenshotProcessor

        captureTask = Task { @MainActor [weak self] in
            let result = await runner.captureArea(to: destinationURL)
            guard let self else {
                return
            }

            defer {
                isCapturing = false
                captureTask = nil
            }

            guard result == .completed else {
                return
            }

            _ = await screenshotProcessor.processScreenshot(at: destinationURL)
        }

        return true
    }

    static func makeDestinationURL() -> URL {
        let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        return desktopURL.appendingPathComponent("Screenshot ClipStack \(UUID().uuidString).png")
    }
}

final class GlobalAreaCaptureHotKey: @unchecked Sendable {
    private static let hotKeyID = EventHotKeyID(signature: 0x4353544B, id: 1)
    static let keyCode = UInt32(kVK_ANSI_S)
    static let modifiers = UInt32(cmdKey | shiftKey)

    private let action: @MainActor @Sendable () -> Void
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?

    init(action: @escaping @MainActor @Sendable () -> Void) {
        self.action = action
    }

    deinit {
        unregister()
    }

    @discardableResult
    func register() -> Bool {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let owner = Unmanaged<GlobalAreaCaptureHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                Task { @MainActor in
                    owner.action()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandler
        )

        guard handlerStatus == noErr else {
            areaCaptureLogger.error("ClipStack failed to install area capture hotkey handler: \(handlerStatus)")
            return false
        }

        let registrationStatus = RegisterEventHotKey(
            Self.keyCode,
            Self.modifiers,
            Self.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKey
        )

        guard registrationStatus == noErr else {
            areaCaptureLogger.error("ClipStack failed to register Shift-Command-S: \(registrationStatus)")
            unregister()
            return false
        }

        return true
    }

    func unregister() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }

        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }
}
