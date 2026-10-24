# Project overview

## What it is
**Monitor Switcher** gives one-click input switching for a monitor shared by two Windows PCs. Each PC runs a small tray app with a widget **in the taskbar** that shows **both PCs' CPU, GPU and RAM use**. Click the other PC's tile (or press Ctrl+Alt+1 / 2) and the monitor changes input. Switching goes straight to the monitor over the video cable (DDC/CI). The usage numbers travel between the PCs over the home network. There's no extra hardware or third-party tool.

## Goal (from the README, the commits and the owner's requests)
"One-click input switching for a monitor shared by two Windows PCs (Nvidia on DisplayPort, AMD on HDMI 1)." The setup script adds: jump straight to a source with a hotkey "even when the monitor is showing another computer". Later commits made the widget always visible, and quick to update "when the other PC switches". On 2026-10-23 the owner asked: "show ram, gpu and cpu usage for both" and "put the widget in the task bar". Later that day (session 4): "i keep forgetting what pc I am on, make it more prominient some how" (D22). The chats from sessions 1–2 aren't on this PC.

## Setup and scope (from the code and history)
| Topic | Answer |
|---|---|
| Monitor | **Samsung Odyssey G91F**, shared by both PCs |
| Nvidia PC | DisplayPort → input code **15**. Color green `#76B900` |
| AMD PC | HDMI 1 → input code **17**. Radeon RX 5700 XT. Color maroon `#8E1622`. The local checkout and the session 3–4 work are on this PC |
| MacBook | Was on HDMI 2 (code 18) in the first version. **Dropped on 2026-10-21**, along with the Mac script |
| Before this app | NirSoft ControlMyMonitor, run from "Switch to ..." desktop shortcuts. The setup deletes those |
| Platform | Windows only: Windows PowerShell 5.1 + .NET Framework, both built into Windows |
| Install | One PowerShell command per PC (in the README). Running it again updates the app |
| Where it runs | Per user, in `%LOCALAPPDATA%\MonitorSwitcher`. Starts at sign-in |
| Network | Both PCs on the same home network; they talk on UDP port 47815. The AMD PC is on Wi-Fi (set to Private) |

## Owner / environment
- GitHub `Ahsan-khan`, **public** repo https://github.com/Ahsan-khan/monitor-switcher, on `main`.
- Local path on the AMD PC: `C:\Users\User\Documents\GitHub\monitor-switcher`. Uses the Claude desktop app.
- The owner keeps an `ai_memory/` folder in most projects and often starts a session with "read every file in ai_memory".
- The owner may be using the other PC while an assistant works on this one (in session 3 the monitor was on the Nvidia PC for a while). Don't assume they can see this PC's screen.

## Owner preferences (observed across projects)
- Prefers short replies and fast progress. **Give click-by-click steps** for anything they do by hand.
- Prefers simple, familiar flows and tools they own over new services.
- Never ask for, read or print their passwords or API keys.
- Likes picking from options for visual things (icons, colors, layouts).
- Usually lets the assistant make the technical calls. Commit when asked; **ask before pushing**, because `main` is public and is what both PCs install from.

## Names and IDs
- Product name **Monitor Switcher**. Exe `MonitorSwitcher.exe`, C# namespace `MonitorSwitcher`, folder `%LOCALAPPDATA%\MonitorSwitcher`, shortcuts `Monitor Switcher.lnk`.
- Single-instance names: mutex `Local\MonitorSwitcher.Instance`, event `Local\MonitorSwitcher.Show`.
- The taskbar widget's window title: `Monitor Switcher taskbar widget` (a child of `Shell_TrayWnd`).
- Network: UDP port **47815**; messages start with `MSW1|`.
- The PCs are called **Nvidia** and **AMD** in the UI (renamed from "PC 1" / "PC 2" on 2026-10-21).
