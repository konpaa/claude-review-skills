---
name: review-reply
description: This skill should be used when the user asks to "reply to the review", "address the comments", "close the review comments", "self-review", "check my changes", address blocker/question/suggestion/nit comments on their own PR, or review their own committed branch before sending it to a reviewer, by the Backend Cross Review Process. Do not use when reviewing someone else's branch, and not for the PR description (that is pr-template).
argument-hint: "[base <branch>|since <sha>|<KEY>] + pasted reviewer comments"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/collect-context.sh *) Bash(git *) Read Grep Glob Edit
---

# Your own changes and review replies

Two modes on your own branch: self-review of the committed changes before the reviewer sees them, and replying to the
reviewer's comments (`blocker:` / `question:` / `suggestion:` / `nit:`). The PR description is written by
`/pr-template`, not by this skill.

Flags and pasted reviewer comments:

$ARGUMENTS

## Step 0. Git context

The script output is substituted below when the skill loads:

```!
"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" author
```

Read [references/process.md](references/process.md) (the whole process) and [references/checklist.md](references/checklist.md).

Rerun `"${CLAUDE_SKILL_DIR}/scripts/collect-context.sh" author <flags>` only if the message has flags
(`base <branch>`, `since <sha>`, `full`, a task key like `ABC-123`) or there is no output above.
**Only flags go into argv.** Never put the reviewer's comment text on the command line: it may contain backticks and
`$(...)`, which the shell would execute, and every line would become a separate command.

Asked for a PR description — say in one line that this is `/pr-template`, and don't write it here.

Don't "improve" style by hand (PSR-12, pint, phpstan, phpmd) while answering a review unless the reviewer asked for it.
CI must be green before merge.

## Output language

Thread replies and any text for Bitbucket are written in the output language from `~/.claude/review-team.md`
(line `Output language:`; read with Read from the home directory), English by default. Talk to the user in the
language they write in.

## Scope

| What | Self-review before the PR | Replying to comments |
| --- | --- | --- |
| Committed diff vs merge-base | yes, the main subject | yes, plus fixes for the comments |
| Uncommitted | separately: commit it or keep it out of the PR | may be edited; the user commits |
| Other code outside the diff | no | only to close a comment |

Don't inflate the task. No self-merge except for the cases in section 10 of the process.

## Choosing the mode

- Reviewer comments are pasted, or "address the comments", "reply to the review", "round 2" → **reply**.
- Otherwise → **self-review** of your branch.

## Mode: replying to a review

1. Parse every comment: anchor (file/line), prefix, gist.
2. Pick one action per comment: `fix` | `argue` | `answer`.
   - `blocker:` — fix it, or give a solid argument why there is no hole (with a reference to the code). Never ignore it silently.
   - `question:` — a short answer about the invariant; touch the code only if the answer calls for a change.
   - `suggestion:` — accept, or decline with a reason.
   - `nit:` — optional, doesn't block.
3. Change code only for `fix`. Keep the change minimal.
4. After the fixes, verify that the comment's scenario and its edge cases are covered.
5. Give the replies **ready to paste into the Bitbucket thread** (format below).

### How to write a reply

The reply goes into the thread under the reviewer's comment, so:

- don't repeat the comment's prefix or quote it — they are already in the thread;
- `fix`: "Fixed: what exactly, in domain terms. How it was verified (test, scenario)";
- `argue`: why there is no hole — the invariant, the place in the code (class/method), the test. Not "by design"
  without a reason;
- `answer` (to a `question:`): a direct answer about the decision and its reason — by the process, this is how the
  decision gets documented for everyone;
- `suggestion:` / `nit:`: "Accepted, …" or "Not doing it: reason";
- 1–3 short lines, neutral tone; no path or line number — Bitbucket shows them.

### Chat output format

Above each block — the number, the comment's prefix, the anchor and the first words of the comment (to find the
thread). Inside the block — only the reply text. The block is fenced with **four** backticks and the `text` language:
it copies with one click and doesn't break on backticks inside.

`````markdown
**Status** (for you, not for pasting): 3 fix, 1 argue, 1 answer · changed `InvoiceService.php`, `RefundTest.php` · not committed

### Thread replies

**1. blocker · `app/Services/InvoiceService.php:42`** — "Nothing checks that the refund…"
````text
Fixed: refunds are now looked up by `invoice_id` before calling the gateway; a repeated
request returns the existing refund. Added a test for the double call.
````

**2. question · `app/Jobs/RefundJob.php:15`** — "Why a synchronous call rather than a job?"
````text
Synchronous because … On a gateway timeout …
````
`````

Same order as the reviewer's comments. Don't commit until the user asks.

If the reviewer sent new commits of the author for checking — that's reviewing someone else's work: use
`/cross-review`, not this skill.

## Mode: self-review of your changes

Look at the **committed** changes (the script's `review range`). Dirty tree — warn that it won't be in the PR.

Go through the process checklist (logic → database → security → code) and [references/checklist.md](references/checklist.md).
Find the holes the way a reviewer would. Don't write about style.

Assess:

- risk Low / Medium / High by section 4 of the process;
- size without lock/generated files (thresholds 300 / 500; 500+ — the description must explain why it can't be split);
- for **any** High — are edge cases and failure scenarios described (§7.1); for payments/refunds duplicate, error,
  timeout and partial execution are mandatory (§4.3).

Found a blocker in your own code — **fix it**, don't leave it to the reviewer. A suggestion — ask, or fix right away if cheap.

Format:

```markdown
## Self-review
- Risk: …
- Size: N lines
- Ready to send: yes / no (what to close)

## Fixed before the reviewer
- file: what the hole was

## What to add to "Risks" in the PR description
edge cases and failure scenarios for High (if missing); the full description — `/pr-template`
```

If a question to the reviewer about a debatable spot is needed — give it as a ready-to-paste ````text block with the
`question:` prefix.

## Self-merge (section 10 of the process)

Only for a production incident / hotfix / critical bug fix / no reviewer available for an urgent change. Then give a
ready PR comment as a ````text block, modelled on the process:

```text
Self-merged: <reason>, <project>.
Risk area: <what may break>.
Post-review required.
```

and remind: a post-review task, post-review within the next working day.

## Never

- Answer "we'll fix it later" to an open `blocker:`.
- Change behaviour beyond the comment and the task.
- Review someone else's branch with this skill.
- Pass the reviewer's comment text as script arguments.
- Write the PR description instead of `/pr-template`.
- Self-merge without a reason from section 10 and without the comment: reason, risk area, post-review required.
