import CoreGraphics
import Foundation
// mouse move <x> <y> <seconds> | mouse click <x> <y>   (global display points, top-left origin)
let a = CommandLine.arguments
let x = Double(a[2])!, y = Double(a[3])!
let src = CGEventSource(stateID: .hidSystemState)
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
if a[1] == "move" {
    let from = CGEvent(source: nil)!.location
    let dur = Double(a[4])!, steps = max(1, Int(dur * 120))
    for i in 1...steps {
        var k = Double(i) / Double(steps); k = k < 0.5 ? 4 * k * k * k : 1 - pow(-2 * k + 2, 3) / 2
        post(.mouseMoved, CGPoint(x: from.x + (x - from.x) * k, y: from.y + (y - from.y) * k))
        usleep(UInt32(dur * 1e6) / UInt32(steps))
    }
} else {
    let p = CGPoint(x: x, y: y)
    post(.leftMouseDown, p); usleep(90_000); post(.leftMouseUp, p)
}
