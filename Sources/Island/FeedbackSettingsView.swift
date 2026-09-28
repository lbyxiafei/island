import AppKit
import IslandCore

/// Settings → Feedback: type a message, then send it through the user's own
/// mail client, as a prefilled GitHub issue, or copy it. There is no server;
/// `FeedbackReport` (IslandCore) builds every channel.
@MainActor
final class FeedbackSettingsView: NSView {
    private let environment: FeedbackEnvironment
    private let textView = NSTextView()
    private let status = NSTextField(labelWithString: "")

    init(environment: FeedbackEnvironment) {
        self.environment = environment
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) { nil }

    private func build() {
        let title = NSTextField(labelWithString: "Send feedback")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let help = NSTextField(
            labelWithString:
                "A bug, an idea, anything. Your island and macOS versions are added for you.")
        help.font = .systemFont(ofSize: 11)
        help.textColor = .secondaryLabelColor

        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.autoresizingMask = [.width]
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let mail = NSButton(title: "Send Email", target: self, action: #selector(mailTapped))
        mail.keyEquivalent = "\r"
        mail.keyEquivalentModifierMask = [.command]
        let issue = NSButton(
            title: "Open GitHub Issue", target: self, action: #selector(issueTapped))
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyTapped))
        let buttons = NSStackView(views: [mail, issue, copy])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, help, scroll, buttons, status])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 180),
        ])
    }

    private var report: FeedbackReport? {
        let report = FeedbackReport(message: textView.string, environment: environment)
        if report == nil { show("Write something first.", isError: true) }
        return report
    }

    @objc private func mailTapped() {
        guard let report else { return }
        guard let url = report.mailURL, NSWorkspace.shared.open(url) else {
            copy(report)
            show(
                "No mail app answered; copied instead — paste it into a mail to \(FeedbackReport.address).",
                isError: true)
            return
        }
        show("Opened in your mail app — press Send there. Thank you!", isError: false)
    }

    @objc private func issueTapped() {
        guard let report else { return }
        guard let url = report.issueURL, NSWorkspace.shared.open(url) else {
            copy(report)
            show("Could not open the browser; copied instead.", isError: true)
            return
        }
        show("Opened on GitHub — submit it there. Thank you!", isError: false)
    }

    @objc private func copyTapped() {
        guard let report else { return }
        copy(report)
        show("Copied — paste it into a mail to \(FeedbackReport.address).", isError: false)
    }

    private func copy(_ report: FeedbackReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.clipboardText, forType: .string)
    }

    private func show(_ message: String, isError: Bool) {
        status.stringValue = message
        status.textColor = isError ? .systemRed : .secondaryLabelColor
    }
}
