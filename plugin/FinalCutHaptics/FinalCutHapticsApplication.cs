namespace Loupedeck.FinalCutHapticsPlugin
{
    using System;

    // Associates the plugin with Final Cut Pro. Although this is a universal/haptics plugin
    // (HasNoApplication = true), the working SDK samples all ship a ClientApplication subclass,
    // so we provide one for parity and to scope the plugin to FCP.
    public class FinalCutHapticsApplication : ClientApplication
    {
        public FinalCutHapticsApplication()
        {
        }

        protected override String GetProcessName() => "Final Cut Pro";

        protected override String GetBundleName() => "com.apple.FinalCut";
    }
}
