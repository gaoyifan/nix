---
name: codex
description: Delegate a programming task, bug fix, refactor, or code review in a project checkout to the installed Codex CLI and inspect its result.
---

# Codex CLI Delegation

Use the installed `codex` CLI for substantial programming work. Run it in the
intended project checkout, with a prompt that states the requested result,
relevant constraints, and checks to run. Its credentials and provider settings
are separate from Rakazo's chat-model connection.

Launch long coding work as an independent background command rather than holding
the Rakazo shell open. For example, from the Bot workspace, replacing the project
path with the actual checkout:

```bash
mkdir -p exports
nohup codex exec --sandbox workspace-write --cd /absolute/path/to/project --output-last-message "$PWD/exports/codex-result.md" 'Implement the requested change and run the relevant project checks.' < /dev/null > exports/codex.log 2>&1 &
```

Use a task-specific prompt and distinct log/result names for separate tasks.
Read the log and result file in later `shell` calls. While the delegate is
running, avoid editing the same files. Once it exits, inspect its final message,
the actual diff, and the reported check results before summarizing the outcome.
Use `codex exec review --help` for a review-only task's current CLI options.

Use authorization already configured for the CLI. If it reports missing or
expired authentication, tell the user that Codex authorization still needs to be
configured; do not copy Rakazo chat tokens or begin a login flow just to complete
this delegation. Preserve any provider or model explicitly selected by the user.

Put requested reports or exports under the Bot workspace's `exports/` and deliver
them with `attach_file` using a relative path.
