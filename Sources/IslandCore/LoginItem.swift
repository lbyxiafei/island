/// Whether island is registered to start at login, mapped to a plain enum so
/// the menu logic stays free of `ServiceManagement`.
public enum LoginItemStatus: String, Equatable, Sendable {
    case enabled
    case notRegistered
    /// macOS knows about the registration but the user has to allow it first.
    case requiresApproval
    /// The registration points at an app bundle macOS can no longer find.
    case notFound
}

/// What the "Launch at login" menu item should look like for a given status.
public struct LoginItemMenuPresentation: Equatable, Sendable {
    public let isChecked: Bool
    /// Present when being unchecked is not self-explanatory.
    public let hint: String?

    public static func make(for status: LoginItemStatus) -> LoginItemMenuPresentation {
        switch status {
        case .enabled:
            return LoginItemMenuPresentation(isChecked: true, hint: nil)
        case .notRegistered:
            return LoginItemMenuPresentation(isChecked: false, hint: nil)
        case .requiresApproval:
            return LoginItemMenuPresentation(
                isChecked: false,
                hint: "allow island in System Settings → General → Login Items"
            )
        case .notFound:
            return LoginItemMenuPresentation(
                isChecked: false,
                hint: "move Island.app to /Applications, then try again"
            )
        }
    }
}
