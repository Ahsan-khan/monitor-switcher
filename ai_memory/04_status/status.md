# Current status (last updated 2026-10-23, end of session 3)

## In one paragraph
**Monitor Switcher** works. It's a small Windows tray app, built on each PC by one PowerShell script, that switches the Samsung Odyssey G91F between the **Nvidia** PC (DisplayPort, input 15) and the **AMD** PC (HDMI 1, input 17). On the **AMD PC** it's installed, starts at sign-in and runs the latest build (made 2026-10-22 13:50, after the last code change). The monitor answers there: `/get` returned 17 on 2026-10-23. The widget's settings were last saved on 2026-10-23, so it's in use. The **Nvidia PC** wasn't checked from here.

## What works
- **Desktop widget:** click a PC to switch, drag it anywhere, right-click for the menu. It hides during fullscreen. Its highlight follows the monitor (re-read every 2 s and on display changes).
- **Panel:** Ctrl+Alt+M or the tray icon. Click a tile or press 1 / 2; Esc closes it. It shows "Switching…", or an error and a shake if the monitor doesn't answer.
- **Hotkeys:** Ctrl+Alt+1 → Nvidia, Ctrl+Alt+2 → AMD.
- **Tray menu:** Open switcher, Show desktop widget, Keep widget on top, Quit.
- **Setup:** one command per PC; run it again to update. It prints which PC it's on, and warns about an unknown input code or DDC/CI being off.
- **Command line:** `/switch <code>`, `/get`, `/show`.

## Known gaps / not built yet
- No uninstall, version number or update check (see `06_roadmap`).
- No automated tests. Use the compile check in `07_dev_environment`.
- Windows only. The Mac script was removed on 2026-10-21 (it's in git history).
- Not verified: switching with a hotkey from the PC the monitor isn't showing.
- Small cleanups: the script's header comment is stale, and `.gitattributes` has a leftover `*.sh` rule.

## Owner's to-dos (suggested)
- If the Nvidia PC hasn't run the install command since 2026-10-22, run it there once to get the faster widget updates.

## Suggested first thing next session
1. Ask the owner what to build next. If they have nothing in mind, offer the P1 cleanups in `06_roadmap`.
2. For any change to the script: run the compile check, install from the checkout on the PC you're on (safe, doesn't switch inputs), and let the owner try switching.
3. Commit when asked. Ask before pushing, because `main` is what both PCs install.
