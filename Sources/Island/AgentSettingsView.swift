import AppKit
import IslandCore

/// Settings → Agents: every agent island supports, each scenario it tells
/// apart, how island detects it and what a click does — so the tab reads as
/// the support matrix — with a switch per scenario and one per agent.
///
/// All state lives in `AgentScenarioSettings` (IslandCore); this view only
/// mirrors it into checkboxes and reports changes.
@MainActor
final class AgentSettingsView: NSView {
    private var settings: AgentScenarioSettings
    private let onChange: (AgentScenarioSettings) -> Void
    private var agentToggles: [AgentKind: NSButton] = [:]
    private var scenarioToggles: [String: NSButton] = [:]

    init(settings: AgentScenarioSettings, onChange: @escaping (AgentScenarioSettings) -> Void) {
        self.settings = settings
        self.onChange = onChange
        super.init(frame: .zero)
        build()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Layout

    private func build() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let intro = Self.label(
            "island only watches what is switched on. Runs switched off are neither counted\nnor listed (island --scan-agents still shows them, marked off).",
            size: 11, color: .secondaryLabelColor)
        stack.addArrangedSubview(intro)
        stack.setCustomSpacing(14, after: intro)

        for profile in AgentProfile.all {
            let agentToggle = NSButton(
                checkboxWithTitle: profile.displayName, target: self,
                action: #selector(agentToggled(_:)))
            agentToggle.font = .systemFont(ofSize: 13, weight: .semibold)
            agentToggle.allowsMixedState = true
            agentToggle.identifier = NSUserInterfaceItemIdentifier(profile.agent.rawValue)
            agentToggles[profile.agent] = agentToggle
            stack.addArrangedSubview(agentToggle)

            for scenario in profile.scenarios {
                let row = scenarioRow(scenario)
                stack.addArrangedSubview(row)
                stack.setCustomSpacing(6, after: row)
            }
            if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(14, after: last) }
        }

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])
    }

    /// Checkbox with the scenario's title, then what it covers and what a
    /// click does, indented under its agent.
    private func scenarioRow(_ scenario: AgentScenario) -> NSView {
        let toggle = NSButton(
            checkboxWithTitle: scenario.title, target: self,
            action: #selector(scenarioToggled(_:)))
        toggle.identifier = NSUserInterfaceItemIdentifier(scenario.id)
        scenarioToggles[scenario.id] = toggle

        let details = NSStackView(views: [
            Self.label(scenario.detection, size: 11, color: .secondaryLabelColor),
            Self.label("Click: \(scenario.jumpBack)", size: 11, color: .tertiaryLabelColor),
        ])
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 1
        details.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)

        let row = NSStackView(views: [toggle, details])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 1
        row.edgeInsets = NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 0)
        return row
    }

    private static func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = color
        return label
    }

    // MARK: - State

    private func refresh() {
        for (agent, toggle) in agentToggles {
            switch settings.state(of: agent) {
            case .on: toggle.state = .on
            case .off: toggle.state = .off
            case .mixed: toggle.state = .mixed
            }
        }
        for (id, toggle) in scenarioToggles {
            toggle.state = settings.isEnabled(id) ? .on : .off
        }
    }

    /// A fully-on agent switches off; an off or mixed one switches fully on.
    @objc private func agentToggled(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let agent = AgentKind(rawValue: raw) else {
            return
        }
        settings.setAgent(agent, enabled: settings.state(of: agent) != .on)
        refresh()
        onChange(settings)
    }

    @objc private func scenarioToggled(_ sender: NSButton) {
        guard let id = sender.identifier?.rawValue else { return }
        settings.setEnabled(id, sender.state == .on)
        refresh()
        onChange(settings)
    }
}

/// Top-left origin, so a short document sits at the top of its scroll view.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
