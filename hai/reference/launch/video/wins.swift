import CoreGraphics
import Foundation
// Prints "<windowID> <layer> <x> <y> <w> <h>" for on-screen windows owned by the given pid.
let pid = Int32(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int32) == pid {
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    print(w[kCGWindowNumber as String]!, w[kCGWindowLayer as String]!, Int(b["X"]!), Int(b["Y"]!), Int(b["Width"]!), Int(b["Height"]!))
}
