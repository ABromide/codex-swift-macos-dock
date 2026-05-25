# Codex Dock Notifier

A small Swift macOS app that watches local Codex session logs and notifies you when Codex finishes a task.

It listens for new `final_answer` assistant messages under:

```text
~/.codex/sessions
```

When a new completion is detected, the app:

- posts a macOS notification in the top-right notification area
- bounces the Dock icon
- updates the Dock badge with the unread completion count
- shows a menu bar item with the current count and latest completed thread
- opens a local usage dashboard with daily, 7-day, 30-day, model, and session statistics

## Build and Run

```bash
make run
```

The first launch asks for macOS notification permission. The first scan records existing Codex sessions as the baseline, so it will not spam you with old completions.

## Start at Login

```bash
make install-login-item
```

To remove the launch agent:

```bash
make uninstall-login-item
```

## Notes

- The app uses local Codex JSONL files as the completion source. It does not need network access.
- Usage stats are calculated from `token_count.last_token_usage` events in local Codex session files. Model names are loaded from `~/.codex/state_5.sqlite` when available, with a JSONL-only fallback.
- Clicking the Dock icon or notification tries to open the Codex app.
- The persisted cursor state is stored at:

```text
~/Library/Application Support/CodexDockNotifier/state.json
```
