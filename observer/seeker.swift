// seeker.swift — minimal live skimmer/playhead timecode printer. Does NOTHING else (no edge walk,
// no UDP) so it can't flood Final Cut. Run it, then zoom + skim and watch whether the value freezes.
//
//   swift observer/seeker.swift
//
// If it prints "Waiting for Accessibility permission", grant your terminal app in
// System Settings ▸ Privacy & Security ▸ Accessibility, then re-run.

import Cocoa
import ApplicationServices
import Darwin
setvbuf(stdout, nil, _IONBF, 0)

func attr(_ el: AXUIElement, _ n: String) -> AnyObject? { var v: AnyObject?; return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil }
func sv(_ el: AXUIElement, _ n: String) -> String? { attr(el, n) as? String }
func kids(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] }
func role(_ el: AXUIElement) -> String { sv(el, kAXRoleAttribute as String) ?? "" }
func desc(_ el: AXUIElement) -> String { sv(el, kAXDescriptionAttribute as String) ?? "" }
func now() -> Double { ProcessInfo.processInfo.systemUptime }

if !AXIsProcessTrusted() {
    print("⏳ Waiting for Accessibility permission — grant your terminal app in")
    print("   System Settings ▸ Privacy & Security ▸ Accessibility, then re-run.")
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    _ = AXIsProcessTrustedWithOptions(opts)
    while !AXIsProcessTrusted() { Thread.sleep(forTimeInterval: 1.0) }
}
guard let fcp = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.FinalCut" }) else {
    print("❌ Final Cut Pro is not running."); exit(1)
}
let app = AXUIElementCreateApplication(fcp.processIdentifier)
func find(_ r: AXUIElement, _ d: Int, _ m: (AXUIElement) -> Bool) -> AXUIElement? {
    if d > 26 { return nil }; if m(r) { return r }
    for c in kids(r) { if let f = find(c, d + 1, m) { return f } }; return nil
}
func findLCD() -> AXUIElement? { find(app, 0) { role($0) == "AXStaticText" && desc($0) == "Timecode LCD" } }

var lcd = findLCD()
while lcd == nil { print("…looking for the timecode readout (open a project)…"); Thread.sleep(forTimeInterval: 1.0); lcd = findLCD() }

print("▶︎ Reading live skimmer timecode. Zoom + skim. Watch the value — does it ever freeze?\n")
var last = ""
var lastChange = now()
var n = 0
while true {
    n += 1
    let t = now()
    let v = lcd.flatMap { sv($0, kAXValueAttribute as String) } ?? "nil"
    let readMs = (now() - t) * 1000
    if v != last { last = v; lastChange = now() }
    let frozenMs = (now() - lastChange) * 1000
    let flag = frozenMs > 700 ? "  ⚠️ FROZEN \(Int(frozenMs))ms" : (readMs > 30 ? "  (slow read \(Int(readMs))ms)" : "")
    // overwrite a single line so it's easy to watch
    print(String(format: "\r%6d  %@%@          ", n, v, flag), terminator: "")
    Thread.sleep(forTimeInterval: 0.05)   // 20 Hz
}
