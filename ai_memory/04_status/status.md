# Current status (last updated 2026-10-23, end of session 4)

## In one paragraph
**Monitor Switcher** works. It's a small Windows tray app, built on each PC by one PowerShell script, that switches the Samsung Odyssey G91F between the **Nvidia** PC (DisplayPort, input 15) and the **AMD** PC (HDMI 1, input 17). The widget sits **inside the taskbar** and shows **CPU, GPU and RAM use for both PCs**, in one of four styles (the owner uses Graphs on the AMD PC). Everything is **pushed**, including session 4. Session 4 made **the PC you're on obvious** (D22): each PC has its own color (Nvidia green, AMD maroon), this PC's tile is tinted with a solid name tag, a big "You're on AMD" card shows after the monitor switches to this PC, the tray icon is filled with the PC's color, and the panel marks "This PC". That build is **installed on the AMD PC** and **pushed to `main`**; the Nvidia PC gets it when the owner runs the README install command there.

## What works (verified on the AMD PC, 2026-10-23)
- **Taskbar widget:** docked left of the tray, with live CPU / GPU / RAM for both PCs. A fake "Nvidia" message sent to the app showed up on the Nvidia tile.
- **Desktop mode:** the same row in the floating card, with the taskbar left clear.
- **Which PC is this:** detected from the cable (HDMI = AMD), even while the monitor was showing the Nvidia PC.
- **Usage readings:** Task Manager's method; the whole app costs about 0.03% CPU.
- **The numbers are real:** they match Windows' own counters, idle and under real CPU, RAM and GPU load (see "Accuracy check" in `03_architecture/taskbar_and_usage.md`).
- **Setup:** builds with the new manifest, prints which PC it's on, and mentions Windows' network prompt.
- Panel, hotkeys, tray icon and command line: as before.
- **Which PC you're on (session 4):** the AMD tag and tint show in the real taskbar (first bright red, then maroon at the owner's request). Offscreen renders checked all four styles on the owner's reddish taskbar, a dark one and a light one, for both PCs, plus the panel chip, the card and the tray icons. A logic test drove `App.InputChanged` like the poll does: the card waits for a switch back, ignores input in the first 1.5 s, shows on the next input, is click-through, doesn't take focus, is centered, goes away after about 2.5 s, and is cancelled by leaving again or by the menu switch (17 checks passed). **Then it worked for real:** the owner switched back from the Nvidia PC at 23:32 and the card showed for 2.6 s (seen by a script watching for its window).

## Not verified yet
- The new build on the Nvidia PC (needs a push, then the README command there).
- Clicking the tray items by hand: "This PC is" (now also flashes the card) and `Show "You're on AMD" after switching here`.
- The switcher panel (Ctrl+Alt+M) by eye since the switch to CPU drawing (D20), and its new "This PC" chip on screen (seen only in offscreen renders).
- The styles in the desktop widget and on a light taskbar, live (offscreen renders only).
- An Explorer restart, an auto-hiding taskbar, a crowded taskbar.

## Known gaps / not built yet
- No uninstall, version number or update check (see `06_roadmap`).
- No automated tests. Use the compile check in `07_dev_environment`.
- If broadcasts can't reach the other PC (different networks, Wi-Fi client isolation), there's no way to type its address.
- Windows only. The Mac script was removed on 2026-10-21 (it's in git history).
- `.gitattributes` still has a leftover `*.sh` rule.

## Owner's to-dos (suggested)
1. Run the README install command on the **Nvidia PC** so it shows its green tag and card too.
2. Say whether the maroon tag and card look right and are prominent enough.
3. The Nvidia PC's GPU showed 94–100% while nobody was using it (session 3): check Task Manager there.
4. Press Ctrl+Alt+M once to check the panel looks normal (CPU drawing, new chip).

## Suggested first thing next session
1. Ask whether the Nvidia PC has the session 4 build (green tag in its taskbar).
2. Ask whether the colors, tag and card work for them, or whether they want them bigger, smaller, other colors, or a permanent screen-corner label too.
3. Then ask what to build next (`06_roadmap`). For any change to the script: compile check, offscreen preview, install from the checkout on the PC you're on (safe, doesn't switch inputs), and let the owner try switching. Ask before pushing.
