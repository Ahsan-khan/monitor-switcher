# Decisions log

Each entry: decision → why → consequences. Add new entries at the bottom.
Reasons marked *(inferred)* were worked out from the code and commits on 2026-10-23, because the chats that built the app aren't on this PC.

## D1. Talk to the monitor directly over DDC/CI, with no third-party tool
- The app calls Windows' own monitor API (`dxva2.dll`: `SetVCPFeature` and `GetVCPFeatureAndVCPFeatureReply` on VCP code `0x60`, input select). Details are in `03_architecture/ddc_ci.md`.
- **Why** *(inferred)*: the owner's earlier setup used NirSoft ControlMyMonitor through "Switch to ..." desktop shortcuts. Calling the API directly means there's nothing else to download or keep updated.
- **Consequence:** the setup deletes those old ControlMyMonitor shortcuts, because their Ctrl+Alt+1/2/3 hotkeys would clash with the app's. DDC/CI must be turned on in the monitor's own menu.

## D2. One PowerShell script builds the app on each PC
- `setup-monitor-switcher-windows.ps1` holds the whole C# app as a string. It compiles it with the C# compiler that ships with .NET Framework (`Microsoft.CSharp.CSharpCodeProvider`), makes the icon and shortcuts, and starts the app.
- **Why** *(inferred)*: Windows PowerShell 5.1 and .NET Framework are already on every Windows PC, so there's nothing to install first and no binary in the repo. Running the same script again installs, updates or reconfigures.
- **Avoids:** shipping an unsigned .exe from GitHub (SmartScreen warnings, a release step), and needing the .NET SDK on both PCs.
- **Consequence:** the app must be **C# 5** and the script must stay **plain ASCII** (D11). A build error shows on the owner's screen, with the lines to send back.

## D3. Settings are baked in at build time
- The list at the top of the script (`$Sources` with Name, Port, Code and Icon, plus `$Monitor`, `$HotkeyLetter` and `$DirectHotkeys`) replaces the `/*SOURCES*/`, `/*MONITOR*/`, `/*HOTKEY*/` and `/*DIRECT*/` placeholders before compiling.
- **Why** *(inferred)*: one place to edit, and the script says "Use the same list on every computer."
- **Consequence:** to rename a PC or change a port, edit the script and run it again on both PCs. Only widget preferences are saved at runtime (D8).

## D4. WPF for the windows, WinForms for the tray
- **Why** *(inferred)*: WPF gives the transparent rounded cards and smooth animations. The tray icon (`NotifyIcon`) and its menu only exist in WinForms. Both ship with .NET Framework.
- The tray menu is restyled dark (`DarkMenuColors`) to match.

## D5. Several ways to switch: widget, panel, hotkeys, command line
- **Desktop widget** (added 2026-10-21, `dfc905d`): always visible. It never takes focus (`WS_EX_NOACTIVATE`), stays out of Alt+Tab (`WS_EX_TOOLWINDOW`), and hides while a fullscreen app covers its screen.
- **Panel:** Ctrl+Alt+M or a click on the tray icon. Keys 1–9 pick a PC; Esc closes it.
- **Direct hotkeys:** Ctrl+Alt+1…9. `$DirectHotkeys = $false` turns them off for keyboards that type with AltGr + number.
- **Command line:** `MonitorSwitcher.exe /switch <code>`, `/get` and `/show` ("for other tools").

## D6. (2026-10-21) Two Windows PCs only; the MacBook was dropped
- The first version had three sources (PC 1 on DisplayPort, PC 2 on HDMI 1, MacBook on HDMI 2 = code 18) and a Mac setup script: `m1ddc` from Homebrew, plus a Swift menu-bar app and a LaunchAgent (Apple Silicon, macOS 13+).
- About 40 minutes later the MacBook was removed (`f7aaed6`, `ec1544e`, `875856a`). The reason wasn't recorded.
- **Consequence:** Windows only. The Mac script is still in git: `git show 6da1198:setup-monitor-switcher-mac.sh`.

## D7. (2026-10-21) The PCs are named after their graphics cards
- "PC 1" / "PC 2" became **Nvidia** / **AMD** (`f7aaed6`).

## D8. Widget preferences live in settings.ini
- `%LOCALAPPDATA%\MonitorSwitcher\settings.ini` holds `WidgetVisible`, `WidgetOnTop`, `WidgetLeft` and `WidgetTop` (position in WPF units, invariant culture). It's saved from the tray menu and after each drag.
- The setup never touches it, so preferences survive rebuilds.

## D9. (2026-10-22) Re-read the input every 2 s, and straight away on a display change
- **Why:** the other PC can switch the monitor, and the widget's highlight went stale (commit: "Update the widget faster when the other PC switches").
- History: every 5 s (`dfc905d`) → every 1 s (`297e675`) → every 2 s a minute later (`a5a5315`). The code says "A DDC read takes a few dozen milliseconds, so every couple of seconds is cheap." Why 2 s won over 1 s wasn't recorded.
- It also re-reads when Windows reports a display change (the monitor coming back to this PC), when the widget reappears after a fullscreen app, and when the panel opens. It doesn't poll while the widget is hidden.

## D10. One running copy per PC
- A named mutex (`Local\MonitorSwitcher.Instance`) allows one copy. A second launch, such as the desktop shortcut, sets the event `Local\MonitorSwitcher.Show` and exits. The running copy then opens its panel.

## D11. (2026-10-21) Keep the script plain ASCII
- **Why:** Windows PowerShell 5.1 reads a script without a BOM in the ANSI code page, so a UTF-8 "…" turns into "â€¦" inside the app (verified 2026-10-23). The widget commit had slipped in a literal "…" and "’"; `f7aaed6` changed them to `…` and `’`.
- **Rule:** use `\uXXXX` escapes in C# strings and keep comments ASCII. These Markdown files can use any characters.

## D12. Per-user install that starts at sign-in, with no binary files in the repo
- Installs to `%LOCALAPPDATA%\MonitorSwitcher` (no admin rights). Shortcuts: Desktop and Start menu (`/show`), and the Startup folder (no arguments).
- The app icon is drawn by the script (System.Drawing → a 256 px PNG inside an .ico). The tray icon is drawn at runtime, dark or light to match the taskbar.

## D13. GitHub `main` is the release channel
- The README command downloads the script from `raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/`. Whatever is on `main` is what the next install gets. There are no versions or releases.
- **Rule (2026-10-23):** commit when asked, and ask before pushing.
