# Issue tracker: GitHub

Issues and implementation slices for this repo live in GitHub Issues for `justinf0rfun/onpaper`. Use the `gh` CLI for issue operations from this repository.

## Conventions

- **Create an issue**: `gh issue create --title "..." --body-file <file>` or a quoted heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --comments`, fetching labels and comments when relevant.
- **List issues**: `gh issue list --state open --json number,title,body,labels,comments`.
- **Comment on an issue**: `gh issue comment <number> --body "..."`
- **Apply or remove labels**: `gh issue edit <number> --add-label "..."` / `--remove-label "..."`
- **Close**: `gh issue close <number> --comment "..."`

Infer the repo from `git remote -v`; `gh` does this automatically when run inside this clone.

## Pull requests as a triage surface

PRs as a request surface: no.

This repo currently treats GitHub Issues as the request and implementation queue. External PRs should not be pulled into the Matt Pocock triage state machine unless this file is updated.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `justinf0rfun/onpaper`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --comments`.

