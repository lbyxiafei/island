/// What a hotkey press should do to the overlay.
///
/// PLAN § Scope #5: the configured hotkey toggles the overlay — it summons it
/// when it is hidden, and dismisses it when it is already on screen. The rule
/// lives here (not in the AppKit layer) so it is covered by tests.
public enum OverlayToggle: Equatable, Sendable {
    case show
    case hide

    public static func hotkeyPress(isOverlayVisible: Bool) -> OverlayToggle {
        isOverlayVisible ? .hide : .show
    }
}
