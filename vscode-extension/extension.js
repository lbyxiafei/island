// Installed into VS Code by island. island writes a focus request (the agent's
// pid and its ancestors) into a shared directory; every VS Code window watches
// it, and the window whose terminal shell is one of those processes shows that
// terminal and answers with its workspace so island can raise the right window.
// A file handshake instead of a vscode:// URI, because VS Code asks the user to
// confirm every URI opened from outside.
//
// Each window also publishes whether it has focus and which terminal is active
// (window-<pid>.json), so island can tell that the user is already looking at
// an agent that just finished and skip the notification.
const fs = require("fs");
const os = require("os");
const path = require("path");
const vscode = require("vscode");

const directory = path.join(os.homedir(), "Library", "Application Support", "island", "vscode");
const requestName = "focus-request.json";
const maxRequestAgeMs = 5000;

let lastHandledID;

// One extension host per window, so its pid names this window's state file.
const stateFile = path.join(directory, `window-${process.pid}.json`);

async function publishState() {
  const terminal = vscode.window.activeTerminal;
  const state = {
    pid: process.pid,
    focused: vscode.window.state.focused,
    terminalPid: terminal ? (await terminal.processId) ?? null : null,
  };
  try {
    fs.writeFileSync(stateFile, JSON.stringify(state));
  } catch {
    // island is best effort; a missing file only means "not in view".
  }
}

function readRequest() {
  try {
    const request = JSON.parse(fs.readFileSync(path.join(directory, requestName), "utf8"));
    if (typeof request.id !== "string" || !Array.isArray(request.pids)) return undefined;
    if (Date.now() - request.time > maxRequestAgeMs) return undefined;
    return request;
  } catch {
    return undefined;
  }
}

async function handleRequest() {
  const request = readRequest();
  if (!request || request.id === lastHandledID) return;
  const pids = new Set(request.pids);
  for (const terminal of vscode.window.terminals) {
    if (!pids.has(await terminal.processId)) continue;
    lastHandledID = request.id;
    terminal.show(false);
    const response = {
      workspaceFile: vscode.workspace.workspaceFile?.scheme === "file"
        ? vscode.workspace.workspaceFile.fsPath
        : null,
      folders: (vscode.workspace.workspaceFolders || []).map((folder) => folder.uri.fsPath),
    };
    fs.writeFileSync(path.join(directory, `focus-response-${request.id}.json`), JSON.stringify(response));
    return;
  }
}

function activate(context) {
  fs.mkdirSync(directory, { recursive: true });
  const watcher = fs.watch(directory, (_event, name) => {
    if (name === requestName) handleRequest();
  });
  context.subscriptions.push({ dispose: () => watcher.close() });
  context.subscriptions.push(
    vscode.window.onDidChangeWindowState(publishState),
    vscode.window.onDidChangeActiveTerminal(publishState),
    { dispose: () => fs.rmSync(stateFile, { force: true }) },
  );
  publishState();
}

module.exports = { activate };
