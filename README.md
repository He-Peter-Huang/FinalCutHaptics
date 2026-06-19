# FinalCutHaptics

**Feel every snap.** A haptic tick on the Logitech **MX Master 4** each time Final Cut Pro's
playhead/skimmer snaps to a clip edge while snapping (the magnet) is on — so the magnetic timeline
actually feels magnetic.

🌐 **Website / download:** https://he-peter-huang.github.io/FinalCutHaptics/

---

## How it works

Final Cut Pro has **no public API** for the timeline or playhead, so the snap is detected by
*observing* FCP through the macOS **Accessibility API** (the same approach
[CommandPost](https://commandpost.fcp.cafe/) uses). The design mirrors the
[ReaperHaptic](https://github.com/b451c/ReaperHaptic) bridge.

```
┌─────────────────┐  Accessibility  ┌──────────────────┐   UDP :9000   ┌─────────────────────┐
│  Final Cut Pro  │ ──────────────▶ │  Swift observer  │ ────────────▶ │  C# Logi Options+   │
│  (timeline)     │  position +     │  (SnapObserver)  │   "snap"      │  plugin → RaiseEvent │
│                 │  clip edges     │                  │               │  → sharp_collision   │
└─────────────────┘                 └──────────────────┘               └─────────────────────┘
```

- **`observer/SnapObserver.swift`** — a small Swift agent that:
  - reads the dashboard **timecode** readout (which tracks the skimmer/playhead) at ~250 Hz,
  - gates on the **snapping** toggle,
  - fires when the position **crosses** a clip edge,
  - and sends a UDP datagram to `127.0.0.1:9000`.

  The clip-edge list is gathered by a background scan of the timeline, which **stands down while the
  mouse is moving** — a full scan floods FCP's main thread and would freeze its own skimmer, so it
  only runs in the pauses. The live position read is lightweight and stays responsive.

- **`plugin/`** — a **C# / .NET** Logi Options+ plugin that launches & supervises the observer,
  listens on the UDP port, and calls `PluginEvents.RaiseEvent("snap")`, mapped to the
  `sharp_collision` waveform on the MX Master 4. It also exposes a **Snap Haptics On/Off** toggle.

- **`web/`** — the product website (Vue + Vite), deployed to GitHub Pages by CI.

> The cut list could also come natively from FCPXML (no Accessibility), but the **real-time
> playhead position has no FCP API** — that part necessarily uses a light Accessibility read.

## Requirements

- macOS 14+, a **Logitech MX Master 4** (the only Logi mouse with haptics) and **Logi Options+**.
- **Final Cut Pro**.
- To build: the **Swift toolchain** (Xcode / Command Line Tools), **.NET SDK 8+**. The plugin links
  against `PluginApi.dll` from an installed Logi Options+ (`LogiPluginService.app`).

## Build

```bash
scripts/build.sh
```

This compiles the universal Swift observer, builds the C# plugin (which bundles the observer), and
produces `dist/FinalCutHaptics-0.1.pkg` (unsigned by default).

To sign & notarize (Apple Developer ID required), set:

```bash
FCH_SIGN_APP="Developer ID Application: NAME (TEAMID)" \
FCH_SIGN_INSTALLER="Developer ID Installer: NAME (TEAMID)" \
FCH_NOTARY_PROFILE="your-notarytool-profile" \
scripts/build.sh
```

### Manual steps

```bash
# 1. Universal observer binary
swiftc -O -target arm64-apple-macosx11.0  observer/SnapObserver.swift -o /tmp/arm
swiftc -O -target x86_64-apple-macosx11.0 observer/SnapObserver.swift -o /tmp/x64
lipo -create /tmp/arm /tmp/x64 -output plugin/FinalCutHaptics/SnapObserver

# 2. Plugin (bundles the observer next to the DLL)
dotnet build plugin/FinalCutHaptics/FinalCutHaptics.csproj -c Release

# 3. Installer .pkg — see scripts/build.sh
```

## Install

Download the signed installer from the
[**latest release**](https://github.com/He-Peter-Huang/FinalCutHaptics/releases/latest) (or the
[website](https://he-peter-huang.github.io/FinalCutHaptics/)) and open it.

### Grant Accessibility (one time)

The observer runs inside **Logi Options+** (`LogiPluginService`), so macOS attributes its
Accessibility permission to that host process — not to a separate "FinalCutHaptics" app. With Final
Cut Pro open, the observer opens **System Settings ▸ Privacy & Security ▸ Accessibility** for you
when it can't read FCP; turn on the entry for **LogiPluginService** (it may also appear as **Logi
Options+** or **SnapObserver**). If you don't see it, click **+** and add
`/Applications/Utilities/LogiPluginService.app`.

> macOS often *doesn't* pop a new permission prompt here, because Logi Options+ may already have a
> (disabled) Accessibility entry — so you have to enable it manually the first time.

Then open a project, press **N** to turn snapping on, and scrub.

## Development

```bash
scripts/run-observer.sh --console        # run the observer standalone, printing detections
scripts/reload-plugin.sh                 # rebuild + hot-reload the plugin in Logi Options+
swift observer/seeker.swift              # minimal live timecode reader (debug)
```

The website:

```bash
cd web && npm install && npm run dev     # local preview
```

## Notes

- Haptics fire only on the **MX Master 4**.
- The plugin bundles the Logi SDK runtime DLLs so it loads reliably (ties it to Logi Plugin
  Service ≥ 6.2.1, the haptics version).
- AX layout of FCP's playhead / snapping toggle / clip edges is documented in comments in
  `observer/SnapObserver.swift`.

## License

[MIT](LICENSE)
