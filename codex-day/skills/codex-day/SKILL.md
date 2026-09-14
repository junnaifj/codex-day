---
name: codex-day
description: Operate or troubleshoot the Codex Day in-app calendar and editable to-do sticky notes, its local midnight extraction, and Apple Calendar/Reminders synchronization.
---
Codex Day is an external runtime extension plus a background EventKit helper. The visible UI is only inside Codex: a Day toggle in the top-right header opens two frosted glass cards. A plugin manifest alone cannot install a custom header control.

Daily operation uses no model, API, or token-consuming automation. A local launchd job scans explicit checklists/action sections at 00:00 in the Mac's timezone; launch or wake catches up once per date. It reads local Codex conversation files, including archived root tasks, but cannot read cloud-only ChatGPT history. This is conservative rule-based extraction, not semantic AI summarization; suggestions may be stale and require review. Never claim complete semantic task coverage.

Use the visible Day button for date selection, to-do edits, suggestion review, and Apple connection requests. Accepted to-dos sync to a dedicated Codex Day Reminders list when enabled. Calendar events are read-only. Preserve unrelated calendars, reminder lists, Codex configuration, and official application bundles.

Runtime: `~/Library/Application Support/Codex Day/runtime/`. User data: the parent directory's `tasks.json` and `suggestions.json`. LaunchAgent labels: `local.codex.day.helper`, `local.codex.day.bridge`, `local.codex.day.midnight`. Check their status with `launchctl print gui/$(id -u)/<label>`; do not dump personal task content into logs.

The persistent `~/Applications/Codex with Day.app` launcher opens the official host with the required loopback debug connection. It has no dashboard window and waits for the user to quit if the host is already open without debugging. The project's `scripts/enable-interface.sh` is the command-line alternative. Using the original official app icon bypasses the launcher and cannot retain this extension. Verify the listener's Codex process and signing identity; do not attach to arbitrary renderer targets or use remote debug endpoints. Never edit app.asar or re-sign the official app. Ask before restarting a running Codex instance; explain the running task interruption. The launcher deliberately refuses to terminate Codex itself.

Remove the runtime with the project's `scripts/uninstall.py`; it preserves tasks and Apple Reminders. A normal launch without the dedicated launcher closes debugging and removes the injected UI/theme. A launch through Codex with Day restores the interface automatically. The renderer remounts after page reconstruction, preserves panel visibility and material choice, and keeps the body text unfiltered. Installing/uninstalling the skill manifest alone does not start/stop the runtime jobs.
