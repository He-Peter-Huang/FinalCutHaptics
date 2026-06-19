namespace Loupedeck.FinalCutHapticsPlugin
{
    using System;

    // On/off switch shown in the Logi Options+ plugin view. Toggles snap haptics; the label
    // reflects the current state and persists across restarts (see FinalCutHapticsPlugin.Enabled).
    public class SnapHapticsToggleCommand : PluginDynamicCommand
    {
        public SnapHapticsToggleCommand()
            : base(displayName: "Snap Haptics On/Off",
                   description: "Enable or disable Final Cut Pro snap haptics on the MX Master 4",
                   groupName: "Final Cut Haptics")
        {
        }

        protected override void RunCommand(String actionParameter)
        {
            if (this.Plugin is FinalCutHapticsPlugin p)
            {
                p.SetEnabled(!p.Enabled);
                this.ActionImageChanged();
            }
        }

        protected override String GetCommandDisplayName(String actionParameter, PluginImageSize imageSize)
        {
            var on = (this.Plugin as FinalCutHapticsPlugin)?.Enabled ?? true;
            return on ? "Snap Haptics\nON" : "Snap Haptics\nOFF";
        }
    }
}
