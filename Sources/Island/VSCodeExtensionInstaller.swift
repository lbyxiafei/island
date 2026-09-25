import AppKit
import IslandCore

/// Installs (or upgrades) the island VS Code extension bundled in Island.app,
/// so jumping to a VS Code terminal tab works without any setup. Runs once per
/// launch, off the main thread, and does nothing when VS Code is not installed
/// or the bundled version is already there.
enum VSCodeExtensionInstaller {
    static func installIfNeeded() {
        guard
            let vsix = Bundle.main.url(forResource: "island-vscode", withExtension: "vsix"),
            let version = Bundle.main.object(forInfoDictionaryKey: "IslandVSCodeExtensionVersion")
                as? String,
            let vscode = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: TerminalTabFocus.vscodeBundleID)
        else { return }
        let cli = vscode.appendingPathComponent("Contents/Resources/app/bin/code").path
        let registry = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".vscode/extensions/extensions.json")

        DispatchQueue.global(qos: .utility).async {
            let installed = (try? Data(contentsOf: registry)).flatMap {
                VSCodeExtension.installedVersion(in: $0, id: VSCodeExtension.id)
            }
            guard installed != version else { return }
            _ = Subprocess.run([cli, "--install-extension", vsix.path, "--force"])
            let now = (try? Data(contentsOf: registry)).flatMap {
                VSCodeExtension.installedVersion(in: $0, id: VSCodeExtension.id)
            }
            let result = now == version ? "installed" : "failed to install"
            FileHandle.standardError.write(
                Data("[island] \(result) VS Code extension \(VSCodeExtension.id)@\(version)\n".utf8)
            )
        }
    }
}
