# Backend review skills for Claude Code

[Claude Code](https://claude.com/claude-code) skills for cross-reviewing backend code in Bitbucket: writing the PR
description, self-review, answering review comments, reviewing someone else's branch, and merging the base branch
into a task branch. The review process they follow is described in
[cross-review/references/process.md](cross-review/references/process.md).

Goal: get your own branch ready for review faster, and review other people's PRs against one checklist — logic,
database, security. The skills never comment on code style (pint / phpstan / phpmd / PSR-12); that is CI's job.

Requirements and assumptions:

- macOS (bash 3.2, `pbcopy` / `pbpaste`), git, Claude Code.
- Git branches carry a task key in their name (`feature/ABC-123-…`).
- Written for PHP/Laravel backends (migrations, N+1, mass assignment, `composer.lock`), but the review logic is general.
- **Language:** the skills are written in English and produce English text for Bitbucket (PR descriptions, review
  comments, thread replies) by default. Set another output language in the [team settings](#team-settings); comment
  prefixes (`blocker:`, `question:`, `suggestion:`, `nit:`) always stay English.

## Commands

| Command | Whose branch | What it does |
| --- | --- | --- |
| `/pr-template` | yours | Writes the Bitbucket PR description from the process template |
| `/review-reply` | yours | Self-review before sending the PR, **or** fixes and replies to reviewer comments |
| `/merge-from` | yours | Merges master/develop (or another branch) into the current branch without losing either side's logic |
| `/cross-review` | someone else's | Reviews the committed changes of a PR, round 1 and follow-up rounds |

Don't mix roles: someone else's PR — only `/cross-review`; your own code — `/pr-template`, `/review-reply`, `/merge-from`.

## Installation

You need the **whole folder** (a git clone, or an archive that keeps symlinks): `pr-template` and `review-reply` use
the scripts and `process.md` from `cross-review` through relative symlinks, so a single skill folder does not work
on its own.

```bash
git clone <repo-url> ~/claude-review-skills
```

```bash
~/claude-review-skills/install.sh
```

`install.sh` checks that the internal symlinks are intact and links each skill into `~/.claude/skills/`. Don't move
the folder after installing (if you do, run `install.sh` again). To update: `git pull` in the folder.

Open Claude Code **in the root of the project repository**, on the branch you need. If the session was started before
installation, restart Claude Code, then type `/` and pick the command.

### Team settings

The output language, the issue tracker URL, the team's projects and reviewers are team data and are not stored in this
repository. They live in `~/.claude/review-team.md`; the template is [team.example.md](team.example.md):

```bash
cp ~/claude-review-skills/team.example.md ~/.claude/review-team.md
```

| Setting | Used by | Without it |
| --- | --- | --- |
| `Output language:` | all skills — text written for Bitbucket | English |
| Issue tracker URL | `/pr-template` — the task link in "Why" | the bare task key |
| Projects, reviewers, who is who | `/pr-template` — reviewer suggestion | no suggestion |

---

## Typical workflow

### As the author

1. Commit the task on your branch (`feature/ABC-123-…`). Uncommitted changes never get into the PR or the description.
2. If master/develop has moved ahead — `/merge-from master` (or `develop`) on your branch before opening the PR.
3. `/review-reply` — find and fix the holes before the reviewer does.
4. `/pr-template` — paste the generated text into the Bitbucket PR description. Below it: who to assign as reviewer.
5. Open the PR, assign the reviewer, wait for CI.
6. When comments arrive: paste them into the chat after `/review-reply` → code fixes plus ready-to-paste thread replies.
7. Commit and push. The reviewer runs `/cross-review` for round 2.

### As the reviewer

1. Check out the author's branch (the PR branch).
2. In Bitbucket, select and copy the PR description.
3. Run `/cross-review` — the skill reads the clipboard if it contains the PR template.
4. Paste the generated comments into the PR: each block goes inline on the `path:line` shown above it, plus one general comment.
5. When the author pushes fixes → pull → `/cross-review` again (it detects round 2 when HEAD has moved).

---

## Git rules shared by all skills

- Reviews and descriptions are built from the **committed** diff only.
- Base branch: taken from the branch-name suffix (`ABC-123-release` → `origin/release`, `*-update-develop` →
  `origin/develop`), otherwise `origin/develop` → `origin/master` → `origin/main`. Override with `base master`; the
  remote branch `origin/master` wins over a local `master`, which is used only when no remote one exists.
- `origin/*` refs are only as fresh as your last `git fetch origin`; the script warns when the last fetch is older than 12 hours.
- The task key comes from the branch name (`ABC-123`, `XYZ-45`). The review covers the contiguous block of commits for
  that task, never wider than the branch relative to its base (a base branch merged into the task branch is not reviewed).
  The whole branch tail: flag `full`.
- Lock files, generated files, `vendor`, `node_modules` and IDE helpers are excluded from size and review.
- The previous review round is remembered in `~/.claude/review-state/`, separately for each branch (nothing is written
  into the project).

PR size thresholds (without lock files): up to 300 lines — fine; 300–500 — acceptable; 500+ — the description must
explain why the PR can't be split.

---

## `/merge-from` — merge master/develop into the current branch

When: production (usually `master`) has moved ahead and your task isn't merged yet. Merge fresh master **into your
feature branch** so that the later PR into master is based on current code. This skill never merges a feature into master.

Stay on your branch with everything committed.

```
/merge-from
/merge-from master
/merge-from develop
/merge-from main
/merge-from ABC-745
```

A task key alone (`ABC-745`) is resolved to the matching branch (`bugfix/ABC-745`); if several branches match, the
skill lists them and asks.

The skill:

1. Runs `git fetch origin` and fast-forwards the local source branch when possible.
2. Runs `git merge` of the source into the current branch (never rebase).
3. Resolves conflicts keeping the task logic **and** the fixes/contracts from the source. Never `--ours` / `--theirs`
   on a whole application file.
4. Keeps migrations and tests from both sides. `composer.lock` / npm lock files are regenerated, not hand-merged.
5. Creates the merge commit. **Does not push** — review the diff and push yourself.

Don't run it while on `master`/`develop`. Dirty working tree — commit first.

---

## `/pr-template` — describe your own branch

When: the branch is ready for review and the PR description needs filling in.

```
/pr-template
/pr-template base develop
/pr-template ABC-123
```

The skill:

- reads the task's commits; if the base branch has been merged into the task branch (`*-update-develop`, `*-release`),
  the base changes are left out of the diff;
- fills in the five template sections;
- below the block: risk level, size, and who to assign as reviewer (from `~/.claude/review-team.md`, excluding the author);
- prints the full text in the chat — copy it from there;
- also puts the text on the clipboard as UTF-8 and verifies it byte by byte (`scripts/copy-utf8.sh`);
- keeps a copy in `~/.claude/review-state/pr-description.md` in case pasting fails.

The template — paste into Bitbucket → Description. Keep the headings as they are: `/cross-review` detects the
template by them (it also recognises the Russian set used when the output language is Russian).

```markdown
## What changed
## Why
## How to test
## Risks
## Migrations
```

| Heading | Content |
| --- | --- |
| `What changed` | Grouped summary of the change, "before → after" |
| `Why` | Link to the task (tracker URL from `review-team.md`) + one sentence of business context |
| `How to test` | Concrete steps or curl requests, each with the expected result |
| `Risks` | Affected areas: DB / payments / refunds / auth / integrations / queues / cache, or "none". Any High-risk PR: edge cases and failure scenarios; payments/refunds: duplicate, error, timeout, partial execution are mandatory |
| `Migrations` | yes (with file names) / no |

The risk level, the "500+ lines" note and the reviewers are written **below** the block — don't copy them into the
description, except for the size explanation when it's needed.

Check that no other task from the same branch train slipped into the description. If the key in the branch name is
different, pass it explicitly: `/pr-template ABC-123`.

---

## `/review-reply` — your own changes and review replies

### Self-review before the PR

On your branch, with no reviewer comments:

```
/review-reply
```

Looks for what a reviewer would mark `blocker:` (idempotency, authorization, mass assignment, migrations, N+1,
transactions) and fixes it in the code. At the end it tells you what to add to the "Risks" section; the description
itself is written by `/pr-template`.

### Replying to review comments

Copy the comments from Bitbucket and paste them into the same message:

```
/review-reply

blocker: Nothing checks that the refund for this invoice hasn't already been made.

question: Why a synchronous call rather than a job?
```

For each item: `fix` (change the code) or `argue` (explain with reference to the code). A `blocker:` can never be
silently skipped. A `question:` gets a short answer about the invariant. `suggestion:` / `nit:` — accept, or decline
with a reason.

Output: one block per comment. Above the block — the prefix, `path:line` and the first words of the comment (to find
the thread); inside — only the reply text, copied with one click and pasted into the thread. The skill does not commit
until you ask.

The pasted comment text is never passed to shell arguments (it may contain backticks and `$(...)`), so paste it as is.

Hotfix / incident / no reviewer available: self-merge only with a PR comment (reason + risk area + "Post-review
required") and a post-review task — the skill gives you that comment as a ready block.

---

## `/cross-review` — someone else's branch

When: you have checked out the author's branch and are reviewing the PR.

The PR description is **required**: by the process, a PR without it can be returned without review. Ways to pass it:

1. Bitbucket → select the description → Copy → `/cross-review` (read from the clipboard when the template headings are found).
2. Paste the description into the chat under the command.
3. Save it to `.review-pr.md` in the repository root (don't commit it), or `/cross-review pr /path/to.md`.

The clipboard is read as UTF-8 (without an explicit locale `pbpaste` returns non-ASCII text as `?`). If the description was
not picked up, the output contains a `clipboard: ...` line with the reason. The description is saved per branch.

```
/cross-review
/cross-review full
/cross-review since abc1234
/cross-review base develop
/cross-review round 2
/cross-review ABC-123
```

Output: comments for the author, ready to paste — one block per inline comment (the `path:line` anchor above the block,
inside only the prefixed comment text) plus one general PR comment. The skill never changes the author's code. Findings
already in the chat (for example from `/code-review`) are converted into this format without reviewing again.

Comment prefixes:

| Prefix | Meaning |
| --- | --- |
| `blocker:` | merge is impossible without a fix (money, data, access, contract, production) |
| `question:` | a question for understanding; shares knowledge |
| `suggestion:` | a proposal; does not block merge |
| `nit:` | a trifle |

Taste and style are never a `blocker:`. Approve only when no `blocker:` is open.

Checklist order: logic → database → security → code complexity.

### Round 1 and round 2

The first run on a branch reviews the whole task diff. After the review the skill saves HEAD (per branch). The author
pushes fixes → `/cross-review` again: it reviews **only the new commits** and reports the status of earlier `blocker:` /
`question:` items. Closed items are not raised again. If the author merged the base branch in between rounds, the
script warns and prints a command that shows only the author's own commits.

New chat without the previous comments: paste the earlier comments into the message, or pass `since <sha>`. Force a
full review: `/cross-review full`.

Uncommitted changes on the reviewer's machine are not part of the PR — the skill only warns about them.

---

## Troubleshooting

| Symptom | What to do |
| --- | --- |
| The `/` command is not found | Restart Claude Code in the repository root |
| The diff is tens of thousands of lines | Compare the `base` line with the PR target in Bitbucket; if wrong — `base <branch>` |
| Wrong base branch | `/cross-review base master` or `/pr-template base master` |
| `WARNING: last fetch is older than 12 h` | `git fetch origin`, then run the command again |
| The PR description was not picked up | Paste the description into the chat as text, not only via Copy |
| Round 2 re-reads the whole PR | Different repository path means a different state file; pass `since <sha>` |
| Skill fails: `scripts/collect-context.sh` is missing | A single skill folder was copied, or symlinks were lost — install the whole folder with `install.sh` |
| Commits of another task in the description | The branch has no task key, or the key doesn't match the commit messages |
| merge-from: dirty tree | Commit or stash, then `/merge-from` again |
| merge-from: protected branch | Check out the feature branch; don't stay on master/develop |
| merge-from: already up to date | The current branch already contains the source; nothing to merge |

---

## What the skills don't do

- They don't push and don't press Merge in Bitbucket. (`/merge-from` merges the base into your feature branch locally.)
- They don't fetch task details from Jira (the key comes from the branch name and the "Why" section).
- They don't replace CI and don't argue about style.
- They don't review uncommitted changes as part of a PR.

---

## Repository layout (for contributors and AI agents)

```
cross-review/
  SKILL.md                     /cross-review instructions
  references/process.md        the review process (the only copy)
  references/checklist.md      reviewer checklist
  references/pr-description.md how the reviewer passes the PR description
  scripts/collect-context.sh   git context for all three review skills (the only copy)
  scripts/copy-utf8.sh         UTF-8-safe clipboard copy (the only copy)
pr-template/
  SKILL.md
  references/process.md   -> ../../cross-review/references/process.md
  scripts/*.sh            -> ../../cross-review/scripts/*.sh
review-reply/
  SKILL.md
  references/checklist.md      author self-review checklist
  references/process.md   -> ../../cross-review/references/process.md
  scripts/collect-context.sh -> ../../cross-review/scripts/collect-context.sh
merge-from/
  SKILL.md, references/conflicts.md, scripts/prepare-merge.sh
install.sh                     links the skills into ~/.claude/skills
team.example.md                template for ~/.claude/review-team.md
```

Rules for changing the skills:

- Edit shared files only in `cross-review/`; the other skills reach them through relative symlinks. Never replace a
  symlink with a copy, and never use absolute symlink targets.
- `process.md` is the source of truth for the process. To adopt your own team process, replace the file but keep the
  section numbering — the skills reference §4.3 (High risk), §7.1 (PR template), section 5 (reviewers),
  section 10 (self-merge).
- Text the skills write for Bitbucket follows `Output language:` from `~/.claude/review-team.md` (default English).
  The PR template heading detection in `collect-context.sh` (`pr_template_hits`) knows English and Russian; adding a
  heading set for another language means extending those regular expressions.
- Scripts must stay bash 3.2 compatible (macOS default). Commands the scripts print must be zsh-safe (quote pathspecs).
- Never pass user-pasted text (PR descriptions, review comments) as shell arguments in `!` blocks — only flags.
- Never commit team data (tracker URL, colleague names, project names) — it belongs in `~/.claude/review-team.md`.
- After changing anything, run `install.sh` in a copy of the folder to verify that symlinks resolve.
