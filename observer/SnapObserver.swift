// SnapObserver.swift — watches Final Cut Pro and emits a "snap" event each time the
// playhead lands on a clip edge while snapping/magnet is ON.
//
// Pipeline: FCP (Accessibility) -> this observer -> UDP 127.0.0.1:9000 -> C# Logi plugin -> haptic.
//
// Run:
//   swift observer/SnapObserver.swift            # send UDP "snap" to 127.0.0.1:9000
//   swift observer/SnapObserver.swift --console   # print only, no UDP (validation)
//   swift observer/SnapObserver.swift --port 9001 # custom UDP port
//
// Requires: FCP running with a timeline; the controlling process granted Accessibility.
// AX tree locations are documented in memory/fcp-ax-map.md.

import Cocoa
import ApplicationServices
import Darwin

setvbuf(stdout, nil, _IONBF, 0) // unbuffered so output streams to logs/pipes immediately

// ---------- AX helpers ----------
func attr(_ el: AXUIElement, _ n: String) -> AnyObject? {
    var v: AnyObject?; return AXUIElementCopyAttributeValue(el, n as CFString, &v) == .success ? v : nil
}
func str(_ el: AXUIElement, _ n: String) -> String? { attr(el, n) as? String }
func kids(_ el: AXUIElement) -> [AXUIElement] { (attr(el, kAXChildrenAttribute as String) as? [AXUIElement]) ?? [] }
func role(_ el: AXUIElement) -> String { str(el, kAXRoleAttribute as String) ?? "" }
func desc(_ el: AXUIElement) -> String { str(el, kAXDescriptionAttribute as String) ?? "" }

// ---------- CLI ----------
let argv = CommandLine.arguments
let consoleOnly = argv.contains("--console")
let debug = argv.contains("--debug")
var port: UInt16 = 9000
if let i = argv.firstIndex(of: "--port"), i + 1 < argv.count, let p = UInt16(argv[i + 1]) { port = p }

// ---------- UDP sender ----------
final class UDP {
    let fd: Int32
    var addr = sockaddr_in()
    init(port: UInt16) {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr)
    }
    func send(_ msg: String) {
        var a = addr
        let bytes = Array(msg.utf8)
        _ = withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                sendto(fd, bytes, bytes.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }
}

// ---------- locate FCP ----------
// Find the LIVE Final Cut Pro process. We must NOT use NSWorkspace.shared.runningApplications:
// that array is a cache refreshed by the MAIN run loop, and this tool blocks the main thread in a
// tight polling loop that never spins the run loop — so the cache freezes at launch. After the user
// quits & relaunches FCP we'd keep handing back the ORIGINAL (now-dead) pid and never re-latch.
// NSRunningApplication.runningApplications(withBundleIdentifier:) does a fresh Launch Services
// query on every call, so it reflects the current process regardless of the run loop.
func findFCPApp() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.FinalCut").first { !$0.isTerminated }
}
func findFCP() -> AXUIElement? {
    guard let a = findFCPApp() else { return nil }
    return AXUIElementCreateApplication(a.processIdentifier)
}
// Kernel-truth liveness for the pid we've latched — independent of any AX-element or Launch Services
// caching. Returns false once that exact process exits, which is how we notice an FCP restart.
func pidAlive(_ pid: pid_t) -> Bool {
    if pid <= 0 { return false }
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM   // exists but owned by another user (not expected for FCP)
}

// ---------- wait for FCP + REAL Accessibility access ----------
// AXIsProcessTrusted() is unreliable for a helper spawned by the Logi service: it can report
// "trusted" via the parent process while our reads are actually blocked (so the observer runs but
// reads nothing, and the user never sees a prompt). Instead, verify access by actually READING
// FCP's window tree. When FCP is running but unreadable, Accessibility hasn't been granted to the
// process responsible for this helper — open the settings pane and tell the user what to enable,
// then keep retrying until access works (no restart needed).
func canReadFCP(_ app: AXUIElement) -> Bool { !kids(app).isEmpty }

func openAccessibilitySettings() {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = ["x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]
    try? p.run()
}

var app: AXUIElement
var fcpPID: pid_t = -1
var openedSettings = false
var loggedWaitFCP = false
var lastNudge = -1.0e9
while true {
    guard let candidate = findFCPApp() else {
        if !loggedWaitFCP { print("⏳ Waiting for Final Cut Pro to launch…"); loggedWaitFCP = true }
        Thread.sleep(forTimeInterval: 1.0); continue
    }
    let axApp = AXUIElementCreateApplication(candidate.processIdentifier)
    if canReadFCP(axApp) { app = axApp; fcpPID = candidate.processIdentifier; break }   // FCP running AND readable → proceed
    // FCP is running but unreadable → Accessibility not granted to this helper's responsible process.
    let now = ProcessInfo.processInfo.systemUptime
    if now - lastNudge > 10 {
        print("⚠️ Accessibility permission needed. Enable Final Cut Haptics in")
        print("   System Settings ▸ Privacy & Security ▸ Accessibility")
        print("   (look for \"LogiPluginService\", \"Logi Options+\", or \"SnapObserver\" and turn it on).")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)            // registers the entry / may surface a prompt
        if !openedSettings { openAccessibilitySettings(); openedSettings = true }  // open the pane once
        lastNudge = now
    }
    Thread.sleep(forTimeInterval: 1.0)
}
print("✅ Final Cut Pro is readable — snap detection active.")

// ---------- element finders ----------
func find(_ root: AXUIElement, depth: Int = 0, _ match: (AXUIElement) -> Bool) -> AXUIElement? {
    if depth > 26 { return nil }
    if match(root) { return root }
    for c in kids(root) { if let f = find(c, depth: depth + 1, match) { return f } }
    return nil
}
func findPositionReadout() -> AXUIElement? {
    // The "Timecode LCD" dashboard readout tracks the SKIMMER (mouse hover) when skimming
    // and the playhead otherwise — and it snaps exactly onto clip edges. The "Playhead"
    // AXValueIndicator only moves when the playhead itself is repositioned, so it misses
    // skim-snaps. See memory/fcp-ax-map.md.
    find(app) { role($0) == "AXStaticText" && desc($0) == "Timecode LCD" }
}
func findSnapCheckbox() -> AXUIElement? {
    // The snapping checkbox is identified by its AXHelp text, not a fragile index.
    find(app) { role($0) == "AXCheckBox" && (str($0, "AXHelp") ?? "").lowercased().contains("snapping") }
}
func collectEdges(_ root: AXUIElement) -> Set<String> {
    var set = Set<String>()
    func walk(_ el: AXUIElement, _ d: Int) {
        if d > 26 { return }
        if role(el) == "AXHandle" {
            let de = desc(el)
            if de == "Leading Edge" || de == "Trailing Edge", let v = str(el, kAXValueAttribute as String) {
                set.insert(v)
            }
        }
        for c in kids(el) { walk(c, d + 1) }
    }
    walk(root, 0)
    return set
}
// Collect edges ONLY from the timeline subtree. Walking the whole app tree is far slower
// (~3.4 s / 2500+ nodes when the media browser is loaded) and finds the same edges as the
// timeline area alone (~200 ms / ~500 nodes). Scope it so refresh cost is browser-independent.
func collectTimelineEdges(_ appRoot: AXUIElement) -> Set<String> {
    guard let tl = find(appRoot, { role($0) == "AXLayoutArea" && desc($0) == "Project Timeline" }) else { return [] }
    return collectEdges(tl)
}

// Map "HH:MM:SS:FF" (or drop-frame "…;FF") to a monotonic integer so we can test whether the
// playhead swept PAST an edge between two samples (FF<100, SS<60, MM<60 → base-100 is order-safe).
func tcToKey(_ s: String) -> Int? {
    let p = s.split(whereSeparator: { $0 == ":" || $0 == ";" })
    guard p.count == 4, let h = Int(p[0]), let m = Int(p[1]), let sec = Int(p[2]), let f = Int(p[3]) else { return nil }
    return ((h * 100 + m) * 100 + sec) * 100 + f
}
func edgeKeysOf(_ e: Set<String>) -> [Int] { e.compactMap(tcToKey).sorted() }

// Snap points (clip edges) are refreshed by a BACKGROUND thread. The walk is an expensive
// full-tree AX scan (280 ms idle, up to ~2 s while scrubbing); running it on the polling loop
// blinded detection for that whole time (the periodic dropouts). AX calls are independent IPC,
// so the hot loop's single playhead read never blocks behind the walk. The hot loop reads an
// atomic snapshot of edgeKeys under a lock.
let edgeLock = NSLock()
var accumEdges = Set(edgeKeysOf(findFCP().map(collectTimelineEdges) ?? []))
var sharedEdgeKeys = accumEdges.sorted()
Thread.detachNewThread {
    // The edge walk floods FCP's main thread, which freezes FCP's own skimmer timecode for the whole
    // walk — the ~10 s blackout on big projects. So NEVER walk while the user is moving the mouse
    // (skimming). We gate on real mouse movement (CoreGraphics, independent of AX, can't freeze).
    // Edge timecodes are absolute and don't change with zoom, so we ACCUMULATE them: a walk during a
    // pause adds any newly-visible clips, and the set never shrinks. Periodic reset drops stale edits.
    var lastMouse = CGPoint(x: -1, y: -1)
    var lastMove = 0.0
    var round = 0
    var threadPID = fcpPID
    while true {
        let nowU = ProcessInfo.processInfo.systemUptime
        let m = CGEvent(source: nil)?.location ?? .zero
        if abs(m.x - lastMouse.x) > 1 || abs(m.y - lastMouse.y) > 1 { lastMouse = m; lastMove = nowU }
        if nowU - lastMove < 0.35 {                     // mouse moving → skimming → stand down
            Thread.sleep(forTimeInterval: 0.1)
            continue
        }
        if let liveApp = findFCPApp() {
            // FCP was restarted → the previous project's edge timecodes are meaningless; drop them.
            if liveApp.processIdentifier != threadPID {
                threadPID = liveApp.processIdentifier
                edgeLock.lock(); accumEdges.removeAll(); sharedEdgeKeys = []; edgeLock.unlock()
            }
            let a = AXUIElementCreateApplication(liveApp.processIdentifier)
            let fresh = Set(edgeKeysOf(collectTimelineEdges(a)))
            if !fresh.isEmpty {
                round += 1
                edgeLock.lock()
                if round % 60 == 0 { accumEdges = fresh } else { accumEdges.formUnion(fresh) }
                sharedEdgeKeys = accumEdges.sorted()
                edgeLock.unlock()
            }
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
}

// ---------- main loop ----------
let udp = consoleOnly ? nil : UDP(port: port)
var posEl = findPositionReadout()
var snapBox = findSnapCheckbox()

print("▶︎ SnapObserver running — \(consoleOnly ? "console mode (no UDP)" : "UDP 127.0.0.1:\(port)")")
print("   timecodeLCD=\(posEl != nil ? "ok" : "MISSING")  snappingToggle=\(snapBox != nil ? "ok" : "MISSING")  snapPoints=\(sharedEdgeKeys.count)")
print("   Turn snapping ON (N) and skim/scrub across clip edges…\n")

var prevKey: Int? = nil
var tick = 0
var snapOn = false
var lastSnapPrint = -1

// Real-time rate limit (DROP, don't queue): fire a tick only if at least `minGapSec` has passed
// since the last one, else skip it entirely. No backlog can build, so there is zero lag — it just
// caps the sustained rate below what the Logi haptic engine throttles on (which caused the
// "ticks then 1-2s cooldown"). Normal/back-and-forth scrubbing stays well under this gap.
let minGapSec = 0.040   // ~25 ticks/s
var lastSend = 0.0
var loopStamp = 0.0
var lastLiveCheck = 0.0

while true {
    tick += 1

    // Detect an FCP restart (or exit) ~2 Hz using kernel-truth liveness, independent of any AX or
    // Launch Services caching. When the pid we latched dies, re-acquire the NEW process and reset
    // everything bound to the old one. Without this the observer stays bound to the first pid it
    // saw and goes permanently silent the moment FCP is relaunched.
    let nowLive = ProcessInfo.processInfo.systemUptime
    if nowLive - lastLiveCheck > 0.5 {
        lastLiveCheck = nowLive
        if !pidAlive(fcpPID), let live = findFCPApp() {
            app = AXUIElementCreateApplication(live.processIdentifier)
            fcpPID = live.processIdentifier
            posEl = nil; snapBox = nil; prevKey = nil   // drop element refs bound to the dead pid
            print("🔄 Final Cut Pro restarted (pid \(fcpPID)) — re-acquired.")
        }
    }

    // Refresh snapping state ~20 Hz; re-find control if it went stale.
    if tick % 12 == 0 || snapBox == nil {
        if snapBox == nil { snapBox = findSnapCheckbox() }
        if let b = snapBox, let v = attr(b, kAXValueAttribute as String) as? Int {
            snapOn = (v == 1)
        } else if let b = snapBox, let n = attr(b, kAXValueAttribute as String) as? NSNumber {
            snapOn = n.intValue == 1
        }
        if snapBox != nil && (attr(snapBox!, kAXValueAttribute as String) == nil) { snapBox = nil } // stale
        if snapOn != (lastSnapPrint == 1) {
            print(snapOn ? "🧲 snapping ON" : "⚪︎ snapping OFF")
            lastSnapPrint = snapOn ? 1 : 0
        }
    }

    // Detect loop stalls (a long pause = blind to crossings during that time).
    if debug {
        let nowUp = ProcessInfo.processInfo.systemUptime
        if loopStamp > 0, nowUp - loopStamp > 0.08 {
            print("STALL \(String(format: "%.0f", (nowUp - loopStamp) * 1000)) ms")
        }
        loopStamp = nowUp
    }

    // Read the position readout (cheap, cached element ≈0.03 ms). Re-find only if the read fails
    // (a forced periodic re-find would itself be a stalling tree walk).
    if posEl == nil { posEl = findPositionReadout() }
    let tc = posEl.flatMap { str($0, kAXValueAttribute as String) }
    if tc == nil { posEl = nil }

    // Atomic snapshot of the latest snap points (refreshed off-thread).
    edgeLock.lock(); let edgeKeys = sharedEdgeKeys; edgeLock.unlock()

    let curKey = tc.flatMap(tcToKey)
    if snapOn, let cur = curKey, let prev = prevKey, cur != prev {
        // Count clip edges swept between the previous and current sample. Catches fast skims
        // where FCP jumps the readout past several edges between two reads (an exact-landing
        // test would miss those). Destination edge counts; origin edge does not (no re-fire
        // while parked on an edge, since cur == prev is skipped above).
        let lo = min(prev, cur), hi = max(prev, cur)
        var crossed = 0
        for k in edgeKeys {
            if k > hi { break }                 // edgeKeys sorted ascending
            if (k > lo && k < hi) || k == cur { crossed += 1 }
        }
        if debug { print("dbg \(prev)→\(cur) span=\(hi - lo) crossed=\(crossed) \(crossed > 0 ? "SNAP" : "")") }
        if crossed > 0 {
            // Fire in real time, but drop (never queue) ticks closer than minGapSec so we don't
            // flood the haptic engine into its cooldown. No backlog → no lag.
            let nowUp = ProcessInfo.processInfo.systemUptime
            if nowUp - lastSend >= minGapSec {
                if consoleOnly { print("• snap → \(tc ?? "")") }
                udp?.send("snap")
                lastSend = nowUp
            }
        }
    }
    if curKey != nil { prevKey = curKey }

    // If FCP quit, try to recover.
    if posEl == nil && snapBox == nil {
        if let live = findFCPApp() {
            app = AXUIElementCreateApplication(live.processIdentifier)
            fcpPID = live.processIdentifier
        } else { print("… waiting for Final Cut Pro …") }
        prevKey = nil
        usleep(500_000)
        posEl = findPositionReadout(); snapBox = findSnapCheckbox()
        continue
    }

    usleep(4_000) // ~250 Hz
}
