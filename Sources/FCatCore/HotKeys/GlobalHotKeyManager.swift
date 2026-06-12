import Carbon
import Foundation

public final class GlobalHotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    public init() {}

    deinit { unregister() }

    public func register(_ hotKey: HotKey, action: @escaping () -> Void) throws {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        // Use passRetained to ensure the callback has a valid reference even if ARC
        // collects the manager between register and callback invocation.
        let selfPointer = UnsafeMutableRawPointer(Unmanaged.passRetained(self).toOpaque())
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                // takeRetainedValue balances the passRetained from register;
                // but the manager must stay alive for future callbacks, so
                // we passRetained again before calling action to keep the
                // balance correct across multiple invocations.
                let retained = Unmanaged<GlobalHotKeyManager>.fromOpaque(userData).takeRetainedValue()
                _ = Unmanaged.passRetained(retained).toOpaque() // re-retain for next callback
                DispatchQueue.main.async { retained.action?() }
                return noErr
            },
            1,
            &eventType,
            selfPointer,
            &eventHandler
        )
        guard installStatus == noErr else { throw GlobalHotKeyError.cannotInstallHandler(status: installStatus) }

        let identifier = EventHotKeyID(signature: OSType(0x46434154), id: 1)
        let registerStatus = RegisterEventHotKey(hotKey.keyCode, hotKey.modifiers, identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else { throw GlobalHotKeyError.cannotRegister(status: registerStatus) }
    }

    public func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
        action = nil
    }
}

public enum GlobalHotKeyError: Error, Equatable {
    case cannotInstallHandler(status: OSStatus)
    case cannotRegister(status: OSStatus)
}
