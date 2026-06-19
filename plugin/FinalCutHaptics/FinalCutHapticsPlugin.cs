namespace Loupedeck.FinalCutHapticsPlugin
{
    using System;
    using System.Diagnostics;
    using System.IO;
    using System.Linq;
    using System.Net;
    using System.Net.Sockets;
    using System.Reflection;
    using System.Text;
    using System.Threading;
    using System.Threading.Tasks;

    /// <summary>
    /// FinalCutHaptics — delivers a haptic tick on the MX Master 4 each time Final Cut Pro's
    /// playhead/skimmer snaps to a clip edge while snapping (magnet) is on.
    ///
    /// Everything ships inside this plugin: the bundled "SnapObserver" binary (next to this DLL)
    /// watches FCP via the Accessibility API and sends a UDP datagram ("snap") to 127.0.0.1:9000
    /// per detected stop. This plugin launches & supervises that binary, listens for the datagrams,
    /// and raises the "snap" plugin event — mapped to the sharp_collision waveform on the MX Master 4
    /// (package/events/extra/eventMapping.yaml). The user only installs the plugin; the one
    /// unavoidable manual step is granting Accessibility permission when macOS prompts.
    /// </summary>
    public class FinalCutHapticsPlugin : Plugin
    {
        // Must match the names in DefaultEventSource.yaml / eventMapping.yaml.
        private const String SnapEvent = "snap";
        private const Int32 UdpPort = 9000;
        // Minimum gap between haptics. The observer already emits exactly one event per edge
        // crossing (and stays silent while parked), so debouncing here only swallows legitimate
        // rapid re-crossings during back-and-forth scrubbing. Keep it off (0); raise only if a
        // pathological burst ever appears.
        private const Int64 DebounceMs = 0;

        public override Boolean UsesApplicationApiOnly => true;
        public override Boolean HasNoApplication => true;

        // On/off switch, surfaced as a toggle command in the Options+ plugin view and persisted
        // across restarts. When off, snaps are detected but no haptic is raised.
        private const String EnabledSetting = "hapticsEnabled";
        public Boolean Enabled { get; private set; } = true;

        public void SetEnabled(Boolean on)
        {
            this.Enabled = on;
            try { this.SetPluginSetting(EnabledSetting, on ? "1" : "0", false); } catch { }
            PluginLog.Info($"haptics {(on ? "ENABLED" : "DISABLED")}");
        }

        private CancellationTokenSource _cts;
        private UdpClient _udp;
        private Task _listenTask;
        private Int64 _lastFireTicks;
        private Process _observer;
        private volatile Boolean _stopping;

        public FinalCutHapticsPlugin()
        {
            PluginLog.Init(this.Log);
        }

        public override void Load()
        {
            try
            {
                this.PluginEvents.AddEvent(
                    SnapEvent,
                    "Timeline Snap",
                    "Fired when the Final Cut Pro playhead snaps to a clip edge (magnet on)");

                if (this.TryGetPluginSetting(EnabledSetting, out var saved)) { this.Enabled = saved != "0"; }

                this._cts = new CancellationTokenSource();
                this._udp = new UdpClient(new IPEndPoint(IPAddress.Loopback, UdpPort));
                this._listenTask = Task.Run(() => this.ReceiveLoop(this._cts.Token));

                this._stopping = false;
                this.StartObserver();

                PluginLog.Info($"FinalCutHaptics loaded; listening on udp://127.0.0.1:{UdpPort}");
            }
            catch (Exception ex)
            {
                PluginLog.Error(ex, "Failed to load FinalCutHaptics plugin");
            }
        }

        public override void Unload()
        {
            this._stopping = true;
            try
            {
                if (this._observer != null && !this._observer.HasExited) { this._observer.Kill(); }
            }
            catch { }
            try
            {
                this._cts?.Cancel();
                this._udp?.Close();
                this._listenTask?.Wait(TimeSpan.FromSeconds(2));
            }
            catch (Exception ex)
            {
                PluginLog.Error(ex, "Error unloading FinalCutHaptics plugin");
            }
            finally
            {
                this._udp?.Dispose();
                this._cts?.Dispose();
                this._observer?.Dispose();
                this._udp = null;
                this._cts = null;
                this._observer = null;
                this._listenTask = null;
            }
        }

        // Launch the bundled SnapObserver binary (sibling of this DLL) and supervise it.
        private void StartObserver()
        {
            try
            {
                var path = this.ResolveObserverPath();
                if (path == null)
                {
                    PluginLog.Warning("SnapObserver binary not found in plugin folder");
                    return;
                }

                // Ensure it's executable (the zip/extract may drop the bit) and kill any strays so
                // we never run two observers (which would double-fire ticks).
                try { File.SetUnixFileMode(path, (UnixFileMode)0b111_101_101); } catch { } // rwxr-xr-x
                this.RunQuietly("/usr/bin/pkill", "-f SnapObserver");

                var psi = new ProcessStartInfo
                {
                    FileName = path,
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                this._observer = new Process { StartInfo = psi, EnableRaisingEvents = true };
                this._observer.OutputDataReceived += (_, e) => { if (e.Data != null) PluginLog.Verbose($"[obs] {e.Data}"); };
                this._observer.ErrorDataReceived += (_, e) => { if (e.Data != null) PluginLog.Verbose($"[obs] {e.Data}"); };
                this._observer.Exited += (_, _) =>
                {
                    if (this._stopping) { return; }
                    PluginLog.Warning("SnapObserver exited; restarting in 2s");
                    Thread.Sleep(2000);
                    if (!this._stopping) { this.StartObserver(); }
                };
                this._observer.Start();
                this._observer.BeginOutputReadLine();
                this._observer.BeginErrorReadLine();
                PluginLog.Info($"SnapObserver started (pid {this._observer.Id})");
            }
            catch (Exception ex)
            {
                PluginLog.Error(ex, "Failed to start SnapObserver");
            }
        }

        // Find the bundled SnapObserver. The Logi host can load the assembly with an empty
        // Location, so try the SDK's path properties (via reflection, to avoid hard API coupling)
        // before falling back to the assembly location.
        private String ResolveObserverPath()
        {
            var candidates = new System.Collections.Generic.List<String>();
            void AddFromProp(String prop, params String[] tail)
            {
                try
                {
                    var pi = this.GetType().GetProperty(prop,
                        BindingFlags.Public | BindingFlags.NonPublic | BindingFlags.Instance | BindingFlags.FlattenHierarchy);
                    if (pi?.GetValue(this) is String v && !String.IsNullOrEmpty(v))
                    {
                        var baseDir = tail.Length > 0 && Path.HasExtension(v) ? Path.GetDirectoryName(v) : v;
                        candidates.Add(Path.Combine(new[] { baseDir }.Concat(tail).ToArray()));
                    }
                }
                catch { }
            }
            // package root → bin/SnapObserver
            AddFromProp("PluginPackageDirectoryPath", "bin", "SnapObserver");
            // plugin DLL path → sibling SnapObserver
            AddFromProp("AssemblyFilePath", "SnapObserver");
            try
            {
                var loc = this.GetType().Assembly.Location;
                if (!String.IsNullOrEmpty(loc)) { candidates.Add(Path.Combine(Path.GetDirectoryName(loc), "SnapObserver")); }
            }
            catch { }

            foreach (var c in candidates)
            {
                PluginLog.Verbose($"observer candidate: {c}");
                if (File.Exists(c)) { return c; }
            }
            return null;
        }

        private void RunQuietly(String file, String args)
        {
            try
            {
                var p = Process.Start(new ProcessStartInfo { FileName = file, Arguments = args, UseShellExecute = false, CreateNoWindow = true });
                p?.WaitForExit(2000);
            }
            catch { }
        }

        private async Task ReceiveLoop(CancellationToken token)
        {
            while (!token.IsCancellationRequested)
            {
                try
                {
                    var result = await this._udp.ReceiveAsync();
                    var msg = Encoding.UTF8.GetString(result.Buffer).Trim();
                    if (msg == "snap")
                    {
                        this.Fire();
                    }
                }
                catch (ObjectDisposedException) { break; }
                catch (SocketException) when (token.IsCancellationRequested) { break; }
                catch (Exception ex)
                {
                    if (!token.IsCancellationRequested)
                    {
                        PluginLog.Warning($"recv error: {ex.Message}");
                    }
                }
            }
        }

        private void Fire()
        {
            if (!this.Enabled) { return; }
            if (DebounceMs > 0)
            {
                var now = DateTime.UtcNow.Ticks;
                var elapsedMs = (now - this._lastFireTicks) / TimeSpan.TicksPerMillisecond;
                if (elapsedMs < DebounceMs)
                {
                    return;
                }

                this._lastFireTicks = now;
            }
            this.PluginEvents.RaiseEvent(SnapEvent);
            PluginLog.Verbose("snap → haptic");
        }
    }
}
