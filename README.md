# Monitor Switcher

One-click input switching for a monitor shared by several computers
(PC 1 on DisplayPort, PC 2 on HDMI 1, MacBook on HDMI 2).

## Install on Windows

Open PowerShell and run:

```powershell
$f="$env:TEMP\ms.ps1"; irm https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-windows.ps1 -OutFile $f; powershell -NoProfile -ExecutionPolicy Bypass -File $f
```

Then press Ctrl+Alt+M (or click the tray icon) to switch.
Ctrl+Alt+1 / 2 / 3 switch straight to PC 1 / PC 2 / MacBook.

## Install on the MacBook

Open Terminal and run:

```bash
curl -fsSL https://raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/setup-monitor-switcher-mac.sh -o /tmp/ms.sh && bash /tmp/ms.sh
```

Then click the display icon in the menu bar.

To change names or ports, edit the list at the top of each script and run it again.
