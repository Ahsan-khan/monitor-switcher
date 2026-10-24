# Current status (last updated 2026-10-23, end of session 3)

## In one paragraph
**Monitor Switcher** works. It's a small Windows tray app, built on each PC by one PowerShell script, that switches the Samsung Odyssey G91F between the **Nvidia** PC (DisplayPort, input 15) and the **AMD** PC (HDMI 1, input 17). Since session 3 the widget sits **inside the taskbar** and shows **CPU, GPU and RAM use for both PCs**; the PCs send each other their numbers over the home network. On the **AMD PC** the new version is installed and running, docked left of the tray, and Windows Firewall allows it. The **Nvidia PC** still runs the 2026-10-22 version, so on the AMD PC its tile says "no usage data". The change is committed but **not pushed**, and the install command downloads from GitHub `main`, so the Nvidia PC can only get it after a push.

## What works (verified on the AMD PC, 2026-10-23)
- **Taskbar widget:** docked left of the tray, with this PC's live CPU / GPU / RAM and the accent bar under the PC on screen. A fake "Nvidia" message sent to the app showed up on the Nvidia tile.
- **Desktop mode:** the same row in the floating card, with the taskbar left clear.
- **Which PC is this:** detected from the cable (HDMI = AMD), even while the monitor was showing the Nvidia PC.
- **Usage readings:** Task Manager's method; the whole app costs about 0.03% CPU.
- **Setup:** builds with the new manifest, prints which PC it's on, and mentions Windows' network prompt.
- Panel, hotkeys, tray icon and command line: as before.

## Not verified yet
- The real link between the two PCs (needs the Nvidia PC on the new version).
- Clicking the new tray menu items (Widget, This PC is) and clicking a tile to switch. They weren't clicked during testing, because a switch hides the AMD PC's screen.
- An Explorer restart, a light taskbar, an auto-hiding taskbar, a crowded taskbar.

## Known gaps / not built yet
- No uninstall, version number or update check (see `06_roadmap`).
- No automated tests. Use the compile check in `07_dev_environment`.
- If broadcasts can't reach the other PC (different networks, Wi-Fi client isolation), there's no way to type its address.
- Windows only. The Mac script was removed on 2026-10-21 (it's in git history).
- `.gitattributes` still has a leftover `*.sh` rule.

## Owner's to-dos (suggested)
1. Push the commit (or let the assistant push it), then run the README install command on the **Nvidia PC** and click **Allow** when Windows asks about the network.
2. Check both tiles show numbers on both PCs, and say if you'd like a different look.

## Suggested first thing next session
1. Ask whether the Nvidia PC is updated and both tiles show numbers on both PCs.
2. If the Nvidia tile says "no usage data": check both PCs run the new version, the network prompt was allowed on at least one PC, and both are on the same network.
3. Then ask what to build next (`06_roadmap`). For any change to the script: compile check, install from the checkout on the PC you're on (safe, doesn't switch inputs), and let the owner try switching. Ask before pushing.
