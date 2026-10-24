# Roadmap (ideas only; check with the owner)

Done in sessions 1–4: the tray app and panel, direct hotkeys, the desktop widget, the two-PC setup (Nvidia / AMD), faster widget updates, this `ai_memory/` folder, (session 3) the taskbar widget with CPU / GPU / RAM for both PCs and four styles, and (session 4) per-PC colors, the "this PC" tag and the "You're on" card (D22).

## P1: Finish the taskbar widget
- Push, then install on the Nvidia PC (the owner runs the README command there and clicks Allow).
- Confirm both tiles show numbers on both PCs. If not, see `04_status` for what to check.
- Ask the owner about the look (they like picking between options).
- Drop the leftover `*.sh` line from `.gitattributes`.

## P2: Possible improvements (ask the owner first)
- If the tag and card aren't enough: a small always-on label in a screen corner (click-through), or a colored edge around the screen. Ask first; both cover a bit of the screen.
- A way to type the other PC's address, for networks where broadcasts don't get through.
- Show the usage in the big panel too.
- More numbers if wanted: GPU memory (`GPU Adapter Memory` counters), CPU or GPU temperature (needs vendor tools or admin rights, so harder).
- A version (for example the commit date) in the tray menu, plus an "Update" item that runs the install command.
- An uninstall option (tray menu or a small script) that removes the folder, the three shortcuts and the firewall rules.

## P3: Bigger, only if asked
- Bring back the MacBook. The old Mac script is in git (`git show 6da1198:setup-monitor-switcher-mac.sh`).
- Other monitor controls over DDC/CI (brightness, volume) from the widget. Check which codes the G91F supports first.
