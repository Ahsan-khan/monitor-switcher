# Project overview

## What it is
**Monitor Switcher** gives one-click input switching for a monitor shared by two Windows PCs. Each PC runs a small tray app with a desktop widget. Click the other PC's tile (or press Ctrl+Alt+1 / 2) and the monitor changes input. The app sends the command straight to the monitor over the video cable (DDC/CI), so there's no extra hardware, network link or third-party tool.

## Goal (from the README and commits; the original chats aren't on this PC)
"One-click input switching for a monitor shared by two Windows PCs (Nvidia on DisplayPort, AMD on HDMI 1)." The setup script adds: jump straight to a source with a hotkey "even when the monitor is showing another computer". Later commits made the widget always visible, and quick to update "when the other PC switches".

## Setup and scope (from the code and history)
| Topic | Answer |
|---|---|
| Monitor | **Samsung Odyssey G91F**, shared by both PCs |
| Nvidia PC | DisplayPort → input code **15** |
| AMD PC | HDMI 1 → input code **17**. Radeon RX 5700 XT. The local checkout and the 2026-10-23 session are on this PC |
| MacBook | Was on HDMI 2 (code 18) in the first version. **Dropped on 2026-10-21**, along with the Mac script |
| Before this app | NirSoft ControlMyMonitor, run from "Switch to ..." desktop shortcuts. The setup deletes those |
| Platform | Windows only: Windows PowerShell 5.1 + .NET Framework, both built into Windows |
| Install | One PowerShell command per PC (in the README). Running it again updates the app |
| Where it runs | Per user, in `%LOCALAPPDATA%\MonitorSwitcher`. Starts at sign-in |

## Owner / environment
- GitHub `Ahsan-khan`, **public** repo https://github.com/Ahsan-khan/monitor-switcher, on `main`.
- Local path on the AMD PC: `C:\Users\User\Documents\GitHub\monitor-switcher`. Uses the Claude desktop app.
- The owner keeps an `ai_memory/` folder in most projects and often starts a session with "read every file in ai_memory".

## Owner preferences (observed across projects)
- Prefers short replies and fast progress. **Give click-by-click steps** for anything they do by hand.
- Prefers simple, familiar flows and tools they own over new services.
- Never ask for, read or print their passwords or API keys.
- Likes picking from options for visual things (icons, colors, layouts).
- Usually lets the assistant make the technical calls. Commit when asked; **ask before pushing**, because `main` is public and is what both PCs install from.

## Names and IDs
- Product name **Monitor Switcher**. Exe `MonitorSwitcher.exe`, C# namespace `MonitorSwitcher`, folder `%LOCALAPPDATA%\MonitorSwitcher`, shortcuts `Monitor Switcher.lnk`.
- Single-instance names: mutex `Local\MonitorSwitcher.Instance`, event `Local\MonitorSwitcher.Show`.
- The PCs are called **Nvidia** and **AMD** in the UI (renamed from "PC 1" / "PC 2" on 2026-10-21).
