import Foundation

/// One way an agent gets run that island tells apart — a terminal CLI, an
/// editor extension, a desktop app, a headless job. Every task a source reports
/// is tagged with exactly one scenario, and each scenario can be switched off
/// on its own in Settings → Agents.
///
/// The texts double as the support matrix shown in that tab, so they describe
/// what island actually does, not what it hopes to do.
public struct AgentScenario: Equatable, Hashable, Sendable, Identifiable {
    /// `<agent raw value>.<scenario>`; persisted, so never rename one.
    public let id: String
    public let agent: AgentKind
    public let title: String
    /// Which runs fall into this scenario and how island sees them finish.
    public let detection: String
    /// What clicking such a run does.
    public let jumpBack: String

    public static func named(_ id: String) -> AgentScenario? {
        AgentProfile.all.lazy.flatMap(\.scenarios).first { $0.id == id }
    }
}

extension AgentScenario {
    public static let claudeCodeTerminal = AgentScenario(
        id: "claude-code.terminal", agent: .claudeCode, title: "Terminal CLI",
        detection: "claude in tmux, cmux, Ghostty, Terminal, iTerm2 or VS Code's terminal",
        jumpBack: "Focuses the exact tab or tmux pane; else copies claude --resume")
    public static let claudeCodeEditor = AgentScenario(
        id: "claude-code.editor", agent: .claudeCode, title: "Editor extension",
        detection: "Claude Code panels inside VS Code or JetBrains IDEs",
        jumpBack: "Brings the editor window forward")
    public static let claudeCodeDesktop = AgentScenario(
        id: "claude-code.desktop", agent: .claudeCode, title: "Code in the Claude app",
        detection: "Claude Code sessions started from the Claude desktop app",
        jumpBack: "Brings the Claude app forward")
    public static let claudeCodeHeadless = AgentScenario(
        id: "claude-code.headless", agent: .claudeCode, title: "SDK & other entry points",
        detection: "Agent SDK and any entry point island does not know yet",
        jumpBack: "Brings its host app forward; else copies claude --resume")

    public static let claudeDesktopChat = AgentScenario(
        id: "claude-desktop.chat", agent: .claudeDesktop, title: "Chats",
        detection: "Replies in conversations the Claude app has open (its local cache)",
        jumpBack: "Opens the conversation (claude:// link)")

    public static let piTerminal = AgentScenario(
        id: "pi.terminal", agent: .pi, title: "Terminal CLI",
        detection: "pi in any terminal, matched to its process by working directory",
        jumpBack: "Focuses the exact tab or tmux pane; else copies pi --session")

    public static let codexApp = AgentScenario(
        id: "codex.app", agent: .codex, title: "Desktop app & IDE",
        detection: "Threads from the Codex (ChatGPT) app and the VS Code extension",
        jumpBack: "Opens the thread (codex:// link)")
    public static let codexCLI = AgentScenario(
        id: "codex.cli", agent: .codex, title: "Terminal CLI",
        detection: "The codex TUI in a terminal",
        jumpBack: "Opens the thread in the Codex app (codex:// link)")
    public static let codexExec = AgentScenario(
        id: "codex.exec", agent: .codex, title: "Headless exec",
        detection: "codex exec runs from scripts or CI",
        jumpBack: "Opens the thread in the Codex app (codex:// link)")
}

/// Everything that differs from one agent to the next, in one declarative
/// place. The rest of island (overlay, menu, reopen, settings) reads these
/// fields instead of switching on `AgentKind`; detection lives behind
/// `AgentActivitySource`. Adding an agent = a case, a profile, a source.
public struct AgentProfile: Sendable {
    public let agent: AgentKind
    public let displayName: String
    /// Executable names to look for in `ps` when a task has no recorded host.
    public let processNames: [String]
    /// Apps whose icon stands for the agent, first installed one wins.
    public let appBundleIDs: [String]
    /// SF Symbol used when none of those apps is installed.
    public let symbolName: String
    /// Never empty; the first one is where untagged tasks land.
    public let scenarios: [AgentScenario]

    public var primaryScenario: AgentScenario { scenarios[0] }

    /// Settings order.
    public static var all: [AgentProfile] { AgentKind.allCases.map(\.profile) }
}

extension AgentKind {
    public var profile: AgentProfile {
        switch self {
        case .claudeCode:
            return AgentProfile(
                agent: self, displayName: "Claude Code", processNames: ["claude"],
                appBundleIDs: ["com.anthropic.claudefordesktop"], symbolName: "sparkle",
                scenarios: [
                    .claudeCodeTerminal, .claudeCodeEditor, .claudeCodeDesktop,
                    .claudeCodeHeadless,
                ])
        case .claudeDesktop:
            return AgentProfile(
                agent: self, displayName: "Claude", processNames: ["Claude"],
                appBundleIDs: ["com.anthropic.claudefordesktop"], symbolName: "bubble.left",
                scenarios: [.claudeDesktopChat])
        case .pi:
            return AgentProfile(
                agent: self, displayName: "pi", processNames: ["pi"], appBundleIDs: [],
                symbolName: "terminal", scenarios: [.piTerminal])
        case .codex:
            return AgentProfile(
                agent: self, displayName: "Codex", processNames: ["codex"],
                appBundleIDs: ["com.openai.codex"],
                symbolName: "chevron.left.forwardslash.chevron.right",
                scenarios: [.codexApp, .codexCLI, .codexExec])
        }
    }

    public var displayName: String { profile.displayName }

    public var processNames: [String] { profile.processNames }
}

/// Which scenarios the user wants island to watch. Only the switched-off ones
/// are recorded, so everything — including scenarios added later — starts on.
public struct AgentScenarioSettings: Equatable, Sendable {
    public private(set) var disabled: Set<String>

    public init(disabled: Set<String> = []) {
        self.disabled = disabled
    }

    /// The checkbox state of an agent's row.
    public enum State: Equatable, Sendable {
        case on, off, mixed
    }

    public func isEnabled(_ scenarioID: String) -> Bool {
        !disabled.contains(scenarioID)
    }

    public mutating func setEnabled(_ scenarioID: String, _ enabled: Bool) {
        if enabled {
            disabled.remove(scenarioID)
        } else {
            disabled.insert(scenarioID)
        }
    }

    public mutating func setAgent(_ agent: AgentKind, enabled: Bool) {
        for scenario in agent.profile.scenarios { setEnabled(scenario.id, enabled) }
    }

    public func state(of agent: AgentKind) -> State {
        let on = agent.profile.scenarios.filter { isEnabled($0.id) }.count
        if on == agent.profile.scenarios.count { return .on }
        return on == 0 ? .off : .mixed
    }

    /// Agents with at least one scenario on — the ones worth scanning.
    public var enabledAgents: Set<AgentKind> {
        Set(AgentKind.allCases.filter { state(of: $0) != .off })
    }

    public func allows(_ task: AgentTask) -> Bool {
        isEnabled(task.scenario)
    }
}

/// Remembers the switched-off scenario ids in `UserDefaults`.
public struct UserDefaultsAgentScenarioStore {
    public static let key = "IslandDisabledScenarios"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> AgentScenarioSettings {
        AgentScenarioSettings(disabled: Set(defaults.stringArray(forKey: Self.key) ?? []))
    }

    public func save(_ settings: AgentScenarioSettings) {
        defaults.set(settings.disabled.sorted(), forKey: Self.key)
    }
}
