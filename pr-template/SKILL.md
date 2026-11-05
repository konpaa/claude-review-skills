---
name: pr-template
description: This skill should be used when the user asks for a "PR template", "PR description", "prepare the PR", "fill in the template", "what to paste into Bitbucket", or to draft a Pull Request description for their own branch from committed changes by the Backend Cross Review Process. Do not use when reviewing someone else's branch.
argument-hint: "[base <branch>|<KEY>]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/collect-context.sh *) Bash(${CLAUDE_SKILL_DIR}/scripts/copy-utf8.sh *) Bash(git *) Bash(pbcopy *) Bash(pbpaste *) Read Grep Glob
---

# PR description for your own branch

Build the Bitbucket Description by the cross-review process from the **committed** changes of your branch.
Don't review someone else's code. Don't commit.

Flags: `$ARGUMENTS`

## Step 0

The script output is substituted below when the skill loads:

```!
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" draft
```

If `$ARGUMENTS` contains `base <branch>` or a task key — rerun
`"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" draft <flags>`. Only flags go into argv, never text.

Read [references/process.md](references/process.md) — the whole process — and the team settings
`~/.claude/review-team.md` (Read, path from the home directory): output language, issue tracker URL, projects, reviewers.
No file — work without it: don't invent the link or the reviewers (see below); below the block, suggest in one line
copying `team.example.md` from the skills repository to `~/.claude/review-team.md`.

Look only at the script's review range (the task from the branch name, not the whole history down to the base).
Don't put uncommitted changes into the description — warn that they won't be in the PR.

Base branch (the PR target): the script takes it from the branch-name suffix (`ABC-123-release`, `*-update-develop` →
`origin/release`, `origin/develop`), otherwise `origin/develop` → `origin/master` → `origin/main`, and never goes past
the merge-base, even when the base has been merged into the branch. Compare the `base` line with the PR target in
Bitbucket; wrong — rerun with `base <branch>`. A `WARNING: last fetch …` line — run `git fetch origin` first.

Read the diff and the key files (migrations, endpoints, jobs, payments) so that "What changed" and "How to test" are
concrete, not generic.

## Output language

The description is written in the output language from `review-team.md` (line `Output language:`), English by default.
The headings follow the language: English — the template below; Russian — `Что изменено` / `Зачем` / `Как проверить` /
`Риски` / `Миграции`. `/cross-review` recognises both sets; for any other language keep the English headings and write
the body in that language. Talk to the user in the language they write in.

## Template (exactly these 5 headings)

The ready text is one markdown block with no agent comments inside it.

```markdown
## What changed
A short summary. Items reflect the diff, not a retelling of every file.

## Why
Link to the task + one sentence of business context.

## How to test
Concrete steps or curl. Mention the tests if they are in the diff.

## Risks
Mark what is affected: DB / payments / refunds / auth / integrations / queues / cache.
Nothing — write "none".
High risk: edge cases and failure scenarios.
Payments/refunds: what happens on a duplicate, an error, a timeout, partial execution.

## Migrations
yes (file names) / no.
```

## Writing so the reviewer gets it on the first read

The reviewer opens the Description before the code and gives it a minute or two. A flat list of ten dense items won't
get read.

1. **Group, don't list.** "What changed" — 3–5 named blocks (protection, accounting, concurrency, diagnostics…), short
   lines inside each. Not one item per file: the reviewer already sees the file list in Files changed.
2. **Each block is "before → after".** First one sentence on what happened before and why that was bad, then what
   happens now. Without the "before" an item reads as a list of touched places and explains nothing.
3. **Numbers and names from the code.** Thresholds, exit codes, column and option names are concrete — not "added
   checks" or "improved error handling".
4. **In "How to test", every step has an expected result.** A command without expected output can't be verified: the
   reviewer must see what counts as success and what as failure.
5. **Negative scenarios on a par with the positive one.** If behaviour on failure changed, show the step that triggers
   it and how it must end.
6. **Keep lines short.** A five-line paragraph reads worse in Bitbucket than three short lines.

### What the process requires of the sections

- **"Why" is a link, not a bare key** (§7.1): `[ABC-123](<tracker URL>/browse/ABC-123)`. The tracker URL comes from
  `review-team.md` (per project or the default). Not there — from earlier PR descriptions or commit messages of this
  repository. Not found — keep the key and say so below the block; never invent it.
- **Risk level by section 4 of the process.** High also means "changes to an API *used by other services*" (our API
  for a mobile app or a neighbouring service), not only payments.
- **For any High PR** add edge cases and failure scenarios to "Risks" (§7.1): what happens on a retry, on partial
  execution, with an old client on the new API, when an external service fails. For payments/refunds duplicate, error
  and timeout are mandatory (§4.3).

### Below the block (not for the Description)

- Risk level (Low / Medium / High) and size in lines.
- 500+ lines without lock files — one sentence on why the PR can't be split, or that the author needs to add it.
- **Who to assign as reviewer** (section 5 of the process): from `review-team.md` — the project this repository
  belongs to (by the repositories column and the remote), excluding the author (`git config user.name`, mapped in the
  same file). Project unclear — list the matching rows, don't guess. No file — skip this item.

## Chat answer — the main result

Print the ready description **in full** in the final chat answer so it can be copied straight from there. Don't replace
it with a file link, a summary, or "the text is on the clipboard".

- One block, the outer fence is **four** backticks. The description may contain its own triple-backtick blocks (curl,
  commands), which would close a triple outer fence too early:

`````
````markdown
## What changed
…
## How to test
```
curl …
```
…
````
`````

- Inside the block — only the Description text, no agent comments.
- Risk level, PR size, the 500+ note and the reviewers — **below** the block, as short separate text.

## Clipboard — in addition

Also put the same text on the clipboard, **only** with this script:

```bash
"${CLAUDE_SKILL_DIR}/scripts/copy-utf8.sh" --label pr-description <<'PRBODY'
…the ready description…
PRBODY
```

Don't use bare `pbcopy`. When `LANG`/`LC_CTYPE` is not set in the shell — and in non-interactive runs it usually isn't —
`pbcopy` marks the clipboard as MacRoman. A `pbcopy | pbpaste` round trip still looks fine, but pasting non-ASCII text
into Bitbucket gives mojibake. The script sets the locale explicitly, verifies the clipboard byte by byte and keeps a
copy in `~/.claude/review-state/pr-description.md`.

The heredoc delimiter is `PRBODY`, not `EOF`: the delimiter must not match any line of the text.

Pass the text only through the heredoc. Never `copy-utf8.sh < ~/.claude/review-state/pr-description.md`: the script
writes its copy to that same file, truncates it first, gets empty input — and the file is lost.

Below the block in the chat, one line: the text is also on the clipboard (paste into Bitbucket → Description). If the
script reported a mismatch or `pbcopy` is unavailable — say so: copy from the block in the chat. Mention the path of the
backup file only as a fallback.

## Never

- Invent the task, curl, risks or migrations that are not in the diff.
- Write about style, pint, phpstan, phpmd.
- Self-merge.
- Review someone else's branch.
