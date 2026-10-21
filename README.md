# Monitor Switcher

One-click input switching for a monitor shared by several computers
(PC 1 on DisplayPort, PC 2 on HDMI 1, MacBook on HDMI 2).

## Install or update on Windows

Open PowerShell and run:

```powershell
$f="$env:TEMP\ms.ps1"; irm https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-windows.ps1 -OutFile $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

- A small widget sits on your desktop: click a computer to switch to it.
  Drag it anywhere; right-click it for options. It hides while a game or video is fullscreen.
- Ctrl+Alt+1 / 2 / 3 switch straight to PC 1 / PC 2 / MacBook.
- Ctrl+Alt+M (or the tray icon) opens the big switcher panel.

## Install on the MacBook

Open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-mac.sh -o /tmp/ms.sh && bash /tmp/ms.sh
```

Then click the display icon in the menu bar.

To change names or ports, edit the list at the top of each script and run it again.
