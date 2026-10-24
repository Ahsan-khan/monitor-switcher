# How switching works (DDC/CI)

## The basics
- **DDC/CI** is a control channel that runs over the video cable (HDMI or DisplayPort). Monitors use it for things like brightness and input select. It must be **turned on in the monitor's own menu**.
- The standard (VESA MCCS) calls each setting a **VCP code**. Input select is **`0x60`**. Writing a number to it switches the input; reading it returns the current input.
- Windows exposes this in `dxva2.dll`. The app uses:
  - `EnumDisplayMonitors` and `GetMonitorInfo` (user32) to find the monitor,
  - `GetPhysicalMonitorsFromHMONITOR` to get a handle to it,
  - `SetVCPFeature(handle, 0x60, code)` to switch,
  - `GetVCPFeatureAndVCPFeatureReply(handle, 0x60, …)` to read the current input,
  - `DestroyPhysicalMonitors` to clean up.

## Input codes
| Port | Standard code | On this monitor (G91F) |
|---|---|---|
| DisplayPort 1 | 15 (`0x0F`) | Nvidia PC |
| DisplayPort 2 | 16 (`0x10`) | not used |
| HDMI 1 | 17 (`0x11`) | AMD PC (`/get` returned 17 on 2026-10-23) |
| HDMI 2 | 18 (`0x12`) | the MacBook, until 2026-10-21 |

- Some brands use their own numbers, or a different VCP code. For example, the removed Mac script had an `input-alt` setting for LG monitors. If a code doesn't work, read the real one (below).
- `GetInput` keeps only the low byte of the reply (`current & 0xFF`), since some monitors set the high byte.

## How to find a port's code
- Run the setup on a PC while the monitor shows that PC. It prints "The monitor is showing input N, so this computer is '<name>'", or warns if N isn't in the list.
- Or read it at any time (safe, read-only):
  ```powershell
  (Start-Process "$env:LOCALAPPDATA\MonitorSwitcher\MonitorSwitcher.exe" -ArgumentList /get -Wait -PassThru).ExitCode
  ```
  The exit code is the input. **-1** means the monitor couldn't be read.

## Which monitor gets the command
- `$Monitor = "Primary"` (the default) picks Windows' primary display.
- A number picks the display whose device name is `\\.\DISPLAY<number>`. **That's Windows' internal number, not the one in Settings → Display.** On the AMD PC, the only monitor is `\\.\DISPLAY9`. Keep "Primary" unless a PC has several monitors.
- The command goes to every physical monitor behind that display, and counts as a success if any of them accepts it.

## Reliability details
- `SetInput` tries up to 3 times, 80 ms apart. `GetInput` tries twice, 50 ms apart.
- All DDC calls inside the app go through one lock, so a poll never overlaps a switch. A separate `/get` or `/switch` process isn't covered by that lock.
- A read takes "a few dozen milliseconds" (code comment), which is why polling every 2 s is fine.

## Switching from the PC that isn't on screen
- The script's header says the hotkeys work "even when the monitor is showing another computer". That depends on the monitor still answering DDC on an input it isn't showing, and on Windows still treating the monitor as connected. **Not verified on the G91F** as of 2026-10-23.
- When the monitor comes back to a PC, Windows raises a display-change event and the app re-reads the input right away. That keeps the widget's highlight right (D9).
