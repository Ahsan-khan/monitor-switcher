# ai_memory: project brain for Monitor Switcher (repo monitor-switcher)

This folder holds everything a new AI session needs to keep building Monitor Switcher without redoing earlier work. Read it in this order:

| # | File | What's inside |
|---|------|---------------|
| 1 | `01_project/overview.md` | What it is, the owner's setup and preferences (**read the preferences**) |
| 2 | `04_status/status.md` | What works now, gaps, and the suggested first thing to do |
| 3 | `03_architecture/architecture.md` | How it fits together, plus a code map with line numbers |
| 4 | `03_architecture/ddc_ci.md` | How the monitor gets switched (DDC/CI), input codes, how to find them |
| 5 | `02_decisions/decisions.md` | Every major choice and why (D1–D13). Don't re-litigate without reason |
| 6 | `05_known_issues/issues.md` | Limits, behaviors, untested areas, gotchas |
| 7 | `06_roadmap/roadmap.md` | Ideas for what's next (nothing agreed with the owner yet) |
| 8 | `07_dev_environment/environment.md` | This PC, **install and compile-check commands**, testing patterns |
| 9 | `08_session_log/` | A dated log of each session |

**Rules:**
- At the end of each session, update `04_status/status.md`, add a session log entry, and record new decisions.
- **This repo is public.** Keep emails, account IDs and other personal details out of these files.
- Never read, print or commit passwords or API keys.
- Don't switch the monitor's input from the PC you're working on without asking. On the AMD PC the monitor is the only screen, so a switch hides the session (see `07_dev_environment`).
