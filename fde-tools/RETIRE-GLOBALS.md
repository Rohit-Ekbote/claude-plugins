# Retiring the global engagement commands

`fde-tools` supersedes the global engagement slash commands in `~/.claude/commands/`. Those files live **outside this repository**, so this plugin does not (and cannot) delete them automatically. After installing `fde-tools` and verifying the commands work, remove the old globals manually:

```bash
rm ~/.claude/commands/build-fde-guide.md
rm ~/.claude/commands/summarize-engagement.md
rm ~/.claude/commands/update-engagement-progress.md
rm ~/.claude/commands/correct-engagement-data.md
rm ~/.claude/commands/_engagement-context.md   # internal shared include, not a user command
rm -rf ~/.claude/commands/assets   # only if no other global command uses it
```

Mapping from old to new:

| Old global command | New fde-tools command |
|--------------------|-----------------------|
| `/build-fde-guide` | `/build-guide` |
| `/summarize-engagement` | `/summarize-engagement` |
| `/update-engagement-progress` | `/update-progress` |
| `/correct-engagement-data` | folded into `/qna` (correction intent) |
| _(none)_ | `/update-requirements` (new) |

Verify `fde-tools` is installed and its commands appear before deleting the globals, so you are never left without the workflow.
