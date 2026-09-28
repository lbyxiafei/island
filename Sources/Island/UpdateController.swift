import AppKit
import IslandCore

/// Checks the tap's cask for a newer release and installs it: through
/// Homebrew when island came from `brew install --cask`, otherwise by opening
/// the release page. The decisions live in IslandCore (`AppUpdate.swift`).
@MainActor
final class UpdateController {
    static let checkInterval: TimeInterval = 6 * 60 * 60
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/island-upgrade.log")

    let current: AppVersion
    private(set) var status: UpdateStatus
    private let store = UserDefaultsUpdateStore()
    private var timer: Timer?
    private var checkInFlight = false
    /// Called on every status change, on the main thread.
    var onChange: ((UpdateStatus) -> Void)?

    init() {
        let text = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        current = text.flatMap(AppVersion.init) ?? AppVersion(major: 0, minor: 0, patch: 0)
        status = current.isDevelopment ? .development : .unknown
    }

    var autoCheck: Bool {
        get { store.loadAutoCheck() }
        set {
            store.saveAutoCheck(newValue)
            schedule()
        }
    }

    var method: UpgradeMethod {
        UpgradeMethod.detect(fileExists: FileManager.default.fileExists(atPath:))
    }

    /// Whether the last upgrade island started failed, read from its log.
    var lastUpgradeFailed: Bool {
        guard let log = try? String(contentsOf: Self.logURL, encoding: .utf8),
            let status = UpgradeLog.lastExitStatus(in: log)
        else { return false }
        return status != 0
    }

    func start() {
        schedule()
    }

    /// Automatic checks (launch, timer, settings opened) respect the switch;
    /// `Check Now` passes `force`.
    func check(force: Bool = false) {
        guard force || store.loadAutoCheck(), !checkInFlight else { return }
        checkInFlight = true
        if !status.needsAttention { set(.checking) }
        let request = UpdateSource.caskRequest
        let current = current
        Task { [weak self] in
            let latest: AppVersion?
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                let ok = (response as? HTTPURLResponse)?.statusCode == 200
                latest =
                    ok ? UpdateSource.version(fromCask: String(decoding: data, as: UTF8.self)) : nil
            } catch {
                latest = nil
            }
            guard let self else { return }
            self.checkInFlight = false
            let status = UpdateStatus.resolve(current: current, latest: latest)
            self.log("update check: latest \(latest?.description ?? "unknown"), \(status)")
            // A failed re-check keeps an update already found on screen.
            if status == .unknown, self.status.needsAttention { return }
            self.set(status)
        }
    }

    /// One click: brew upgrades in a detached shell after island quits, then
    /// reopens it. Without brew, the release page opens instead.
    func upgrade() {
        guard case .available(let latest) = status else { return }
        switch method {
        case .download:
            log("opening the release page for \(latest)")
            NSWorkspace.shared.open(UpdateSource.releasesURL)
        case .brew(let brew):
            let command = UpgradeMethod.upgradeCommand(
                pid: ProcessInfo.processInfo.processIdentifier, brew: brew,
                logPath: Self.logURL.path)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: command.executable)
            process.arguments = command.arguments
            do {
                try FileManager.default.createDirectory(
                    at: Self.logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try process.run()
            } catch {
                log("could not start the upgrade: \(error.localizedDescription)")
                NSWorkspace.shared.open(UpdateSource.releasesURL)
                return
            }
            log("upgrading to \(latest) with \(brew); island quits and reopens")
            NSApp.terminate(nil)
        }
    }

    private func schedule() {
        timer?.invalidate()
        timer = nil
        guard store.loadAutoCheck(), !current.isDevelopment else { return }
        check()
        timer = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    private func set(_ status: UpdateStatus) {
        guard status != self.status else { return }
        self.status = status
        onChange?(status)
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[island] \(message)\n".utf8))
    }
}
