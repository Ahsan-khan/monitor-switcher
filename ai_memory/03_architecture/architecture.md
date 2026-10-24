# Architecture (as of 2026-10-23, end of session 4)

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
- Everything is in **one file**, `setup-monitor-switcher-windows.ps1` (about 3,400 lines): the settings, the whole C# app as a here-string, and the PowerShell that builds and installs it.

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

**The monitor goes to another PC / comes back** (D22): `InputChanged` watches the input change. When it goes to another PC, `PrepareName` makes the card and loads the logo. When it comes back from another PC's code to `Settings.Self` (never on the first reading at startup), `FlashName` shows the small `NameBanner` card in the top-right corner at once. It stays at least 3 s and until 1.5 s after the first mouse or keyboard input (`GetLastInputInfo`), 5 s at most, then fades.

**This PC changes** (cable detection on a display change, or "This PC is" in the menu): `SelfChanged` redraws the tray icon and tooltip and refreshes the rows, which move the tint and name tag (`StatTile.SetSelf`). Picking it in the menu also flashes the card.

**Switch from the panel or a hotkey:** unchanged since session 1 (Ctrl+Alt+M or the tray icon opens the panel; keys 1–9; Ctrl+Alt+1…9 switch directly).

**Every second, UI timer:** in taskbar mode, `KeepDocked` re-docks after an Explorer restart, follows the tray's left edge, and re-asserts the z-order. In desktop mode, it hides the widget while a fullscreen app covers its screen.

**Every 2 s** (a 250 ms timer that polls every 8th tick): `PollInput` re-reads the input while a widget is showing, or while the "You're on" card is turned on (`NameOnSwitch`). While the monitor shows another PC and the card is on, it polls on every tick (4 times a second), so a switch back is noticed within about 0.3 s. A display change runs `UpdateSelf` (and `SelfChanged` if this PC turned out to be another one), re-places the widgets, polls, and refreshes the usage. A light/dark theme change re-docks the taskbar widget with the matching text color and redraws the tray icon.

## Code map (`setup-monitor-switcher-windows.ps1`, line numbers as of session 4)
### PowerShell
| Lines | Part | Role |
|---|---|---|
| 1–11 | Header comment | How to run it, and what it builds |
| 13–38 | **Settings** | `$Sources` (Name, Port, Code, Icon, Color), `$Monitor`, `$HotkeyLetter`, `$DirectHotkeys`. The only part the owner edits |
| 40–59 | Checks | PowerShell 7 relaunch, setting checks, paths, stop the running copy |
| 62–3197 | `$AppSource` | The C# app (next table) |
| 3200–3212 | Fill-in | `ConvertTo-CSharpString` and the placeholder replacement (5 arguments per source; a missing Color becomes `""`) |
| 3214–3266 | Build | The manifest, the `CSharpCodeProvider` compile, and the error report |
| 3268–3310 | App icon | Draws the 256 px icon and writes it as a PNG-in-ICO file |
| 3312–3335 | Shortcuts | Desktop, Start menu, Startup; removes old ControlMyMonitor shortcuts |
| 3337–3385 | Launch | `/get` and `/whoami`, the `Self` fallback, start with `/show`, summary text |

### C# inside `$AppSource` (namespace `MonitorSwitcher`)
| Lines | Class | Role |
|---|---|---|
| 86–111 | `Source` | Name, Port, Code, Icon and Color of one PC. The 4-argument constructor (no color) still works |
| 113–145 | `Config` | The baked-in settings (placeholders); spare colors for PCs without one; `Config.Self` = this PC's `Source` or null |
| 148–280 | `Ddc` | Finds the monitor; `SetInput` (3 tries, 80 ms apart), `GetInput` (2 tries, 50 ms apart, low byte), one lock around both; `DeviceName` |
| 286–374 | `Identity` | Which PC this is, from the cable type (`QueryDisplayConfig`) |
| 376–450 | `Native` | user32 calls and constants: hotkeys, window styles and positions, monitor info, `LastInputTick` (`GetLastInputInfo`) |
| 453–531 | `Settings` | settings.ini: `WidgetMode`, `WidgetOnTop`, `WidgetLeft`, `WidgetTop`, `Self`, `SelfPicked`, `WidgetStyle`, `NameOnSwitch`, `InstallId` |
| 534–540 | `Usage` | One reading: `Cpu`, `Gpu`, `Ram` (percent, -1 = unknown) and when it was taken |
| 543–669 | `Stats` | Reads CPU / GPU / RAM like Task Manager (PDH counters, `GlobalMemoryStatusEx`) |
| 676–795 | `Link` | UDP port 47815: send every second, receive, `For(code)` |
| 798–839 | `Theme` | Accent gradient #6366F1 → #A855F7, glow #8B5CF6, white tints, easing, `InkOn` (black or white text on a color), `Shade` |
| 841–1023 | `Tile` | Panel tile (136×124) with the "This PC" chip, and `MakeIcon` (desktop / laptop / tv, in any color) |
| 1028–1067 | `NameTag` | A PC's icon and name in a widget tile; a solid tag in the PC's color on this PC's tile |
| 1072–1130 | `TileBody` | The numbers part of a widget tile, per style; its `Tag`; metric colors, helpers, `Create(style)` |
| 1133–1197 | `ClassicBody` | Classic: icon, name, "CPU 23%  GPU 5%  RAM 61%" |
| 1200–1281 | `BarsBody` | Bars: icon, name, a colored meter per metric |
| 1284–1384 | `RingsBody` | Rings: name, a ring gauge per metric with the number inside |
| 1388–1516 | `GraphsBody` | Graphs: icon, name, a 40-second graph per metric with its number above |
| 1522–1633 | `StatTile` | Widget tile (40 DIP tall): background, hover, click, the tint on this PC's tile, the on-screen bar on another PC's tile; hosts a TileBody |
| 1636–1716 | `WidgetRow` | A row of StatTiles in one style: click-to-switch, shake, right-click menu |
| 1719–1841 | `WidgetWindow` | The desktop widget: dark card, grip, drag, placement, `UseStyle` |
| 1849–1948 | `TaskbarDock` | Hosts a WidgetRow inside the taskbar, left of the tray |
| 1950–1969 | `DarkMenuColors` | Dark colors for the tray menu |
| 1972–1984 | `DarkRenderer` | The dark menu renderer, with white submenu arrows |
| 1986–2233 | `SwitcherWindow` | The panel: header with the hotkey hint, tiles, status line, keys, animations |
| 2239–2353 | `NameBanner` | The small "You're on AMD" card: `Fill` (color, logo, name), `Flash` (top right, slide in, stay 3 to 5 s depending on input, fade, hide). Click-through |
| 2359–2537 | `Logo` | The graphics card maker's logo from its own app's icon (`PrivateExtractIcons`), the white-mark cut-out, `logo.png` override |
| 2540–3195 | `App` | `Main` and the command-line verbs, hotkeys, the usage thread, widget modes and styles, timers, polling, the card (`PrepareName`, `FlashName`), `SelfChanged`, the tray menu and icon, theme changes, `TrimSoon` |

### Other files
| File | Role |
|---|---|
| `README.md` | The one-line install command and the basics |
| `Install Monitor Switcher.cmd` | Double-click launcher for the script next to it (for a downloaded copy) |
| `.gitattributes` | CRLF for `.ps1` and `.cmd`. The `*.sh` rule is left over from the Mac script |

## What lives on each PC
- `%LOCALAPPDATA%\MonitorSwitcher\`: `MonitorSwitcher.exe`, `MonitorSwitcher.ico`, `settings.ini`.
- settings.ini keys: `WidgetMode` (taskbar / desktop / off), `WidgetOnTop`, `WidgetLeft`, `WidgetTop`, `Self` (this PC's input code), `SelfPicked` (1 = picked by hand in the menu), `WidgetStyle` (classic / bars / rings / graphs), `NameOnSwitch` (1 = show the "You're on" card, the default; only written once the app saves settings), `InstallId` (random; tells the PCs' messages apart). Older installs saved `WidgetVisible` instead of `WidgetMode`; it's still read.
- Shortcuts named `Monitor Switcher.lnk`: Desktop (`/show`), Start menu Programs (`/show`), Startup (no arguments).
- Windows Firewall rules, created when the owner clicks Allow (inbound, for the exe's path). On the AMD PC: allowed on Private and Public networks (2026-10-23).
- Nothing in the registry. The app reads `SystemUsesLightTheme` to pick the text and tray icon colors.
