# Taskbar widget, usage numbers and the PC-to-PC link (added 2026-10-23)

## The taskbar widget (`TaskbarDock`)
- Windows 11 has no taskbar toolbars ("deskbands") any more. The app puts its own **child window inside the taskbar** (`Shell_TrayWnd`) and places it just left of the tray (`TrayNotifyWnd`, which covers the ^ chevron, the tray icons and the clock). Verified on the AMD PC (Windows 11 build 26200): `TrayNotifyWnd`'s rectangle matches the visible tray exactly.
- The child is a WPF `HwndSource` with `UsesPerPixelTransparency = true`, so the taskbar shows through it.
- **A see-through (layered) child window needs an app manifest that declares Windows 8 or later.** Without it, `CreateWindowEx` fails with "The operation completed successfully". A prototype confirmed this: it failed without the manifest in every DPI mode, and worked with it. The setup writes the manifest at build time (D15).
- It answers `WM_MOUSEACTIVATE` with `MA_NOACTIVATE`, so clicking it doesn't take focus from the app in front.
- Fully transparent pixels don't take clicks, so the row and the tiles have an almost invisible fill (alpha 1).
- Every second, `App.KeepDocked` docks it again if the taskbar was re-created (an Explorer restart). Otherwise it re-places it, because the tray gets wider or narrower as icons come and go. It also re-asserts the top of the z-order among the taskbar's children, above `Windows.UI.Composition.DesktopWindowContentBridge` (the taskbar's own content). A failed dock is retried every 10 s, and the desktop widget shows in the meantime.
- Size on the AMD PC (125% scaling): 439×40 DIP (549×50 px) in a 60 px taskbar, 6 DIP left of the tray.
- The text color follows the taskbar: white on dark, near-black on light (`SystemUsesLightTheme`). A theme change re-docks it with the new color.
- Desktop mode reuses the same row inside the old floating card (`WidgetWindow`). The tray menu's Widget items set `WidgetMode` and call `ApplyWidgetMode`.

## Tile layout (`StatTile`)
- An icon, the name (12 px semibold), then "CPU 23%  GPU 5%  RAM 61%". Labels are 10 px at 60% opacity; values are 10.5 px semibold in fixed 28 DIP boxes, so the width never jumps.
- A 16×3 accent bar under the PC that's on screen (like the line Windows draws under running apps), plus a faint background.
- Values of 90% or more turn amber (#FFC14D on dark, #B45309 on light).
- "no usage data" when nothing fresh (under 5 s old) is known, and "Switching…" while switching.

## Usage numbers (`Stats`)
- PDH with English counter paths (`PdhAddEnglishCounter`), so it works in any Windows language. One query, collected every second on a background thread (`App.StartStats`, below-normal priority). A sample takes 1–3 ms. The whole app used about 0.03% of the CPU on the AMD PC.
- **CPU:** `\Processor Information(_Total)\% Processor Utility` (what Task Manager shows), falling back to `\Processor(_Total)\% Processor Time`. Clamped to 0–100.
- **GPU:** `\GPU Engine(*)\Utilization Percentage`, about 600 instances (one per process and engine). Each engine is summed across processes (the key is the instance name from `_luid_` on), and the busiest engine wins, like in Task Manager. New processes are picked up automatically (verified). It works the same for AMD and Nvidia cards.
- **RAM:** `GlobalMemoryStatusEx`: (total − available) / total.
- PDH array items are 24 bytes on 32- and 64-bit: a name pointer, the status at +8 and the value at +16.

## The PC-to-PC link (`Link`)
- UDP port **47815** on all network interfaces. Every second each PC sends `MSW1|<install id>|<its input code>|<cpu>|<gpu>|<ram>` to the broadcast address of every IPv4 network it's on (re-read every 30 s), plus a direct copy to every PC it has heard from.
- It ignores its own install ID, clamps the values, ignores messages over 200 bytes, and remembers at most 16 senders. No names or other personal data are sent.
- `Link.For(code)` returns the other PC's latest reading. If the other PC doesn't know which PC it is (code -1) and there are exactly two PCs, the reading counts as the one that isn't this PC.
- `SIO_UDP_CONNRESET` is turned off, so a direct copy to a sleeping PC doesn't break receiving.
- **Firewall:** Windows asks once per PC whether the app may use the network. On the AMD PC the owner clicked Allow on 2026-10-23 (inbound allow rules for Private and Public). If only one PC allows it, it still works: the blocked PC's broadcasts reach the open one, and Windows lets the open one's direct replies through as answers to those broadcasts.
- Both PCs must be on the same network (same subnet). Wi-Fi with "client isolation" would block it.

## Which PC is this? (`Identity`, `UpdateSelf`, `/whoami`)
- This PC's own numbers go on the tile whose input code is `Settings.Self`.
- `Identity.Detect()` asks Windows how the controlled monitor is plugged in (`QueryDisplayConfig` active paths, matched by the display's device name such as `DISPLAY9`). HDMI (5) → codes 17/18; DisplayPort (10, 11, or 18 over USB-C) → 15/16; DVI (4) → 3/4; VGA (0) → 1/2. If exactly one PC in the list uses that kind of port, it's this PC.
- Verified on the AMD PC: HDMI, even while the monitor was showing the Nvidia PC.
- It runs at startup and on every display change, unless the owner picked a PC in the menu (`SelfPicked=1`).
- The setup runs `MonitorSwitcher.exe /whoami` (exit code = input code, or -1). Only if that fails and no `Self` is saved yet does it guess from what the monitor shows.
- Why: the first version guessed from the screen, and saved the wrong PC when the setup ran while the monitor showed the other PC. That happened on 2026-10-23.
