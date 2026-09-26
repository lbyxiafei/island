import Foundation

/// One row of `tmux list-clients -F '#{client_pid}\t#{client_tty}\t#{client_session}\t#{client_activity}'`.
/// A client is one terminal tab showing tmux; switching it is what actually
/// puts the task's session on screen.
public struct TmuxClient: Equatable, Sendable {
    public let pid: Int32
    public let tty: String
    public let session: String
    public let activity: Int

    public init(pid: Int32, tty: String, session: String, activity: Int) {
        self.pid = pid
        self.tty = tty
        self.session = session
        self.activity = activity
    }

    public static func parse(_ text: String) -> [TmuxClient] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(
                String.init)
            guard fields.count >= 3, let pid = Int32(fields[0]) else { return nil }
            let activity = fields.count > 3 ? Int(fields[3]) ?? 0 : 0
            return TmuxClient(pid: pid, tty: fields[1], session: fields[2], activity: activity)
        }
    }

    /// `island:1.1` -> `island`.
    public static func session(ofPane paneTarget: String) -> String {
        paneTarget.firstIndex(of: ":").map { String(paneTarget[..<$0]) } ?? paneTarget
    }

    /// The client to switch: one already showing the pane's session (least
    /// disruptive), otherwise the one the user touched last.
    public static func pick(_ clients: [TmuxClient], forPane paneTarget: String) -> TmuxClient? {
        let session = session(ofPane: paneTarget)
        let onSession = clients.filter { $0.session == session }
        let candidates = onSession.isEmpty ? clients : onSession
        return candidates.max { $0.activity < $1.activity }
    }
}

/// Reads what `ps` reports about a process.
public enum ProcessEnvironment {
    /// Picks `keys` out of `ps eww -o command= -p <pid>`, which prints the
    /// command line followed by `KEY=value` tokens. Values containing spaces
    /// are cut at the first space, which is fine for the ids island reads.
    public static func parse(_ output: String, keys: Set<String>) -> [String: String] {
        var values: [String: String] = [:]
        for token in output.split(whereSeparator: { $0 == " " || $0 == "\n" }) {
            guard let equals = token.firstIndex(of: "=") else { continue }
            let key = String(token[..<equals])
            guard keys.contains(key), values[key] == nil else { continue }
            values[key] = String(token[token.index(after: equals)...])
        }
        return values
    }

    /// `ps -o tty= -p <pid>` prints `ttys012`, or `??` without a terminal.
    public static func ttyPath(fromPS output: String) -> String? {
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != "??" else { return nil }
        return name.hasPrefix("/dev/") ? name : "/dev/" + name
    }
}

/// The process whose terminal tab island brings forward: the agent itself, or
/// the tmux client showing the agent's pane.
public struct TerminalLeaf: Equatable, Sendable {
    public let pid: Int32
    public let tty: String?

    public init(pid: Int32, tty: String?) {
        self.pid = pid
        self.tty = tty
    }
}

/// How to find one terminal inside an app that scripts like Ghostty (cmux
/// shares its AppleScript dictionary).
public enum TerminalMatch: Equatable, Sendable {
    /// cmux exports `CMUX_SURFACE_ID`, which is the scripting `id` of the terminal.
    case terminalID(String)
    /// Standalone Ghostty exposes no id to the process, so island briefly sets
    /// the tty's title to a unique string and looks the terminal up by name.
    case titleProbe(tty: String)
}

/// Which tab to focus once the hosting app is known. `none` still activates the app.
public enum TerminalTabFocus: Equatable, Sendable {
    case scriptable(bundleID: String, match: TerminalMatch)
    case appleTerminal(tty: String)
    case iTerm(tty: String)
    /// The island VS Code extension shows the terminal whose shell is in `pids`.
    case vscode(pids: [Int32])
    case none

    public static let cmuxBundleID = "com.cmuxterm.app"
    public static let ghosttyBundleID = "com.mitchellh.ghostty"
    public static let terminalBundleID = "com.apple.Terminal"
    public static let iTermBundleID = "com.googlecode.iterm2"
    public static let vscodeBundleID = "com.microsoft.VSCode"
    public static let surfaceKey = "CMUX_SURFACE_ID"

    /// Needs macOS automation consent for the host app.
    public var usesAppleScript: Bool {
        switch self {
        case .scriptable, .appleTerminal, .iTerm: return true
        case .vscode, .none: return false
        }
    }

    /// - Parameters:
    ///   - chain: the leaf's ancestors (`ProcessTree.ancestors`), leaf first.
    ///   - environment: the leaf's environment, at least `surfaceKey` if set.
    public static func plan(
        hostBundleID: String?,
        leaf: TerminalLeaf,
        chain: [Int32],
        environment: [String: String]
    ) -> TerminalTabFocus {
        switch hostBundleID {
        case cmuxBundleID:
            if let surface = environment[surfaceKey], !surface.isEmpty {
                return .scriptable(bundleID: cmuxBundleID, match: .terminalID(surface))
            }
            return leaf.tty.map { .scriptable(bundleID: cmuxBundleID, match: .titleProbe(tty: $0)) }
                ?? .none
        case ghosttyBundleID:
            return leaf.tty.map {
                .scriptable(bundleID: ghosttyBundleID, match: .titleProbe(tty: $0))
            }
                ?? .none
        case terminalBundleID:
            return leaf.tty.map { .appleTerminal(tty: $0) } ?? .none
        case iTermBundleID:
            return leaf.tty.map { .iTerm(tty: $0) } ?? .none
        case vscodeBundleID:
            return .vscode(pids: chain)
        default:
            return .none
        }
    }
}

/// AppleScript sources for the scriptable terminals, kept here so the exact
/// text is under test.
public enum TerminalScript {
    public static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// Raises the window holding the terminal, focuses it, activates the app and
    /// returns the terminal's id ("" when nothing matched). `probe` is the title
    /// written for `.titleProbe`.
    public static func focus(bundleID: String, match: TerminalMatch, probe: String = "") -> String {
        let condition: String
        switch match {
        case .terminalID(let id): condition = "(id of t) is \(quoted(id))"
        case .titleProbe: condition = "(name of t) is \(quoted(probe))"
        }
        return """
            tell application id \(quoted(bundleID))
                repeat with w in windows
                    repeat with t in terminals of w
                        if \(condition) then
                            activate window w
                            focus t
                            activate
                            return id of t
                        end if
                    end repeat
                end repeat
            end tell
            return ""
            """
    }

    /// One `id<TAB>name` line per terminal, so a probed title can be put back.
    /// Inside the tell block `tab` would mean the app's tab class, so the
    /// separators are bound first.
    public static func listTerminals(bundleID: String) -> String {
        """
        set separator to tab
        set newline to linefeed
        tell application id \(quoted(bundleID))
            set out to ""
            repeat with t in terminals
                set out to out & (id of t) & separator & (name of t) & newline
            end repeat
            return out
        end tell
        """
    }

    public static func parseListing(_ text: String) -> [String: String] {
        var names: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let separator = line.firstIndex(of: "\t") else { continue }
            names[String(line[..<separator])] = String(line[line.index(after: separator)...])
        }
        return names
    }

    /// Activates before reordering: `set index` only sticks once Terminal is
    /// frontmost, and activating afterwards restores the old front window.
    public static func appleTerminal(tty: String) -> String {
        """
        tell application id "com.apple.Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is \(quoted(tty)) then
                        activate
                        set selected of t to true
                        set index of w to 1
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """
    }

    public static func iTerm(tty: String) -> String {
        """
        tell application id "com.googlecode.iterm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is \(quoted(tty)) then
                            activate
                            select w
                            select t
                            select s
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
        end tell
        return false
        """
    }

    /// OSC 2: sets the window/tab title of whatever terminal shows the tty.
    public static func titleSequence(_ title: String) -> String {
        "\u{1B}]2;\(title)\u{07}"
    }
}

/// Written by island into the directory the VS Code extension watches
/// (`vscode-extension/extension.js` reads exactly these fields).
public struct VSCodeFocusRequest: Equatable, Sendable {
    public let id: String
    public let time: Date
    public let pids: [Int32]

    public init(id: String, time: Date, pids: [Int32]) {
        self.id = id
        self.time = time
        self.pids = pids
    }

    public func encoded() throws -> Data {
        let object: [String: Any] = [
            "id": id,
            "time": Int((time.timeIntervalSince1970 * 1000).rounded()),
            "pids": pids.map(Int.init),
        ]
        return try JSONSerialization.data(withJSONObject: object)
    }
}

/// The answer from the VS Code window that owned the terminal.
public struct VSCodeFocusResponse: Equatable, Sendable {
    public let workspaceFile: String?
    public let folders: [String]

    public init(workspaceFile: String?, folders: [String]) {
        self.workspaceFile = workspaceFile
        self.folders = folders
    }

    public static func decode(_ data: Data) -> VSCodeFocusResponse? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return VSCodeFocusResponse(
            workspaceFile: object["workspaceFile"] as? String,
            folders: object["folders"] as? [String] ?? [])
    }

    /// What `open -b com.microsoft.VSCode <path>` needs to raise that window.
    public var windowPath: String? { workspaceFile ?? folders.first }
}

/// What one VS Code window last published (`vscode-extension/extension.js`,
/// `window-<pid>.json`): whether it has focus and which terminal is active.
public struct VSCodeWindowState: Equatable, Sendable {
    public static let filePrefix = "window-"

    /// The window's extension host, so a crashed window's file can be ignored.
    public let pid: Int32
    public let isFocused: Bool
    /// The shell of the active terminal, nil when the window has none.
    public let terminalPID: Int32?

    public init(pid: Int32, isFocused: Bool, terminalPID: Int32?) {
        self.pid = pid
        self.isFocused = isFocused
        self.terminalPID = terminalPID
    }

    public static func decode(_ data: Data) -> VSCodeWindowState? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let pid = object["pid"] as? Int
        else { return nil }
        return VSCodeWindowState(
            pid: Int32(pid),
            isFocused: object["focused"] as? Bool ?? false,
            terminalPID: (object["terminalPid"] as? Int).map(Int32.init))
    }

    /// True when a focused window's active terminal runs the process whose
    /// ancestor chain is `chain`.
    public static func shows(_ chain: [Int32], in windows: [VSCodeWindowState]) -> Bool {
        windows.contains { window in
            guard window.isFocused, let terminal = window.terminalPID else { return false }
            return chain.contains(terminal)
        }
    }
}

public enum VSCodeExtension {
    public static let id = "binyanli.island"

    /// Reads `~/.vscode/extensions/extensions.json`. Extension ids are
    /// case-insensitive.
    public static func installedVersion(in extensionsJSON: Data, id: String) -> String? {
        guard
            let entries = try? JSONSerialization.jsonObject(with: extensionsJSON)
                as? [[String: Any]]
        else { return nil }
        for entry in entries {
            let identifier = entry["identifier"] as? [String: Any]
            guard (identifier?["id"] as? String)?.lowercased() == id.lowercased() else { continue }
            return entry["version"] as? String
        }
        return nil
    }
}
