# How to pass the PR description

Required. This is not a reviewer comment but the **Description** in Bitbucket that the author fills from the process template.

## What to copy

The whole Description block of the PR, as it appears in Bitbucket:

```
What changed
…

Why
link to the task + one sentence

How to test
steps or curl

Risks
DB / payments / refunds / auth / integrations / queues / cache
or "none"

Migrations
yes / no
```

The Russian headings (`Что изменено`, `Зачем`, `Как проверить`, `Риски`, `Миграции`) are recognised as well.

For a High-risk payments/refunds PR the description must cover duplicate, error and timeout.

## How to pass it

1. Bitbucket → select the Description → Copy → `/cross-review` (clipboard).
2. Paste the same text into the chat right under `/cross-review`.
3. Save it to `.review-pr.md` in the repository root (don't commit it).

If `.review-pr.md` exists, the clipboard is not read. Delete the old file after the review.

If the clipboard didn't qualify, the script prints `clipboard: … template headings N/5`. At least 2 lines must start
with a heading (`What changed`, `Why`, `How to test`, `Risks`, `Migrations` or their Russian equivalents; `##`, `**`,
`:` and list markers are allowed).

Don't copy Files changed or the whole diff — only the description.
