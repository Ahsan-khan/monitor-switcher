# Known issues, risks and gotchas (as of 2026-10-23, end of session 3)

## Limits
- **Windows only.** Needs Windows PowerShell 5.1 and .NET Framework 4.x, which come with Windows. 1–9 sources.
- The app is compiled with the C# compiler built into .NET Framework, which only understands **C# 5** (D2).
- The taskbar widget goes on the **primary taskbar** only, left of the tray. On a crowded taskbar, app icons could slide under it.
- The PCs must be on the **same network**, and Windows Firewall must allow the app on at least one of them.
- Usage updates once a second. The other PC's numbers count as missing after 5 s ("no usage data").
- GPU % is the busiest engine across all graphics adapters (Task Manager's method).
- The input highlight only updates while a widget is showing. With the widget hidden, it updates when the panel opens.
- The panel and the desktop card are always dark. The taskbar row follows the taskbar's light or dark setting.
- No uninstall, no version number and no update check. A PC updates only when the owner runs the install command again.
- No automated tests. The compile check in `07_dev_environment` is the main safety net.

## Behaviors to know
- **On the AMD PC, a switch hides that PC's desktop** (the monitor is its only screen), including the Claude app. Never run `/switch`, click a widget tile or press Ctrl+Alt+1 there while testing without asking. `/get` and `/whoami` are safe.
- Running the setup stops the app, rebuilds it, opens the panel, and waits for Enter at the end. It doesn't switch inputs.
- The first run on each PC makes Windows ask whether the app may use the network.
- Once the owner picks "This PC is" in the menu, detection stops (`SelfPicked=1`) until settings.ini is edited.
- Clicking the tile that's already lit still sends the switch command. The panel skips it and just closes.
- The desktop widget hides while a fullscreen app covers its screen. The taskbar widget hides along with the taskbar.
- If another app owns one of the hotkeys, a balloon at startup lists the taken ones. `$DirectHotkeys = $false` turns off Ctrl+Alt+1…9 for keyboards that type with AltGr + number.
- A failed switch shows "Couldn't reach the monitor. Is DDC/CI turned on?" (a balloon, or red text in the panel).
- Exit codes: `/get` = the current input or -1; `/whoami` = this PC's input or -1; `/switch` = 0 (OK), 1 (failed) or 2 (not a number).

## Untested
- The real link between the two PCs (the Nvidia PC needs the new version).
- Ctrl+Alt+1 / 2 from the PC the monitor isn't showing. Reading works from there (see `03_architecture/ddc_ci.md`).
- The new tray submenus and tile clicks, by hand.
- An Explorer restart (re-docking), a light taskbar, an auto-hiding taskbar, a taskbar on another monitor, mixed DPI.
- `$Monitor = "<number>"` on a PC with several monitors. More than two sources.

## Dev gotchas
- **Keep the .ps1 plain ASCII.** Windows PowerShell 5.1 reads a BOM-less script as ANSI, so "…" becomes "â€¦" (verified 2026-10-23). Write `\u2026`, `\u2019` and so on (D11).
- **AI file-writing tools can turn a typed `\u2026` into the real "…" character.** It happened on 2026-10-23, in the C# and in these notes. Check for non-ASCII before building (`LC_ALL=C grep -n $'[\x80-\xff]' setup-monitor-switcher-windows.ps1` in Git Bash), and when you need a literal backslash-u, build the backslash in code (for example Python `chr(92) + "u2026"`).
- **C# 5 only:** no `$"..."`, `?.`, `nameof`, `=>` members, property initializers or `out var`. Verified 2026-10-23: a `$"..."` line fails with "Unexpected character '$'". Lambdas and `delegate { }` are fine; the code uses the `delegate` style throughout.
- Build errors give C# line numbers. The compile check prints the matching script line for you. For the setup's own error report, script line = C# line + 59 for lines after the Sources list (with two sources, as of session 3).
- The compile check builds without the manifest. That's fine for catching errors, but **the taskbar widget only works in a build with the manifest**, as the real setup makes it.
- In PowerShell, passing `$null` to a .NET method's string parameter sends `""`, so a lookup like `FindWindowEx(bar, [IntPtr]::Zero, $null, "...")` silently finds nothing. Do window lookups inside `Add-Type` C# instead.
- Screenshots from PowerShell need `SetProcessDPIAware()` first, or the coordinates are scaled (the AMD PC runs at 125%).
- The setup can run while the monitor shows the other PC (for example when an assistant runs it while the owner is on the other PC). Never treat "what the monitor shows" as "which PC this is"; that's why `/whoami` exists (D18).
- The setup must run in Windows PowerShell 5.1. It relaunches itself if started from PowerShell 7, and it kills any running `MonitorSwitcher.exe` first, because the build overwrites the exe.
- The `$Monitor` number is matched against Windows' internal `\\.\DISPLAYn` name, not the number in Settings (the AMD PC's monitor is `\\.\DISPLAY9`).
- **`main` is what both PCs install.** A broken script on `main` breaks the next install on both PCs, so run the compile check before every commit that touches the script.
- `.gitattributes` still has a `*.sh` rule for the deleted Mac script.
