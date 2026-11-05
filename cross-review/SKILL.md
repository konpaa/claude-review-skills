---
name: cross-review
description: This skill should be used when the user asks to "review this branch", "review the PR", "cross-review", "review again", "round 2", review another developer's committed branch, find blockers after the author's fixes, or review a Bitbucket backend PR by the Backend Cross Review Process. Do not use for answering comments on the user's own PR.
argument-hint: "[full|since <sha>|base <branch>|round <n>|pr <file>|<KEY>] + pasted PR description"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/collect-context.sh *) Bash(git *) Read Grep Glob
---

# Backend cross-review

Review someone else's backend branch by the cross-review process ([references/process.md](references/process.md)).
The author is not the current user. The result is comments for Bitbucket, not code changes.

Flags (full / since / base / round) and the pasted PR description:

$ARGUMENTS

## Output language

Everything meant for Bitbucket (inline comments, the general PR comment, thread replies) is written in the output
language from `~/.claude/review-team.md` (line `Output language:`; read it with Read from the home directory).
No file or no such line — English. Talk to the user in the language they write in. Comment prefixes
(`blocker:` / `question:` / `suggestion:` / `nit:`) are always English.

## The PR description is required

The author fills the PR template from the process. Without it, by the process, the PR may be returned without review.
With it, check the code against: the task, the risks, how to test, the payment scenarios.

Sections: **What changed** / **Why** / **How to test** / **Risks** / **Migrations** (the Russian set
**Что изменено** / **Зачем** / **Как проверить** / **Риски** / **Миграции** is recognised too).

How to pass it (first source that works):

1. **Clipboard (fastest):** in Bitbucket select the description → Copy → `/cross-review` in Claude Code. The script reads
   `pbpaste` as UTF-8 and takes the text if at least two lines start with template headings (`## Risks`, `**Why:**`,
   `- Migrations` also count).
2. **Paste into the chat** in the same message, after the command:

```
/cross-review

What changed
...
Why
...
How to test
...
Risks
...
Migrations
...
```

3. **File:** save the text to `.review-pr.md` in the repository root (don't commit it), or `/cross-review pr /path/to.md`.

Priority: text in the chat (`$ARGUMENTS` above or a long paste in a separate block) if it looks like the template →
`pr <file>` → `.review-pr.md` → clipboard → the copy saved by a previous run on the same branch. No description —
say in the verdict that the PR may be returned; still review the code if the user is on the branch.

What to do with the script's lines in the PR description section:

- `clipboard: ... skipped` — tell the user in one line why the clipboard didn't qualify (how many headings were found).
- `WARNING: the description has no key` — confirm this is the right PR's description. The clipboard may still hold the
  user's own description after `/pr-template`, or a previous PR's.

## Step 0. Git context

The script output is substituted below when the skill loads. Don't rerun it without flags:

```!
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh"
```

Read [references/process.md](references/process.md) (the whole process), [references/checklist.md](references/checklist.md),
[references/pr-description.md](references/pr-description.md).

Rerun `"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" <flags>` only if:

- `$ARGUMENTS` contains flags (`full`, `since <sha>`, `base <branch>`, `round 2`, `pr <file>`, `ABC-123`);
- there is no output above or the script failed. Then determine the base (`origin/develop` / `origin/master` /
  `origin/main`) and retry with `base <branch>`;
- the output has `WARNING: last fetch …` — run `git fetch origin` first, then rerun: otherwise you review yesterday's
  version of the author's branch.

Base branch: the script takes it from the branch-name suffix (`*-release` → `origin/release`, `*-develop` →
`origin/develop`), otherwise `origin/develop` → `origin/master` → `origin/main`; `origin/<name>` wins over a local branch.
Compare the `base` line with the PR target in Bitbucket and `review diff lines` with the PR size there; on a mismatch —
`base <branch>`.

Never pass the PR description text in argv — it breaks the shell.

## Source of changes

- Review **only committed** changes: `git diff --find-renames <merge-base>...<HEAD>`.
- Uncommitted / staged changes are **not part of the PR**. Mention a dirty tree in one line and ignore its content
  unless the user asks otherwise.
- Skip `composer.lock`, lock files, generated files, `vendor`, `node_modules`, IDE helpers.
- Don't comment on style, PSR-12, pint, phpstan, phpmd.

## Review rounds

Determine the mode from the script output (`mode`) and the chat history.

### Round 1 (`mode=full`)

Review the whole committed diff against the merge-base. This is the branch's first review.

### Round 2+ (`mode=incremental`, or the user says "fixed", "new commits", "review again")

1. Take **the new commits** (`review range` / `since <sha>`). If the output has `WARNING: the base was merged into the
   branch after the previous round` — review only the author's commits with the `git log -p … --not <base>` command
   from the output, not the whole `review range`: it contains the base branch's commits.
2. For every earlier `blocker:` and open `question:` check the current code: `resolved` / `still open` / `author argued`.
3. New comments — only on the new diff and on regressions caused by the fixes.
4. Don't repeat closed or agreed items.
5. Don't raise a `nit:` / `suggestion:` again if the author explicitly declined it with a reason.

If `mode=no_new_commits` — don't reread the whole PR. Only report the status of open items from this chat or from the
list the user pasted.

If this is a new chat and the script still says `incremental` — the previous comments are not available. Ask the user
to paste them. Until then review only the new range and note that the verification of earlier blockers is incomplete.

After finishing a round, save the point:

```bash
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" save
```

Force a full round: `/cross-review full`.

## Review order

1. Classify the risk by section 4 of the process: Low / Medium / High. High — payments, refunds, invoices,
   authentication, bulk operations, changes to an API **used by other services** (our API for a mobile app or a
   neighbouring service), schema changes of large tables, bulk background processes.
2. Check the code against the PR description: the task from "Why", the risks from "Risks", the scenarios from "How to
   test". Description MISSING — say in the verdict that the PR may be returned without review. Description
   requirements for High:
   - any High — edge cases and failure scenarios (§7.1). Missing — an item in the general comment
     (`question:` — what happens on a retry, a failure, an old client, etc.);
   - payments/refunds — duplicate, error and timeout are mandatory (§4.3). Missing — `blocker:` in the general comment.
3. Read the committed diff. If the patch is not inlined, run the `git diff` from the script's Patch section.
4. For questionable logic read the surrounding code (service, job, policy, request, migration), not just the hunk.
5. Go through the checklist strictly in order: logic → database → security → code complexity.
6. High + payments/refunds: state explicitly what happens on a duplicate, a timeout, partial execution. If the PR
   doesn't cover it — `blocker:` or `question:` depending on the actual hole.

## Result — ready-to-paste comments for the author

The main result is text the user **copies and pastes into Bitbucket as is**: one inline comment per finding plus one
general PR comment. The audience is the author of the code, not the user. A reviewer's report, a retelling of findings
and reasoning are not part of the result.

If findings are already in the chat (for example after `/code-review` or a previous answer), don't review again:
convert them into this format, rechecking only the anchor (line) and the prefix.

### Prefixes (from the process template)

| Prefix | Meaning |
| --- | --- |
| `blocker:` | merge is impossible without a fix (money, data, access, contract, production) |
| `question:` | a question for understanding |
| `suggestion:` | a proposal; does not block merge |
| `nit:` | a trifle |

Model them on the examples in section 9 of [references/process.md](references/process.md):

```text
blocker: A repeated webhook from the provider creates a second payment: nothing
checks `external_id`. The customer is charged twice.

question: Why `lockForUpdate()` outside a transaction? The lock is released
right after the query and protects nothing.

suggestion: This query could become a model scope — it is repeated
in three places.
```

### How to write a comment

1. **One comment — one problem**, anchored to the line where it has to be fixed.
2. **The text starts with the prefix.** Then: what is wrong here (one sentence, in domain terms) → what breaks (a
   concrete scenario: which data/state → which result) → if needed, one sentence on what to do. 2–4 short lines in total.
3. A `question:` is a real question with a "?" and why it matters (what happens if the answer is "no").
4. **No path or line number inside the text** — Bitbucket shows them. Refer to other places by a short class/method
   name in backticks.
5. **Anchor only on a line in the PR diff.** Bitbucket allows inline comments only on changed lines. If the root cause is
   in a file the PR doesn't touch — anchor on the nearest changed line that triggers it; if there is none — put the
   item into the general comment.
6. Neutral, impersonal tone ("This…", "If…"): no "you must", no filler praise, no "I found", no review jargon
   (finding, severity, failure scenario).
7. No code longer than one line — a comment is not a patch.
8. A bug that existed before the PR — at most `suggestion:` marked "pre-existing", never `blocker:`.
9. Don't propose rewriting working code "nicer" when there is no bug or hole. Don't edit the author's files.
10. Wrap lines at 80–100 characters, as in the examples.

### Chat output format

Comment order: `blocker:` → `question:` → `suggestion:` → `nit:`. Each text in its own block fenced with **four**
backticks and the `text` language, so it copies with one click and doesn't break on backticks inside. Above the block —
the number and the anchor; inside — only the comment text.

`````markdown
**Verdict** (for you, not for pasting): risk High · round 1, full · `<base>...HEAD` · ~N lines without lock files
· changes needed: 2 blocker, 3 question

### Inline comments

**1. `path/to/File.php:123`**
````text
blocker: This … .
If …, then … .
````

**2. `path/to/Other.php:40`**
````text
question: Why …? If …, then … .
````

### General PR comment
````text
Summary: changes needed — 2 blockers, the rest are questions and suggestions.
<items without a line in the diff, if any>
````
`````

- The verdict — one or two lines above the comments: risk, round/mode, range, size, readiness
  (approve | changes needed | return because of the description). Approve only when no blocker is open.
- Round 2+: before the comments, the status of earlier items (`[resolved]` / `[open]` / `[agreed]`) for the user; new
  comments in the same block format. For an `[open]` blocker — a ready thread reply in the same format
  (`blocker: still …`).
- The general comment holds the summary for the author and items without an anchor. Don't repeat inline items there.
- No comments — the general comment is an approve plus 2–4 sentences on what can be learned from this PR (knowledge sharing).
- Nothing after the blocks: no prose retelling of the "main" findings.

## Never

- Review uncommitted changes as part of the PR.
- Write a patch into the repository unless the user says "fix it yourself".
- Mark taste, naming or "I would do it differently" as `blocker:`.
- Ignore round 2 and comment on the whole PR again.
- Deliver a reviewer's report instead of ready-to-paste comments for the author.
