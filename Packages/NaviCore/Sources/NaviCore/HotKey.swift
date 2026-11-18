import Carbon.HIToolbox

@MainActor
public final class HotKey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var releaseActions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false
    private static let signature: OSType = 0x4E41_5649

    private let id: UInt32
    private var ref: EventHotKeyRef?

    public init?(
        keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void, onRelease: (() -> Void)? = nil
    ) {
        Self.installHandlerIfNeeded()
        id = Self.nextID
        Self.nextID += 1

        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        self.ref = ref
        Self.actions[id] = action
        Self.releaseActions[id] = onRelease
    }

    public func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.actions[id] = nil
        Self.releaseActions[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            guard hotKeyID.signature == HotKey.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
            MainActor.assumeIsolated {
                if released { HotKey.releaseActions[id]?() } else { HotKey.actions[id]?() }
            }
            return noErr
        }, specs.count, &specs, nil, nil)
    }
}
