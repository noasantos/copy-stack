import Carbon
import os

private let quickPasteHotKeyLogger = Logger(subsystem: "com.startapse.ClipStack", category: "quick-paste")

final class GlobalQuickPasteHotKey: @unchecked Sendable {
    private static let hotKeyID = EventHotKeyID(signature: 0x4353544B, id: 2)
    static let keyCode = UInt32(kVK_ANSI_V)
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

                let owner = Unmanaged<GlobalQuickPasteHotKey>
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
            quickPasteHotKeyLogger.error("ClipStack failed to install quick-paste hotkey handler: \(handlerStatus)")
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
            quickPasteHotKeyLogger.error("ClipStack failed to register Shift-Command-V: \(registrationStatus)")
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
