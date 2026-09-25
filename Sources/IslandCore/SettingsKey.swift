/// What a key press in the settings window should do.
///
/// Recording a hotkey only happens after the user clicks the recorder, so a
/// reflexive ⌘W or Esc closes the window instead of becoming the new hotkey.
public enum SettingsKey: Equatable, Sendable {
    case record(HotkeySpec)
    case reject
    case cancelRecording
    case closeWindow
    /// Not ours; let AppKit handle it (Tab, Space on a button, …).
    case pass

    static let escapeKeyCode: UInt32 = 53
    static let wKeyCode: UInt32 = 13

    public static func action(
        isRecording: Bool, keyCode: UInt32, modifiers: Set<HotkeySpec.Modifier>
    ) -> SettingsKey {
        let isEscape = keyCode == escapeKeyCode && modifiers.isEmpty
        if isRecording {
            if isEscape { return .cancelRecording }
            return HotkeySpec.captured(keyCode: keyCode, modifiers: modifiers).map(record)
                ?? .reject
        }
        if isEscape || (keyCode == wKeyCode && modifiers == [.command]) { return .closeWindow }
        return .pass
    }
}
