# Roadmap (ideas only; nothing agreed with the owner yet)

Done in sessions 1–2: the tray app and panel, direct hotkeys, the desktop widget, the two-PC setup (Nvidia / AMD), and faster widget updates. Session 3 added this `ai_memory/` folder.

## P1: Small cleanups (offer these first)
- Update the script's header comment (lines 4–9): Ctrl+Alt+1 / 2, and mention the widget.
- Drop the leftover `*.sh` line from `.gitattributes`.
- Make sure the Nvidia PC runs the latest build (run the install command there once).

## P2: Possible improvements (ask the owner first)
- Show a version (for example the commit date) in the tray menu, plus an "Update" item that runs the install command.
- An uninstall option (tray menu or a small script) that removes the folder and the three shortcuts.

## P3: Bigger, only if asked
- Bring back the MacBook. The old Mac script is in git (`git show 6da1198:setup-monitor-switcher-mac.sh`).
- Other monitor controls over DDC/CI (brightness, volume) from the widget. Check which codes the G91F supports first.
