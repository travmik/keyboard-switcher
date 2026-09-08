import Carbon.HIToolbox
import Foundation

private final class HotkeyContext {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }
}

/// Registers the global ⌥⌘K hotkey via Carbon RegisterEventHotKey (spec §3.5).
public final class HotkeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let context: HotkeyContext

    public init(handler: @escaping () -> Void) {
        context = HotkeyContext(handler: handler)
    }

    public func install() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(context).toOpaque()
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.hotkeyCallback,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard installStatus == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4B_53_57_31) /* "KSW1" */, id: 1)
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_K),
            UInt32(optionKey | cmdKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        return registerStatus == noErr
    }

    public func uninstall() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
        hotKeyRef = nil
        eventHandlerRef = nil
    }

    private static let hotkeyCallback: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return noErr }
        var hotKeyID = EventHotKeyID()
        _ = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        unsafeBitCast(userData, to: HotkeyContext.self).handler()
        return noErr
    }
}
