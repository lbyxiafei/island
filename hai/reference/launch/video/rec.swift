import AppKit
import ScreenCaptureKit
import AVFoundation

// rec <out.mov> <x> <y> <w> <h> <seconds> <pid,pid,...> [excludedWindowID,...]
// Records only the given apps' windows (plus a backdrop drawn by this process) inside
// the rect (display points, top-left origin), with the cursor. Nothing else on screen
// ends up in the file.
let a = CommandLine.arguments
let out = URL(fileURLWithPath: a[1])
let rect = CGRect(x: Double(a[2])!, y: Double(a[3])!, width: Double(a[4])!, height: Double(a[5])!)
let seconds = Double(a[6])!
let pids = Set(a[7].split(separator: ",").compactMap { Int32($0) })
let excluded = Set((a.count > 8 ? a[8] : "").split(separator: ",").compactMap { UInt32($0) })

@MainActor final class Recorder: NSObject, SCRecordingOutputDelegate, SCStreamDelegate {
    var stream: SCStream?
    var backdrop: NSWindow?
    func start() async throws {
        let screen = NSScreen.main!
        let h = screen.frame.height
        let win = NSWindow(contentRect: NSRect(x: rect.minX - 40, y: h - rect.maxY - 40, width: rect.width + 80, height: rect.height + 80),
                           styleMask: .borderless, backing: .buffered, defer: false)
        win.level = NSWindow.Level(Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        win.ignoresMouseEvents = true
        win.collectionBehavior = [.canJoinAllSpaces, .stationary]
        let view = NSView(); view.wantsLayer = true
        let g = CAGradientLayer()
        g.colors = [NSColor(red: 0.08, green: 0.10, blue: 0.20, alpha: 1).cgColor,
                    NSColor(red: 0.12, green: 0.16, blue: 0.32, alpha: 1).cgColor,
                    NSColor(red: 0.30, green: 0.20, blue: 0.45, alpha: 1).cgColor]
        g.startPoint = CGPoint(x: 0, y: 0); g.endPoint = CGPoint(x: 1, y: 1)
        view.layer = g
        win.contentView = view
        win.orderFront(nil)
        backdrop = win
        try await Task.sleep(nanoseconds: 400_000_000)

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let display = content.displays.first { $0.displayID == CGMainDisplayID() }!
        let me = ProcessInfo.processInfo.processIdentifier
        let apps = content.applications.filter { pids.contains($0.processID) || $0.processID == me }
        let except = content.windows.filter { excluded.contains($0.windowID) }
        let filter = SCContentFilter(display: display, including: apps, exceptingWindows: except)
        let cfg = SCStreamConfiguration()
        cfg.sourceRect = rect
        let scale = NSScreen.main!.backingScaleFactor; cfg.width = Int(rect.width * scale); cfg.height = Int(rect.height * scale)
        cfg.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        cfg.showsCursor = true
        cfg.queueDepth = 8
        let s = SCStream(filter: filter, configuration: cfg, delegate: self)
        let rc = SCRecordingOutputConfiguration()
        rc.outputURL = out; rc.outputFileType = .mov; rc.videoCodecType = .hevc
        try s.addRecordingOutput(SCRecordingOutput(configuration: rc, delegate: self))
        try await s.startCapture()
        stream = s
        print("recording"); fflush(stdout)
        try await Task.sleep(nanoseconds: UInt64(seconds * 1e9))
        try await s.stopCapture()
        try await Task.sleep(nanoseconds: 800_000_000)
        print("done"); fflush(stdout)
    }
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) { print("stream error: \(error)") }
    nonisolated func recordingOutput(_ o: SCRecordingOutput, didFailWithError error: Error) { print("record error: \(error)") }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let recorder = Recorder()
    do { try await recorder.start() } catch { print("error: \(error)") }
    exit(0)
}
app.run()
