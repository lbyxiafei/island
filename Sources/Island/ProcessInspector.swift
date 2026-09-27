import Foundation
import IslandCore

/// The live `ProcessInspecting`: `kill(pid, 0)` for liveness, `ps` + `lsof`
/// for working directories (the same lookup `AgentReopenExecutor` uses to
/// find a pi process).
struct ProcessInspector: ProcessInspecting {
    func isRunning(_ pid: Int32) -> Bool {
        // EPERM: the pid exists but belongs to someone else.
        kill(pid, 0) == 0 || errno == EPERM
    }

    func workingDirectories(ofProcessesNamed names: Set<String>) -> Set<String>? {
        guard let processList = Subprocess.run(["/bin/ps", "-axo", "pid=,comm="]) else {
            return nil
        }
        let pids = AgentProcess.pids(fromProcessList: processList, names: names)
        guard !pids.isEmpty else { return [] }
        let pidList = pids.map(String.init).joined(separator: ",")
        guard
            let output = Subprocess.run([
                "/usr/sbin/lsof", "-a", "-p", pidList, "-d", "cwd", "-Fpn",
            ])
        else { return nil }
        return Set(AgentProcess.parseLsof(output).compactMap(\.cwd))
    }
}
