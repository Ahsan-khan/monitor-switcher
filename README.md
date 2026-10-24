# Monitor Switcher

One-click input switching for a monitor shared by two Windows PCs
(Nvidia on DisplayPort, AMD on HDMI 1).

## Install or update

On each PC, open PowerShell and run:

```powershell
$f="$env:TEMP\ms.ps1"; irm https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-windows.ps1 -OutFile $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

- A widget in the taskbar, left of the clock, shows each PC's CPU, GPU and RAM use.
  Click a PC to switch to it. Right-click it for options, like moving it onto the desktop.
- The PC you're on shows its name in its own color in the taskbar (Nvidia green, AMD maroon).
  After you switch to a PC, a small "You're on AMD" card with the AMD or NVIDIA logo
  slides in at the top right for a few seconds (turn it off from the widget's right-click menu).
- Ctrl+Alt+1 / 2 switch straight to Nvidia / AMD.
- Ctrl+Alt+M (or the tray icon) opens the big switcher panel.

The PCs share their usage over your home network, so install it on both. The first
time it runs, Windows asks whether Monitor Switcher may use the network: click Allow.

To change names, ports or colors, edit the list at the top of the script and run it again.
