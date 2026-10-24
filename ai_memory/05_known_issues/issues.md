# Known issues, risks and gotchas (as of 2026-10-23)

## Limits
- **Windows only.** Needs Windows PowerShell 5.1 and .NET Framework 4.x, which come with Windows. 1–9 sources.
- The app is compiled with the C# compiler built into .NET Framework, which only understands **C# 5** (D2).
- The widget re-reads the input only while it's visible. With the widget turned off, the highlight updates only when the panel opens.
- The UI is always dark. The tray icon picks dark or light ink once, at startup.
- No uninstall, no version number and no update check. A PC updates only when the owner runs the install command again.
- No automated tests. The compile check in `07_dev_environment` is the main safety net.

## Behaviors to know
- **On the AMD PC, a switch hides that PC's desktop** (the monitor is its only screen), including the Claude app. Never run `/switch`, click a widget tile or press Ctrl+Alt+1 there while testing without asking. `/get` is safe.
- Running the setup stops the app, rebuilds it, opens the panel, and waits for Enter at the end. It doesn't switch inputs.
- Clicking the widget tile that's already lit still sends the switch command. The panel skips it and just closes.
- The widget hides while a fullscreen app covers its screen (checked every second). A maximized window normally doesn't count, because it leaves the taskbar uncovered.
- The widget's position is saved after every drag. If the saved spot is off every screen, the widget goes to the bottom-right corner of the work area.
- If another app owns one of the hotkeys, a balloon at startup lists the taken ones ("... is already used by another app.").
- `$DirectHotkeys = $false` turns off Ctrl+Alt+1…9 for keyboards that type with AltGr + number.
- A failed switch shows "Couldn't reach the monitor. Is DDC/CI turned on?" (a balloon, or red text in the panel).
- `/get` exits with the current input, or -1 if it couldn't read the monitor. `/switch` exits 0 (OK), 1 (failed) or 2 (not a number).

## Untested
- Ctrl+Alt+1 / 2 from the PC the monitor isn't showing (see `03_architecture/ddc_ci.md`).
- The Nvidia PC: nothing was checked from the AMD PC.
- `$Monitor = "<number>"` on a PC with several monitors, and mixed-DPI setups.
- More than two sources since the MacBook was removed (the first version had three).

## Dev gotchas
- **Keep the .ps1 plain ASCII.** Windows PowerShell 5.1 reads a BOM-less script as ANSI, so "…" becomes "â€¦" (verified 2026-10-23). Write `…`, `’` and so on (D11).
- **C# 5 only:** no `$"..."`, `?.`, `nameof`, `=>` members, property initializers or `out var`. Verified 2026-10-23: a `$"..."` line fails with "Unexpected character '$'". Lambdas and `delegate { }` are fine; the code uses the `delegate` style throughout.
- Build errors give C# line numbers. The compile check prints the matching script line for you. For the setup's own error report, script line = C# line + 57 for lines after the Sources list (with two sources, as of a5a5315).
- The setup must run in Windows PowerShell 5.1. It relaunches itself if started from PowerShell 7.
- The setup kills any running `MonitorSwitcher.exe` before building, because the build overwrites the exe.
- The `$Monitor` number is matched against Windows' internal `\\.\DISPLAYn` name, not the number in Settings (the AMD PC's monitor is `\\.\DISPLAY9`).
- **`main` is what both PCs install.** A broken script on `main` breaks the next install on both PCs, so run the compile check before every commit that touches the script.
- The script's header comment (lines 4–9) is stale: it still says "Ctrl+Alt+1 / 2 / 3" and doesn't mention the widget. `.gitattributes` still has a `*.sh` rule for the deleted Mac script.
