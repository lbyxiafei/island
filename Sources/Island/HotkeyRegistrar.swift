import Carbon.HIToolbox
import IslandCore

enum HotkeyRegistrationError: Error, LocalizedError {
    case eventHandlerUnavailable
    case carbonStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandlerUnavailable:
            return "could not install the Carbon event handler"
        case .carbonStatus(let status):
            return "RegisterEventHotKey failed (status \(status))"
        }
    }
}

/// Registers the system-wide hotkey through Carbon's `RegisterEventHotKey`.
///
/// Deliberately not `NSEvent.addGlobalMonitorForEvents`: this API needs no Input
/// Monitoring / Accessibility grant, which keeps the app free of permission
/// prompts.
///
/// Registration is swappable at runtime: `register(_:)` replaces whatever was
/// registered before, and throws instead of leaving the app with a hotkey that
/// silently does nothing.
final class HotkeyRegistrar: HotkeyRegistering {
    private let handler: () -> Void
    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRef: EventHotKeyRef?

    init(handler: @escaping () -> Void) {
        self.handler = handler
        installEventHandler()
    }

    deinit {
        unregister()
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    func register(_ spec: HotkeySpec) throws {
        unregister()
        guard eventHandlerRef != nil else { throw HotkeyRegistrationError.eventHandlerUnavailable }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            spec.keyCode,
            Self.carbonModifiers(for: spec.modifiers),
            EventHotKeyID(signature: OSType(0x4953_4C4E), id: 1),  // 'ISLN'
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr else { throw HotkeyRegistrationError.carbonStatus(status) }
        hotKeyRef = ref
    }

    func unregister() {
        guard let hotKeyRef else { return }
        UnregisterEventHotKey(hotKeyRef)
        self.hotKeyRef = nil
    }

    private func installEventHandler() {
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
        if status != noErr {
            eventHandlerRef = nil
        }
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
