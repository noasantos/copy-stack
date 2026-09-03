import Carbon
import os

private let quickPasteHotKeyLogger = Logger(subsystem: "com.clipstack.app", category: "quick-paste")

final class GlobalQuickPasteHotKey: @unchecked Sendable {
    static let hotKeyID = EventHotKeyID(signature: 0x4353544B, id: 2)
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
            { _, event, userData in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }

                let owner = Unmanaged<GlobalQuickPasteHotKey>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                guard GlobalQuickPasteHotKey.matches(event: event) else {
                    return OSStatus(eventNotHandledErr)
                }
                quickPasteHotKeyLogger.info("Shift-Command-V received")
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

        quickPasteHotKeyLogger.info("Shift-Command-V registered")
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

    static func matches(id: EventHotKeyID) -> Bool {
        id.signature == hotKeyID.signature && id.id == hotKeyID.id
    }

    private static func matches(event: EventRef) -> Bool {
        var receivedID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &receivedID
        )
        return status == noErr && matches(id: receivedID)
    }
}
