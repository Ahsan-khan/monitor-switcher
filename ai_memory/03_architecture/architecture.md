# Architecture (as of 2026-10-23, end of session 3)

```
  Nvidia PC ──── DisplayPort (input 15) ────┐
      │                                     ├──► Samsung Odyssey G91F
      │  home network, UDP 47815:           │     (one screen, two inputs)
      │  CPU / GPU / RAM every second       │
      │                                     │
  AMD PC ─────── HDMI 1 (input 17) ─────────┘
```
- Each PC runs its own copy of `MonitorSwitcher.exe`. A switch is one DDC/CI command over that PC's own video cable: "set VCP `0x60` (input select) to N". See `ddc_ci.md`.
- Each PC measures its own CPU, GPU and RAM use every second and sends the numbers to the other PC over the home network. The widget in each taskbar shows both PCs. See `taskbar_and_usage.md`.
- Each PC learns about the other's input switches by reading VCP `0x60` back from the monitor, not over the network.
- Everything is in **one file**, `setup-monitor-switcher-windows.ps1` (about 2,360 lines): the settings, the whole C# app as a here-string, and the PowerShell that builds and installs it.

## Build and install (what the setup script does)
1. If started from PowerShell 7, it relaunches itself in Windows PowerShell 5.1, which the build needs.
2. Checks the settings: the hotkey is one letter, `Monitor` is "Primary" or a number, and there are 1–9 sources.
3. Stops any running `MonitorSwitcher.exe` and waits 400 ms.
4. Fills the placeholders in the C# source from the settings.
5. Writes a temporary **app manifest** that declares Windows 8–11 support (the taskbar widget needs it, D15), then compiles with `CSharpCodeProvider` (`/target:winexe /optimize+ /win32manifest:...`) to `%LOCALAPPDATA%\MonitorSwitcher\MonitorSwitcher.exe`. If there are errors, it prints them and waits for Enter.
6. Draws `MonitorSwitcher.ico` (an indigo → purple tile with a white monitor).
7. Creates the Desktop, Start menu and Startup shortcuts, and deletes old ControlMyMonitor "Switch to ..." desktop shortcuts.
8. Runs `/get` (which input the monitor shows) and `/whoami` (which PC this is, from the cable). Only if the cable doesn't tell and no PC is saved yet does it assume the monitor shows this PC, and write `Self=` to settings.ini.
9. Starts the app with `/show`, prints a summary (including the hint about Windows' network prompt), and waits for Enter.

## Runtime flows
**Start:** `Main` handles `/switch`, `/get` and `/whoami`, then exits. Otherwise it takes the single-instance mutex (or signals the running copy to show its panel, and exits). Then it loads settings.ini and works out which PC this is (`UpdateSelf`). It creates the panel and desktop-widget windows, the tray icon and the hotkeys, and reads the current input in the background. Finally it starts the network link (`Link.Start`) and the once-a-second usage thread (`StartStats`). When WPF starts, `ApplyWidgetMode` docks the widget into the taskbar (or shows it on the desktop), and the timers start.

**Every second, usage thread:** `Stats.Sample()` → `Link.Send()` (broadcasts plus direct copies) → `UsageChanged()` on the UI thread updates the widget that's showing.

**Link thread:** each message from another PC updates `remote[code]` and remembers the sender's address for direct copies.

**Switch from the widget:** click a tile → it shows "Switching…" → `Ddc.SetInput(code)` runs on a worker thread. On success, `App.LastInput = code` and every view refreshes. On failure, the row shakes and a tray balloon says "Couldn't reach the monitor. Is DDC/CI turned on?"

**Switch from the panel or a hotkey:** unchanged since session 1 (Ctrl+Alt+M or the tray icon opens the panel; keys 1–9; Ctrl+Alt+1…9 switch directly).

**Every second, UI timer:** in taskbar mode, `KeepDocked` re-docks after an Explorer restart, follows the tray's left edge, and re-asserts the z-order. In desktop mode, it hides the widget while a fullscreen app covers its screen.

**Every 2 s:** `PollInput` re-reads the input, only while a widget is showing. A display change runs `UpdateSelf`, re-places the widgets, polls, and refreshes the usage. A light/dark theme change re-docks the taskbar widget with the matching text color and redraws the tray icon.

## Code map (`setup-monitor-switcher-windows.ps1`, line numbers as of session 3's commit)
### PowerShell
| Lines | Part | Role |
|---|---|---|
| 1–11 | Header comment | How to run it, and what it builds |
| 13–36 | **Settings** | `$Sources`, `$Monitor`, `$HotkeyLetter`, `$DirectHotkeys`. The only part the owner edits |
| 38–57 | Checks | PowerShell 7 relaunch, setting checks, paths, stop the running copy |
| 60–2169 | `$AppSource` | The C# app (next table) |
| 2172–2184 | Fill-in | `ConvertTo-CSharpString` and the placeholder replacement |
| 2186–2238 | Build | The manifest, the `CSharpCodeProvider` compile, and the error report |
| 2240–2282 | App icon | Draws the 256 px icon and writes it as a PNG-in-ICO file |
| 2284–2307 | Shortcuts | Desktop, Start menu, Startup; removes old ControlMyMonitor shortcuts |
| 2309–2357 | Launch | `/get` and `/whoami`, the `Self` fallback, start with `/show`, summary text |

### C# inside `$AppSource` (namespace `MonitorSwitcher`)
| Lines | Class | Role |
|---|---|---|
| 83–94 | `Source` | Name, Port, Code and Icon of one PC |
| 96–105 | `Config` | The baked-in settings (placeholders) |
| 108–240 | `Ddc` | Finds the monitor; `SetInput` (3 tries, 80 ms apart), `GetInput` (2 tries, 50 ms apart, low byte), one lock around both; `DeviceName` |
| 246–334 | `Identity` | Which PC this is, from the cable type (`QueryDisplayConfig`) |
| 336–396 | `Native` | user32 calls and constants: hotkeys, window styles and positions, monitor info |
| 399–471 | `Settings` | settings.ini: `WidgetMode`, `WidgetOnTop`, `WidgetLeft`, `WidgetTop`, `Self`, `SelfPicked`, `InstallId` |
| 474–480 | `Usage` | One reading: `Cpu`, `Gpu`, `Ram` (percent, -1 = unknown) and when it was taken |
| 483–609 | `Stats` | Reads CPU / GPU / RAM like Task Manager (PDH counters, `GlobalMemoryStatusEx`) |
| 616–735 | `Link` | UDP port 47815: send every second, receive, `For(code)` |
| 738–759 | `Theme` | Accent gradient #6366F1 → #A855F7, glow #8B5CF6, white tints, easing |
| 761–923 | `Tile` | Panel tile (136×124) and `MakeIcon` (desktop / laptop / tv, in any color) |
| 928–1075 | `StatTile` | Widget tile (40 DIP tall): icon, name, CPU / GPU / RAM, accent bar, notes |
| 1078–1157 | `WidgetRow` | A row of StatTiles: click-to-switch, shake, right-click menu |
| 1160–1273 | `WidgetWindow` | The desktop widget: dark card, grip, drag, placement |
| 1281–1380 | `TaskbarDock` | Hosts a WidgetRow inside the taskbar, left of the tray |
| 1382–1401 | `DarkMenuColors` | Dark colors for the tray menu |
| 1404–1416 | `DarkRenderer` | The dark menu renderer, with white submenu arrows |
| 1418–1663 | `SwitcherWindow` | The panel: header with the hotkey hint, tiles, status line, keys, animations |
| 1666–2167 | `App` | `Main` and the command-line verbs, hotkeys, the usage thread, widget modes, timers, polling, the tray menu, theme changes |

### Other files
| File | Role |
|---|---|
| `README.md` | The one-line install command and the basics |
| `Install Monitor Switcher.cmd` | Double-click launcher for the script next to it (for a downloaded copy) |
| `.gitattributes` | CRLF for `.ps1` and `.cmd`. The `*.sh` rule is left over from the Mac script |

## What lives on each PC
- `%LOCALAPPDATA%\MonitorSwitcher\`: `MonitorSwitcher.exe`, `MonitorSwitcher.ico`, `settings.ini`.
- settings.ini keys: `WidgetMode` (taskbar / desktop / off), `WidgetOnTop`, `WidgetLeft`, `WidgetTop`, `Self` (this PC's input code), `SelfPicked` (1 = picked by hand in the menu), `InstallId` (random; tells the PCs' messages apart). Older installs saved `WidgetVisible` instead of `WidgetMode`; it's still read.
- Shortcuts named `Monitor Switcher.lnk`: Desktop (`/show`), Start menu Programs (`/show`), Startup (no arguments).
- Windows Firewall rules, created when the owner clicks Allow (inbound, for the exe's path). On the AMD PC: allowed on Private and Public networks (2026-10-23).
- Nothing in the registry. The app reads `SystemUsesLightTheme` to pick the text and tray icon colors.
