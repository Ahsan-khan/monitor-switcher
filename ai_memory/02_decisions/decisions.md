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
- **Consequence:** to rename a PC or change a port, edit the script and run it again on both PCs. Only widget preferences and this PC's identity are saved at runtime (D8, D18).

## D4. WPF for the windows, WinForms for the tray
- **Why** *(inferred)*: WPF gives the transparent rounded cards and smooth animations. The tray icon (`NotifyIcon`) and its menu only exist in WinForms. Both ship with .NET Framework.
- The tray menu is restyled dark (`DarkMenuColors`, `DarkRenderer`) to match.

## D5. Several ways to switch: widget, panel, hotkeys, command line
- **Widget** (added 2026-10-21, `dfc905d`; moved into the taskbar on 2026-10-23, D14): click a PC to switch to it.
- **Panel:** Ctrl+Alt+M or a click on the tray icon. Keys 1–9 pick a PC; Esc closes it.
- **Direct hotkeys:** Ctrl+Alt+1…9. `$DirectHotkeys = $false` turns them off for keyboards that type with AltGr + number.
- **Command line:** `MonitorSwitcher.exe /switch <code>`, `/get`, `/whoami` and `/show` ("for other tools").

## D6. (2026-10-21) Two Windows PCs only; the MacBook was dropped
- The first version had three sources (PC 1 on DisplayPort, PC 2 on HDMI 1, MacBook on HDMI 2 = code 18) and a Mac setup script: `m1ddc` from Homebrew, plus a Swift menu-bar app and a LaunchAgent (Apple Silicon, macOS 13+).
- About 40 minutes later the MacBook was removed (`f7aaed6`, `ec1544e`, `875856a`). The reason wasn't recorded.
- **Consequence:** Windows only. The Mac script is still in git: `git show 6da1198:setup-monitor-switcher-mac.sh`.

## D7. (2026-10-21) The PCs are named after their graphics cards
- "PC 1" / "PC 2" became **Nvidia** / **AMD** (`f7aaed6`).

## D8. Widget preferences live in settings.ini
- `%LOCALAPPDATA%\MonitorSwitcher\settings.ini` holds `WidgetMode`, `WidgetOnTop`, `WidgetLeft` and `WidgetTop` (desktop position in WPF units, invariant culture), plus `Self`, `SelfPicked` and `InstallId` since session 3. It's saved from the tray menu and after each drag.
- The setup only ever adds a guessed `Self` line (D18), so preferences survive rebuilds.

## D9. (2026-10-22) Re-read the input every 2 s, and straight away on a display change
- **Why:** the other PC can switch the monitor, and the widget's highlight went stale (commit: "Update the widget faster when the other PC switches").
- History: every 5 s (`dfc905d`) → every 1 s (`297e675`) → every 2 s a minute later (`a5a5315`). The code says "A DDC read takes a few dozen milliseconds, so every couple of seconds is cheap." Why 2 s won over 1 s wasn't recorded.
- It also re-reads when Windows reports a display change (the monitor coming back to this PC), when the desktop widget reappears after a fullscreen app, and when the panel opens. It doesn't poll while no widget is showing.

## D10. One running copy per PC
- A named mutex (`Local\MonitorSwitcher.Instance`) allows one copy. A second launch, such as the desktop shortcut, sets the event `Local\MonitorSwitcher.Show` and exits. The running copy then opens its panel.

## D11. (2026-10-21) Keep the script plain ASCII
- **Why:** Windows PowerShell 5.1 reads a script without a BOM in the ANSI code page, so a UTF-8 "…" turns into "â€¦" inside the app (verified 2026-10-23). The widget commit had slipped in a literal "…" and "’"; `f7aaed6` changed them to `\u2026` and `\u2019`.
- **Rule:** use `\uXXXX` escapes in C# strings and keep comments ASCII. These Markdown files can use any characters.
- AI file-writing tools can turn a typed `\u2026` into the real character, too (it happened on 2026-10-23; see `05_known_issues`).

## D12. Per-user install that starts at sign-in, with no binary files in the repo
- Installs to `%LOCALAPPDATA%\MonitorSwitcher` (no admin rights). Shortcuts: Desktop and Start menu (`/show`), and the Startup folder (no arguments).
- The app icon is drawn by the script (System.Drawing → a 256 px PNG inside an .ico). The tray icon is drawn at runtime, dark or light to match the taskbar.

## D13. GitHub `main` is the release channel
- The README command downloads the script from `raw.githubusercontent.com/Ahsan-khan/monitor-switcher/main/`. Whatever is on `main` is what the next install gets. There are no versions or releases.
- **Rule (2026-10-23):** commit when asked, and ask before pushing.

## D14. (2026-10-23) The widget lives inside the taskbar
- The owner asked: "put the widget in the task bar". The widget is now a child window of the taskbar, just left of the tray (details in `03_architecture/taskbar_and_usage.md`). The tray menu can still put it on the desktop or hide it (`WidgetMode`).
- **Why:** Windows 11 dropped taskbar toolbars (deskbands). A floating always-on-top window over the taskbar would fight the taskbar for the top spot and flicker whenever the taskbar is clicked. A child window moves and hides with the taskbar for free.
- **Consequence:** it needs the manifest (D15). It re-docks itself after Explorer restarts. A crowded taskbar could slide app icons under it.

## D15. (2026-10-23) Compile with a manifest that declares Windows 8–11 support
- **Why:** verified with a prototype: without it, Windows refuses the see-through child window (`CreateWindowEx` fails); with it, the window works in every DPI mode.
- The setup writes the manifest to `%TEMP%` for the build and deletes it afterwards. It keeps `asInvoker` (no admin).

## D16. (2026-10-23) Usage is measured the way Task Manager does it
- The owner asked: "show ram, gpu and cpu usage for both".
- CPU = `% Processor Utility`. GPU = the busiest engine, summing each engine across processes (`GPU Engine` counters). RAM = (total − available) / total. One reading per second on a background thread.
- **Why:** the numbers match what the owner sees in Task Manager, it works for AMD and Nvidia cards without vendor tools, and it costs about 0.03% CPU.
- **Rejected:** vendor libraries (NVML, AMD ADL): separate code per vendor, and DLLs that may be missing.

## D17. (2026-10-23) The PCs share their numbers over the home network (UDP 47815)
- Each PC can only measure itself, so each sends its numbers to the other every second: a broadcast to each local network, plus direct copies to PCs it has heard from. A message carries a random install ID, the sender's input code and three numbers. No names.
- **Why:** no server, account or setup step, and it finds the other PC by itself. The owner prefers simple things they own.
- **Rejected:** a cloud relay (an outside service and account), typing in IP addresses (extra setup), a TCP server (more code, and the same firewall prompt).
- **Consequence:** Windows asks once per PC whether the app may use the network (the owner clicked Allow on the AMD PC). Both PCs must be on the same network. One PC allowing it is enough.

## D18. (2026-10-23) Each PC works out which PC it is from the cable type
- `Identity.Detect()` checks whether the monitor is plugged in by HDMI or DisplayPort. If only one PC in the list uses that kind of port, that's this PC. It runs at startup and on display changes. The tray menu's "This PC is" overrides it (`SelfPicked`).
- **Why:** the first version guessed from what the monitor showed during setup. It saved the wrong PC when the setup ran while the monitor showed the other PC (in session 3, the assistant ran the setup while the owner was on the Nvidia PC).
- **Consequence:** the setup asks the app (`/whoami`). It only guesses from the screen when the cable doesn't tell and nothing is saved yet.

## D19. (2026-10-23) Tile layout
- Two lines per PC: the name, then CPU / GPU / RAM in fixed-width boxes, so the widget never changes width. A small accent bar marks the PC on screen, like the line Windows draws under running apps. Values of 90% or more turn amber. "no usage data" when the other PC hasn't reported in 5 s.
- The owner hasn't commented on the look yet. They like choosing between options for visual things, so offer alternatives if they want a change.
