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

## Tile layout and styles (`StatTile`, `TileBody`)
- Every tile shares one frame: a faint background (brighter on hover) and click to switch. **The tile of the PC you're on** (this PC, `Settings.Self`) is tinted in that PC's color with a 1 px border, and its icon and name sit in a solid tag of that color (`NameTag`, since session 4, D22). A 16×3 accent bar marks the PC that's on screen, like the line Windows draws under running apps, but only under **another** PC's tile (you'd see it on a second screen); this PC's tint says it already. It says "no usage data" when nothing fresh (under 5 s old) is known, and "Switching…" while switching. The width never jumps: numbers sit in fixed boxes, and notes cover them without changing the size.
- The numbers part comes from the style the owner picks (tray menu > Widget style; `WidgetStyle` in settings.ini; Classic by default). Widths per tile, measured from screenshots:
  - **Classic:** icon, name, then "CPU 23%  GPU 5%  RAM 61%" (labels 10 px at 60% opacity, values 10.5 px semibold in 28 DIP boxes). About 215 DIP.
  - **Bars:** icon, name, then a 50 DIP meter per metric with its label and number. About 190 DIP.
  - **Rings:** name, then a 24 DIP ring gauge per metric with the number inside and the label under it. About 150 DIP.
  - **Graphs:** icon, name, then a 44×19 DIP graph of the last 40 seconds per metric, with its label and number above. About 230 DIP.
- Metric colors (Bars, Rings, Graphs): CPU blue #60A5FA, GPU purple #C084FC, RAM teal #2DD4BF, with darker shades on a light taskbar. 90% or more turns amber (#FFC14D on dark, #B45309 on light) in every style.
- All four were captured in the AMD PC's taskbar on 2026-10-23, with live numbers from both PCs.
- The name tag adds about 1 DIP per tile; the row on the AMD PC (Graphs, 125%) is about 578 px wide.

## Which PC you're on: colors, tag and the "You're on" card (session 4, D22)
- Colors come from `$Sources` (`Color = "#RRGGBB"`): Nvidia `#76B900`, AMD `#8E1622` (maroon; it was `#ED1C24` until the owner asked for a darker red). Text on a color is near-black or white by contrast, with white winning close calls (`Theme.InkOn`): white on AMD maroon, black on Nvidia green.
- Taskbar and desktop widget: tint (alpha 0x2E) + border (alpha 0xA0) + solid name tag on this PC's tile. Same on light and dark taskbars.
- Tray icon: the monitor glyph's screen is filled with this PC's color; tooltip "Monitor Switcher: you’re on AMD (Ctrl+Alt+M)" (cut to 63 characters, Windows' limit).
- Switcher panel: a "This PC" chip in the PC's color at the top right of that tile.
- `NameBanner`: a small card (about 150×75 DIP) in the PC's color slides in at the top-right corner, 16 DIP from the edges, with the logo of the graphics card's maker and "You're on" over the name. It stays 2.5 s, then fades in 0.35 s. It shows when the monitor comes over from the other PC: It shows as soon as the mouse or keyboard has been used here since the switch was noticed (but not in the first 0.5 s, while the picture comes up), or after 3 s anyway. While the monitor shows another PC, the input is checked every 0.5 s instead of every 2 s, so a switch back is noticed quickly. Measured in the logic test: shown 0.66 s after the switch was noticed with input, 3.09 s without. (First version: input in the first 1.5 s was ignored and it waited for the next input, with a 2 s poll; the owner found it "very late".) Click-through (`WS_EX_TRANSPARENT`), `WS_EX_NOACTIVATE`, topmost. The window is made on first use and then reused.
- **The logo** (`Logo` class): taken at runtime from the maker's own app on this PC, so the public repo ships no logo artwork. The maker comes from the name of the graphics card driving the monitor (`EnumDisplayDevices`, for example "AMD Radeon RX 5700 XT"). AMD: the icon of `Program Files/AMD/CNext/CNext/RadeonSoftware.exe`, else `AMD/CIM/Bin64/AMDSoftwareInstaller.exe`. NVIDIA, in order: `NVIDIA Corporation/NVIDIA app/CEF/NVIDIA app.exe`, `Control Panel Client/nvcplui.exe`, `NVIDIA GeForce Experience/NVIDIA GeForce Experience.exe`, `NvContainer/nvcontainer.exe` (untested: there's no NVIDIA card on the AMD PC). If the icon is a white mark on a solid square (AMD's arrow on red), only the mark is kept and drawn in the card's text color; other icons show as a rounded tile. A `logo.png` in `%LOCALAPPDATA%/MonitorSwitcher` wins. With no logo, the card shows the PC's monitor icon.

## Usage numbers (`Stats`)
- PDH with English counter paths (`PdhAddEnglishCounter`), so it works in any Windows language. One query, collected every second on a background thread (`App.StartStats`, below-normal priority). A sample takes 1–3 ms. The whole app used about 0.03% of the CPU on the AMD PC.
- **CPU:** `\Processor Information(_Total)\% Processor Utility` (what Task Manager shows), falling back to `\Processor(_Total)\% Processor Time`. Clamped to 0–100.
- **GPU:** `\GPU Engine(*)\Utilization Percentage`, about 600 instances (one per process and engine). Each engine is summed across processes (the key is the instance name from `_luid_` on), and the busiest engine wins, like in Task Manager. New processes are picked up automatically (verified). It works the same for AMD and Nvidia cards.
- **RAM:** `GlobalMemoryStatusEx`: (total − available) / total.
- PDH array items are 24 bytes on 32- and 64-bit: a name pointer, the status at +8 and the value at +16.

## Accuracy check (2026-10-23)
The widget's on-screen text (read through UI Automation) was compared with Windows' own counters, read at the same moment by PowerShell's `Get-Counter`:
- Idle: RAM 73% vs 73% on every sample; GPU 4–7% vs 4–6%; CPU within a few points (CPU changes from second to second, and the two readings don't cover exactly the same second).
- All 16 logical cores busy: CPU 100% vs 100%.
- 2 GB of RAM taken: RAM 73% → 85% vs 85%; 71% after it was released.
- A blurred, spinning test window: GPU 5% → 58% vs 58%; about 5% after it closed.
- All three loads at once: CPU 100% (shown in amber), GPU 22% (the busy CPU slowed the test window down), RAM 86%.

How to repeat it: "Check the numbers" in `07_dev_environment`.

The link was then seen working between the real PCs: once the owner installed the session 3 build on the Nvidia PC, its tile on the AMD PC updated every second (CPU 32–51%, GPU 94–100%, RAM 69%, at a time nobody was looking at the Nvidia PC). The high GPU there was not explained yet; compare with Task Manager on that PC.

## What the app costs (2026-10-23, D20)
Measured with the same script on the AMD PC, after a fresh start (Task Manager's "Memory" = private working set):

| Build | RAM | GPU memory | CPU (whole PC) |
|---|---|---|---|
| Before session 3 (desktop widget, no usage) | 51 MB | 13 MB | 0.02% |
| Session 3 taskbar build | 65 MB | 20 MB | 0.06% |
| Drawn with the CPU | 22 MB | 0 MB | 0.05% |
| Unused memory handed back | 18 MB | 12 MB | 0.06% |
| **Both (installed)** | **12.9 MB** | **0 MB** | **0.04%** |

The usage readings themselves take 1–3 ms a second; the rest of the CPU is redrawing the tiles and the 2 s input poll.

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
