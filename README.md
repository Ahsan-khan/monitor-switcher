# Monitor Switcher

One-click input switching for a monitor shared by two Windows PCs
(Nvidia on DisplayPort, AMD on HDMI 1).

## Install or update

On each PC, open PowerShell and run:

```powershell
$f="$env:TEMP\ms.ps1"; irm https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-windows.ps1 -OutFile $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

- A small widget sits on your desktop: click a PC to switch to it.
  Drag it anywhere; right-click it for options. It hides while a game or video is fullscreen.
- Ctrl+Alt+1 / 2 switch straight to Nvidia / AMD.
- Ctrl+Alt+M (or the tray icon) opens the big switcher panel.

To change names or ports, edit the list at the top of the script and run it again.
