#!/usr/bin/env bash
# bash 3.2 compatible (macOS). Fetch/update source branch, print merge context. Does not merge.
set -euo pipefail

usage() {
  echo "usage: prepare-merge.sh [master|main|develop|origin/<branch>|<task key>]"
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "not a git repository. Run it from the project root, on a feature branch."
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if ! git rev-parse --verify --quiet HEAD >/dev/null; then
  die "the repository has no commits (no HEAD)."
fi

CURRENT="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
SHORT_HEAD="$(git rev-parse --short HEAD)"
SRC_ARG="${1:-master}"

if [ "$CURRENT" = "HEAD" ]; then
  die "detached HEAD. Check out the feature branch, then retry."
fi

is_protected() {
  case "$1" in
    master|main|develop|production|prod|staging|release) return 0 ;;
    *) return 1 ;;
  esac
}

if is_protected "$CURRENT"; then
  die "the current branch $CURRENT is protected. Check out the feature branch. This skill merges master/develop INTO the task, not the other way round."
fi

DIRTY="$(git status --porcelain)"
if [ -n "$DIRTY" ]; then
  echo "ERROR: working tree dirty. Commit or stash first, otherwise the merge overwrites uncommitted work."
  echo "$DIRTY"
  exit 1
fi

if [ -f "$ROOT/.git/MERGE_HEAD" ]; then
  echo "# Merge already in progress"
  echo "- current: $CURRENT ($SHORT_HEAD)"
  echo "- MERGE_HEAD: $(git rev-parse --short MERGE_HEAD)"
  echo "- unmerged:"
  git diff --name-only --diff-filter=U || true
  echo
  echo "Don't start a new merge. Finish the current one: resolve the files, git add, git commit."
  exit 0
fi

resolve_source() {
  name="$1"
  name="${name#refs/heads/}"
  name="${name#refs/remotes/}"

  if echo "$name" | grep -q '^origin/'; then
    short="${name#origin/}"
    if git rev-parse --verify --quiet "$name" >/dev/null; then
      echo "$name $short"
      return
    fi
  fi

  if git rev-parse --verify --quiet "origin/${name}" >/dev/null; then
    echo "origin/${name} ${name}"
    return
  fi
  if git rev-parse --verify --quiet "$name" >/dev/null; then
    echo "${name} ${name}"
    return
  fi

  # No exact name: most likely a task key (ABC-745) was given instead of the full
  # branch name (bugfix/ABC-745). Search local and origin/* branches; the local and
  # the remote copy of one branch count as one candidate.
  esc="$(printf '%s' "$name" | sed 's/[][\.^$*+?(){}|\\]/\\&/g')"
  all_branches="$(
    git for-each-ref --format='%(refname:short)' refs/heads refs/remotes/origin \
      | sed '/^origin\/HEAD$/d' \
      | sed 's|^origin/||' \
      | sort -u
  )"

  # First a branch name ending with the key: bugfix/ABC-745 for ABC-745.
  cands="$(printf '%s\n' "$all_branches" | grep -i -E "(^|/)${esc}\$" || true)"

  if [ -z "$cands" ]; then
    cands="$(printf '%s\n' "$all_branches" | grep -i -- "$esc" || true)"
  fi

  count="$(printf '%s\n' "$cands" | grep -c . || true)"

  if [ "$count" = "1" ]; then
    picked="$(printf '%s\n' "$cands" | head -n 1)"
    echo "resolved: $1 -> $picked" >&2
    if git rev-parse --verify --quiet "origin/${picked}" >/dev/null; then
      echo "origin/${picked} ${picked}"
    else
      echo "${picked} ${picked}"
    fi
    return
  fi

  if [ "$count" != "0" ]; then
    echo "ERROR: several branches match \"$1\" — say which one to merge:" >&2
    printf '%s\n' "$cands" | sed 's/^/  /' >&2
    exit 1
  fi

  die "branch not found: $1. Example: master, develop, origin/master, ABC-745"
}

HAS_ORIGIN=0
if git remote get-url origin >/dev/null 2>&1; then
  HAS_ORIGIN=1
fi

FETCH_OK=0
FETCH_NOTE="fetch skipped (no origin)"
if [ "$HAS_ORIGIN" -eq 1 ]; then
  echo "## Fetch"
  if git fetch origin --prune; then
    FETCH_OK=1
    FETCH_NOTE="git fetch origin — ok"
  else
    FETCH_NOTE="git fetch origin — FAILED, using the local origin/* (may be stale)"
  fi
  echo "$FETCH_NOTE"
  echo
fi

read SRC SHORT <<EOF
$(resolve_source "$SRC_ARG")
EOF

if [ "$FETCH_OK" -eq 1 ]; then
  if git rev-parse --verify --quiet "origin/${SHORT}" >/dev/null; then
    SRC="origin/${SHORT}"
    if git show-ref --verify --quiet "refs/heads/${SHORT}"; then
      if git merge-base --is-ancestor "$SHORT" "origin/${SHORT}"; then
        if git fetch origin "${SHORT}:${SHORT}"; then
          echo "local ${SHORT} fast-forwarded to origin/${SHORT}"
        fi
      else
        echo "local ${SHORT} has diverged from origin/${SHORT} — left as is. Merging ${SRC}."
      fi
    fi
  fi
fi

SRC_SHA="$(git rev-parse "$SRC")"
SHORT_SRC="$(git rev-parse --short "$SRC")"

if [ "$HEAD_SHA" = "$SRC_SHA" ]; then
  die "the current branch and $SRC point to the same commit. Nothing to merge."
fi

CUR_SHORT="$(echo "$CURRENT" | tr '[:upper:]' '[:lower:]')"
SRC_SHORT_LC="$(echo "$SHORT" | tr '[:upper:]' '[:lower:]')"
if [ "$CUR_SHORT" = "$SRC_SHORT_LC" ]; then
  die "a branch cannot be merged into itself ($CURRENT)."
fi

MB="$(git merge-base HEAD "$SRC" 2>/dev/null || true)"
if [ -z "$MB" ]; then
  die "no merge-base with $SRC."
fi

INCOMING="$(git log --oneline HEAD.."$SRC" | wc -l | tr -d ' ')"
OURS="$(git log --oneline "$SRC"..HEAD | wc -l | tr -d ' ')"

echo "# Merge context"
echo "- repo: $ROOT"
echo "- current (ours): $CURRENT @ $SHORT_HEAD"
echo "- source (theirs, being merged in): $SRC @ $SHORT_SRC"
echo "- fetch: $FETCH_NOTE"
echo "- merge-base: $(git rev-parse --short "$MB")"
echo "- commits incoming (source not in current): $INCOMING"
echo "- commits on current not in source: $OURS"
echo

if [ "$INCOMING" = "0" ]; then
  echo "## Result"
  echo "Already up to date: $CURRENT already has all commits of $SRC. No merge needed."
  exit 0
fi

# git itself does the limiting: `| head` closes the pipe, git log gets SIGPIPE,
# and `set -o pipefail` then kills the whole script (it broke on branches with >40
# incoming commits).
INCOMING_SHOWN=40
INCOMING_NOMERGE="$(git log --oneline --no-merges HEAD.."$SRC" | wc -l | tr -d ' ')"

echo "## Incoming commits (being merged into the current branch): $INCOMING_NOMERGE without merge commits"
git log --oneline --no-merges -n "$INCOMING_SHOWN" HEAD.."$SRC"
if [ "$INCOMING_NOMERGE" -gt "$INCOMING_SHOWN" ]; then
  echo "… and $((INCOMING_NOMERGE - INCOMING_SHOWN)) more commits"
fi
echo

echo "## Incoming diffstat vs merge-base"
git diff --stat "${MB}...${SRC}" | tail -n 20
echo

SRC_FILES_SHOWN=80
SRC_FILES_COUNT="$(git diff --name-only "${MB}...${SRC}" | wc -l | tr -d ' ')"

echo "## Files changed on source since merge-base: $SRC_FILES_COUNT"
git diff --name-only "${MB}...${SRC}" | awk -v n="$SRC_FILES_SHOWN" 'NR<=n'
if [ "$SRC_FILES_COUNT" -gt "$SRC_FILES_SHOWN" ]; then
  echo "… and $((SRC_FILES_COUNT - SRC_FILES_SHOWN)) more files"
fi
echo

# The overlap is the only place where the merge can lose the current branch's
# work. Everything else merges by itself.
BOTH="$(
  comm -12 \
    <(git diff --name-only "${MB}...HEAD" | sort) \
    <(git diff --name-only "${MB}...${SRC}" | sort) || true
)"
BOTH_COUNT="$(printf '%s\n' "$BOTH" | grep -c . || true)"

echo "## Files changed on BOTH sides since merge-base: $BOTH_COUNT"
if [ "$BOTH_COUNT" = "0" ]; then
  echo "(no overlap — no conflicts expected)"
else
  echo "This is where the conflicts will be. Keep both behaviours in every file:"
  printf '%s\n' "$BOTH" | awk 'NR<=60 {print "  " $0}'
  if [ "$BOTH_COUNT" -gt 60 ]; then
    echo "  … and $((BOTH_COUNT - 60)) more"
  fi
fi
echo

echo "## Next"
echo "git merge --no-edit ${SRC}"
echo "ours = $CURRENT (the task's functionality). theirs = $SRC (what is being merged in). Never checkout --ours/--theirs on a whole file."
