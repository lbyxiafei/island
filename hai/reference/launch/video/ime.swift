import Carbon
// ime            -> prints the current input source id
// ime <id>       -> selects that input source
let a = CommandLine.arguments
if a.count == 1 {
    let s = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
    print(Unmanaged<CFString>.fromOpaque(TISGetInputSourceProperty(s, kTISPropertyInputSourceID)).takeUnretainedValue())
} else {
    let list = TISCreateInputSourceList([kTISPropertyInputSourceID: a[1]] as CFDictionary, false).takeRetainedValue() as! [TISInputSource]
    if let s = list.first { print(TISSelectInputSource(s) == noErr ? "selected" : "failed") } else { print("not found") }
}
