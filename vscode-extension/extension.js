// Installed into VS Code by island. island writes a focus request (the agent's
// pid and its ancestors) into a shared directory; every VS Code window watches
// it, and the window whose terminal shell is one of those processes shows that
// terminal and answers with its workspace so island can raise the right window.
// A file handshake instead of a vscode:// URI, because VS Code asks the user to
// confirm every URI opened from outside.
const fs = require("fs");
const os = require("os");
const path = require("path");
const vscode = require("vscode");

const directory = path.join(os.homedir(), "Library", "Application Support", "island", "vscode");
const requestName = "focus-request.json";
const maxRequestAgeMs = 5000;

let lastHandledID;

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
}

module.exports = { activate };
