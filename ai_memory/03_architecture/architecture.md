# Architecture (as of 2026-10-23, commit a5a5315)

```
  Nvidia PC ──── DisplayPort (input 15) ────┐
                                            ├──► Samsung Odyssey G91F
  AMD PC ─────── HDMI 1 (input 17) ─────────┘     (one screen, two inputs)
```
- Each PC runs its own copy of `MonitorSwitcher.exe`. A switch is one DDC/CI command over that PC's own video cable: "set VCP `0x60` (input select) to N". See `ddc_ci.md`.
- **There's no network link between the PCs.** Each one learns about the other's switches by reading VCP `0x60` back from the monitor.
- Everything is in **one file**, `setup-monitor-switcher-windows.ps1` (about 1,460 lines): the settings, the whole C# app as a here-string, and the PowerShell that builds and installs it.

## Build and install (what the setup script does)
1. If started from PowerShell 7, it relaunches itself in Windows PowerShell 5.1, which the build needs.
2. Checks the settings: the hotkey is one letter, `Monitor` is "Primary" or a number, and there are 1–9 sources.
3. Stops any running `MonitorSwitcher.exe` and waits 400 ms.
4. Fills the placeholders in the C# source from the settings.
5. Compiles with `CSharpCodeProvider` (`/target:winexe /optimize+`) to `%LOCALAPPDATA%\MonitorSwitcher\MonitorSwitcher.exe`. If there are errors, it prints them and waits for Enter.
6. Draws `MonitorSwitcher.ico` (an indigo → purple tile with a white monitor).
7. Creates the Desktop, Start menu and Startup shortcuts, and deletes old ControlMyMonitor "Switch to ..." desktop shortcuts.
8. Runs `/get` to see which input the monitor is on, starts the app with `/show`, and prints which PC this is. Waits for Enter to close.

## Runtime flows
**Start:** `Main` handles `/switch` and `/get` and exits. Otherwise it takes the single-instance mutex (or signals the running copy to show its panel, and exits). Then it loads settings.ini, creates the panel and widget windows, the tray icon and the hotkeys, and reads the current input in the background. Finally it shows the widget and starts the timers.

**Switch from the widget:** click a tile → it shows "Switching…" → `Ddc.SetInput(code)` runs on a worker thread. On success, `App.LastInput = code` and every view refreshes. On failure, the widget shakes and a tray balloon says "Couldn't reach the monitor. Is DDC/CI turned on?"

**Switch from the panel:** Ctrl+Alt+M or the tray icon opens it in the middle of the screen, and it re-reads the input. Click a tile or press 1–9. Picking the PC that's already on screen just closes the panel. A successful switch closes it after 280 ms. A failure shows red text and a shake.

**Direct hotkey:** Ctrl+Alt+N arrives as `WM_HOTKEY` (id 10 + N − 1) → `App.SwitchDirect` → the same switch, with a balloon on failure.

**Keeping the highlight right:** a 2 s timer calls `PollInput`, which is skipped while the widget is hidden or a read is still running. Windows' display-change event re-places the widget and polls at once. Showing the widget again, or opening the panel, also re-reads.

**Fullscreen hiding:** every 1 s, the widget hides if the foreground window isn't this app, the desktop or the taskbar, and covers the whole screen the widget is on. It comes back (and polls) when that's no longer true.

## Code map (`setup-monitor-switcher-windows.ps1`, line numbers as of a5a5315)
### PowerShell
| Lines | Part | Role |
|---|---|---|
| 1–9 | Header comment | How to run it. Partly stale: still says Ctrl+Alt+1 / 2 / 3 and doesn't mention the widget |
| 11–34 | **Settings** | `$Sources`, `$Monitor`, `$HotkeyLetter`, `$DirectHotkeys`. The only part the owner edits |
| 36–55 | Checks | PowerShell 7 relaunch, setting checks, paths, stop the running copy |
| 58–1323 | `$AppSource` | The C# app (next table) |
| 1326–1338 | Fill-in | `ConvertTo-CSharpString` and the placeholder replacement |
| 1340–1367 | Build | `CSharpCodeProvider` compile and the error report |
| 1369–1411 | App icon | Draws the 256 px icon and writes it as a PNG-in-ICO file |
| 1413–1436 | Shortcuts | Desktop, Start menu, Startup; removes old ControlMyMonitor shortcuts |
| 1438–1464 | Launch | `/get` probe, start with `/show`, summary text |

### C# inside `$AppSource` (namespace `MonitorSwitcher`)
| Lines | Class | Role |
|---|---|---|
| 78–89 | `Source` | Name, Port, Code and Icon of one PC |
| 91–100 | `Config` | The baked-in settings (placeholders) |
| 103–225 | `Ddc` | Finds the monitor. `SetInput` (3 tries, 80 ms apart), `GetInput` (2 tries, 50 ms apart, low byte). One lock around both |
| 227–269 | `Native` | user32 calls: hotkeys, window styles, foreground window, monitor info |
| 272–320 | `Settings` | Reads and writes settings.ini |
| 323–344 | `Theme` | Accent gradient #6366F1 → #A855F7, glow #8B5CF6, white tints, easing |
| 346–503 | `Tile` | Panel tile (136×124): number badge, icon, name, and the port or "On screen". Also `MakeIcon` (desktop / laptop / tv) |
| 506–588 | `MiniTile` | Widget tile (80×54) |
| 590–748 | `WidgetWindow` | The desktop widget: grip, drag, right-click menu, placement, click-to-switch, shake |
| 750–769 | `DarkMenuColors` | Dark colors for the tray menu |
| 771–1016 | `SwitcherWindow` | The panel: header with the hotkey hint, tiles, status line, keys, show and hide animations |
| 1019–1321 | `App` | `Main` and the command-line verbs, single instance, hotkeys (`WndProc`, `RegisterHotkeys`), `SwitchDirect`, timers, fullscreen check, `PollInput`, tray icon and menu |

### Other files
| File | Role |
|---|---|
| `README.md` | The one-line install command and the basics |
| `Install Monitor Switcher.cmd` | Double-click launcher for the script next to it (for a downloaded copy) |
| `.gitattributes` | CRLF for `.ps1` and `.cmd`. The `*.sh` rule is left over from the Mac script |

## What lives on each PC
- `%LOCALAPPDATA%\MonitorSwitcher\`: `MonitorSwitcher.exe`, `MonitorSwitcher.ico`, `settings.ini`.
- Shortcuts named `Monitor Switcher.lnk`: Desktop (`/show`), Start menu Programs (`/show`), Startup (no arguments).
- Nothing in the registry. The app only reads the taskbar theme (`SystemUsesLightTheme`) to color the tray icon.
