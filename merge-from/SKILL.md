---
name: merge-from
description: This skill should be used when the user asks to "merge master into my branch", "merge master into current", "pull develop into this branch", "update my branch from master", "merge ABC-745 in", "bring in changes from the task branch", or to fetch/update a specified branch (by name or by task key) and merge it into the current feature branch with conflict resolution that keeps both sides' functionality. Use before a later PR into master/develop, and to pull another feature branch into the current one. Do not use to merge a feature into master or to review a PR.
argument-hint: "[master|main|develop|<branch>|<task key>]"
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/scripts/prepare-merge.sh *) Bash(git *) Bash(composer *) Bash(npm *) Read Grep Glob Edit
---

# Merge a given branch into the current one

Merge fresh **master / develop / a given branch** into **the current feature branch**, so that the later PR into master
is based on current production code. First fetch and update the source, then merge. Resolve conflicts without wiping
out either the task or production.

Source argument: `$ARGUMENTS` (default `master`). Examples: `master`, `develop`, `main`, `origin/master`, `bugfix/ABC-745`.

A task key alone works too — `ABC-745`: the script finds the branch `bugfix/ABC-745` among local and `origin/*` branches
and says which one it picked. If several branches match the key, it lists them and stops — then ask the user which one
to merge; never guess.

## Step 0. Context

The working tree must be clean. The current branch is a task branch, not master/develop.

Run the script with **one** argument — the source branch name or task key taken from `$ARGUMENTS` (no argument →
`master`), quoted:

```bash
"${CLAUDE_SKILL_DIR}/scripts/prepare-merge.sh" "<source>"
```

Never pass anything else in argv (a task description, a sentence): the shell would execute backticks and `$(...)` in it.

Read [references/conflicts.md](references/conflicts.md).

Stop on a script ERROR: dirty tree, protected current branch, nothing to merge. Don't work around it with stash unless
the user asks.

`Merge already in progress` — don't run `git merge` again. Finish resolving the current one.

`Already up to date` — say so and stop.

## Step 1. Merge

Take the source from the script output (`source (theirs)`), not from a stale local master without a fetch.

```bash
git merge --no-edit <source>
```

- Fast-forward if possible (the branch is only behind).
- No `rebase`. No `--ours` / `--theirs` for the whole merge.
- No `push`. No `reset --hard`. No `checkout` of a protected branch.

## Step 2. Conflicts

While `git diff --name-only --diff-filter=U` is not empty:

The script prints `Files changed on BOTH sides since merge-base` — only these files can lose the current branch's work.
Go through each of them, even if git merged it without markers: someone else's change may have landed next to removed code.

1. Open the file and read both sides.
2. ours = the current task's functionality. theirs = what is being merged: from master/develop it's production and the
   base; from another feature branch it's someone else's task, just as alive.
3. Combine both behaviours. Keep the fix from master, keep the task logic.

   A special case: the current branch moved code into a new layer while the source changed it in the old place. Git
   reports "deleted by us / modified by them", or brings the old file back with no conflict at all. Port the change into
   the new layer by hand; don't resurrect the old file. After the merge check that no old classes came back:
   `git diff --stat ORIG_HEAD` and a search for duplicate class names.
4. Remove the markers. `git add`.

Never hand-merge lock files: first the json, then `composer update --lock` / `composer install` or the npm equivalent.

Keep migrations from both sides.

An unclear conflict (binary, unclear what would break production) — stop, show the file, ask. Never resolve payments
or permissions "in favour of one side" by guessing.

## Step 3. Finish the merge

```bash
rg '<<<<<<<|=======|>>>>>>>' --glob '!vendor/**' --glob '!node_modules/**'
git diff --name-only --diff-filter=U
git status
```

No markers and no unmerged files → complete the merge (`git commit` if the merge stopped before committing). A plain
message: merge the source into the current branch.

If `vendor/bin/pint` exists — run it on the changed PHP files. Don't "fix" phpstan/phpmd by style; fix only what the
merge broke.

## Report

```markdown
## Merge
- merged: origin/master @ sha
- into: feature/… @ sha (before → after)
- conflicts: file — what was kept from the task / from the source
- overlaps without conflicts: what was checked by hand
- lock files / migrations: how they were rebuilt
- push: no, do it yourself
```

## Never

- Merge a feature into master with this skill.
- Rebase the current branch onto master.
- `--ours` / `--theirs` on a whole conflicted application file.
- Push, force, hard reset.
- Drop migrations, tests, fixes or endpoints of either side.
