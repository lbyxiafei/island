import Carbon.HIToolbox
import IslandCore

/// Registers a system-wide hotkey through Carbon's `RegisterEventHotKey`.
///
/// Deliberately not `NSEvent.addGlobalMonitorForEvents`: this API needs no
/// Input Monitoring / Accessibility grant, which keeps the POC free of any
/// permission prompt.
final class HotkeyRegistrar {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let handler: () -> Void

    init?(spec: HotkeySpec, handler: @escaping () -> Void) {
        self.handler = handler

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                Unmanaged<HotkeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .handler()
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4953_4C4E), id: 1)  // 'ISLN'
        let registerStatus = RegisterEventHotKey(
            spec.keyCode,
            Self.carbonModifiers(for: spec.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr else {
            if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    private static func carbonModifiers(for modifiers: Set<HotkeySpec.Modifier>) -> UInt32 {
        modifiers.reduce(into: UInt32(0)) { flags, modifier in
            switch modifier {
            case .command: flags |= UInt32(cmdKey)
            case .control: flags |= UInt32(controlKey)
            case .option: flags |= UInt32(optionKey)
            case .shift: flags |= UInt32(shiftKey)
            }
        }
    }
}
