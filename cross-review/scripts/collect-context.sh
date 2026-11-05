#!/usr/bin/env bash
# bash 3.2 compatible (macOS). Collect committed PR context for cross-review.
set -euo pipefail

# Claude Code (the desktop app especially) runs the script without LANG/LC_*. Then pbpaste returns non-ASCII
# text as '?', the PR template headings on the clipboard are not found and the description counts as MISSING.
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8

usage() {
  echo "usage: collect-context.sh [author|draft] [full] [since <sha>] [base <branch>] [pr <file>] [save] [round <n>]"
}

die() {
  echo "ERROR: $1" >&2
  exit 1
}

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  die "not a git repository. Run it from a checkout of the branch under review."
fi

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if ! git rev-parse --verify --quiet HEAD >/dev/null; then
  die "the repository has no commits (no HEAD)."
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
SHORT_HEAD="$(git rev-parse --short HEAD)"

STATE_DIR="${HOME}/.claude/review-state"
mkdir -p "$STATE_DIR"
STATE_KEY="$(printf '%s' "$ROOT" | shasum -a 256 | awk '{print substr($1,1,16)}')"
BRANCH_KEY="$(printf '%s' "$BRANCH" | shasum -a 256 | awk '{print substr($1,1,12)}')"
# The previous-round point is per branch: reviewing branch B must not reset the round of branch A.
STATE_FILE="${STATE_DIR}/${STATE_KEY}.${BRANCH_KEY}.txt"
# Before the per-branch split there was one point per repository — read it if it is about this branch.
LEGACY_STATE_FILE="${STATE_DIR}/${STATE_KEY}.txt"

BASE_OVERRIDE=""
SINCE=""
FORCE_FULL=0
DO_SAVE=0
ROUND_HINT=""
AUTHOR=0
DRAFT=0
TICKET_OVERRIDE=""
PR_FILE=""

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help|help)
      usage
      exit 0
      ;;
    author|self)
      AUTHOR=1
      shift
      ;;
    draft|pr-template|template)
      AUTHOR=1
      DRAFT=1
      shift
      ;;
    full)
      FORCE_FULL=1
      shift
      ;;
    save)
      DO_SAVE=1
      shift
      ;;
    since)
      [ $# -ge 2 ] || die "since needs a sha"
      SINCE="$2"
      shift 2
      ;;
    base)
      [ $# -ge 2 ] || die "base needs a branch name"
      BASE_OVERRIDE="$2"
      shift 2
      ;;
    round)
      [ $# -ge 2 ] || die "round needs a number"
      ROUND_HINT="$2"
      shift 2
      ;;
    round2)
      ROUND_HINT="2"
      shift
      ;;
    pr|--pr)
      [ $# -ge 2 ] || die "pr needs a path to a file with the PR description"
      PR_FILE="$2"
      shift 2
      ;;
    *)
      if echo "$1" | grep -qE '^[A-Za-z]{2,10}-[0-9]+$'; then
        TICKET_OVERRIDE="$(echo "$1" | tr '[:lower:]' '[:upper:]')"
      fi
      shift
      ;;
  esac
done

# || true: without a key grep returns 1, and under pipefail + set -e the assignment key="$(...)" would
# silently kill the script (commits like "fix review", "Merged in ...", a branch without a task key).
extract_ticket() {
  echo "$1" | grep -oE '[A-Za-z]{2,10}-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]' || true
}

load_state() {
  SAVED_BRANCH=""
  SAVED_SHA=""
  SAVED_ROUND="0"
  SAVED_BASE=""
  src="$STATE_FILE"
  if [ ! -f "$src" ] && [ -f "$LEGACY_STATE_FILE" ] \
    && [ "$(awk -F= '/^branch=/{print $2}' "$LEGACY_STATE_FILE")" = "$BRANCH" ]; then
    src="$LEGACY_STATE_FILE"
  fi
  if [ -f "$src" ]; then
    SAVED_BRANCH="$(awk -F= '/^branch=/{print $2}' "$src")"
    SAVED_SHA="$(awk -F= '/^reviewed_sha=/{print $2}' "$src")"
    SAVED_ROUND="$(awk -F= '/^round=/{print $2}' "$src")"
    SAVED_BASE="$(awk -F= '/^base=/{print $2}' "$src")"
  fi
  [ -n "$SAVED_ROUND" ] || SAVED_ROUND="0"
}

save_state() {
  mkdir -p "$STATE_DIR"
  cat >"$STATE_FILE" <<EOF
repo=$ROOT
branch=$BRANCH
base=$BASE
reviewed_sha=$HEAD_SHA
round=$ROUND
saved_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF
  echo "saved review state: branch=$BRANCH sha=$SHORT_HEAD round=$ROUND file=$STATE_FILE"
}

# Branch name -> ref. origin/<name> wins over the local branch: a local release/master is usually behind
# the remote one, and a merge-base with it drags other people's already merged commits into the review.
resolve_ref() {
  case "$1" in
    origin/*) candidates="$1" ;;
    *) candidates="origin/$1 $1" ;;
  esac
  for c in $candidates; do
    if git rev-parse --verify --quiet "${c}^{commit}" >/dev/null; then
      echo "$c"
      return 0
    fi
  done
  return 1
}

detect_base() {
  if [ -n "$BASE_OVERRIDE" ]; then
    resolve_ref "$BASE_OVERRIDE" || die "base not found: $BASE_OVERRIDE"
    return
  fi
  # A train branch (ABC-123-release, ABC-123-update-develop) targets the base named by its suffix.
  case "${BRANCH##*-}" in
    release|develop|master|main)
      if ref="$(resolve_ref "${BRANCH##*-}")"; then
        echo "$ref"
        return
      fi
      ;;
  esac
  for candidate in origin/develop origin/master origin/main develop master main; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null; then
      echo "$candidate"
      return
    fi
  done
  if git symbolic-ref --quiet refs/remotes/origin/HEAD >/dev/null 2>&1; then
    git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/@@'
    return
  fi
  die "could not determine the base branch. Pass it: base develop"
}

EXCLUDES=(
  ':(exclude)composer.lock'
  ':(exclude)package-lock.json'
  ':(exclude)yarn.lock'
  ':(exclude)pnpm-lock.yaml'
  ':(exclude)*.lock'
  ':(exclude)*.min.js'
  ':(exclude)*.min.css'
  ':(exclude)*_ide_helper.php'
  ':(exclude)*.phpstorm.meta.php'
  ':(exclude)vendor'
  ':(exclude)node_modules'
  ':(exclude)public/build'
  ':(exclude)public/hot'
  ':(exclude)storage/framework'
  ':(exclude)bootstrap/cache'
)

# The same excludes for the commands the script prints: in zsh (Claude Code's shell) an unquoted
# `:(exclude)*.lock` is a glob and the command fails with "no matches found".
EXCLUDES_QUOTED="$(printf "'%s' " "${EXCLUDES[@]}")"
EXCLUDES_QUOTED="${EXCLUDES_QUOTED% }"

count_diff_lines() {
  local range="$1"
  git diff --numstat "$range" -- . "${EXCLUDES[@]}" 2>/dev/null | awk '
    { add += $1; del += $2; files += 1 }
    END { printf "%d %d %d %d\n", add+0, del+0, (add+del)+0, files+0 }
  '
}

# Contiguous task block: newest ticket commits (+ unlabeled review fixes on top).
# Stop at an older commit with a different ticket key.
resolve_task_range() {
  TASK_PARENT=""
  TASK_HEAD=""
  TICKET_FOUND=0
  HEAD_PREFIX_OTHER=0

  if [ -z "$TICKET" ]; then
    return
  fi

  NEWEST_TICKET=""
  OLDEST_TICKET=""
  while read -r hash subject; do
    [ -n "$hash" ] || continue
    is_this=0
    echo "$subject" | grep -qi -- "$TICKET" && is_this=1
    key="$(extract_ticket "$subject")"

    if [ "$is_this" -eq 1 ]; then
      [ -n "$NEWEST_TICKET" ] || NEWEST_TICKET="$hash"
      OLDEST_TICKET="$hash"
      continue
    fi

    if [ -z "$NEWEST_TICKET" ]; then
      if [ -n "$key" ]; then
        HEAD_PREFIX_OTHER=1
      fi
      continue
    fi

    if [ -n "$key" ]; then
      break
    fi
  done <<EOF
$(git log --format='%H %s' "${MERGE_BASE}..${HEAD_SHA}")
EOF

  if [ -z "$OLDEST_TICKET" ]; then
    return
  fi

  TICKET_FOUND=1
  TASK_PARENT="$(git rev-parse "${OLDEST_TICKET}^" 2>/dev/null || true)"
  [ -n "$TASK_PARENT" ] || TASK_PARENT="$MERGE_BASE"
  # The task range is never wider than the branch: when the base is merged into the branch (ABC-123-release =
  # a task cut from master + a merge of release), the parent of the task's first commit lies before the merge-base,
  # and without this check the whole base ends up in the review (tens of thousands of lines instead of hundreds).
  if ! git merge-base --is-ancestor "$MERGE_BASE" "$TASK_PARENT" 2>/dev/null; then
    TASK_PARENT="$MERGE_BASE"
  fi
  if [ "$HEAD_PREFIX_OTHER" -eq 1 ]; then
    TASK_HEAD="$NEWEST_TICKET"
  else
    TASK_HEAD="$HEAD_SHA"
  fi
}

# A copy from Bitbucket may have CRLF, non-breaking spaces and markup (## Risks, **Why:**, - Migrations).
# Strip all of that so the heading ends up at the start of the line.
normalize_pr_text() {
  printf '%s\n' "$1" \
    | LC_ALL=C tr -d '\r' \
    | LC_ALL=C sed -E -e $'s/\xc2\xa0/ /g' -e 's/[*_#:>?]//g' -e 's/^[[:space:]]*([-+]|[0-9]+\.)?[[:space:]]*//'
}

# A heading counts only if a line starts with it: the words "risks" or "migrations" inside ordinary
# text don't make it a PR template. English and Russian headings are recognised.
pr_template_hits() {
  norm="$(normalize_pr_text "$1")"
  n=0
  grep -qiE '^(what( has)? changed|что измен)' <<<"$norm" && n=$((n + 1))
  grep -qiE '^(why|зачем)([[:space:]]|$)' <<<"$norm" && n=$((n + 1))
  grep -qiE '^(how to (test|verify|check)|как (провер|тестир))' <<<"$norm" && n=$((n + 1))
  grep -qiE '^(risk|риск)' <<<"$norm" && n=$((n + 1))
  grep -qiE '^(migration|миграц)' <<<"$norm" && n=$((n + 1))
  echo "$n"
}

emit_pr_description() {
  src=""
  body=""
  clip_note=""
  # Bound to the branch: a previous PR's description in this repository must not leak into another branch's review.
  saved_pr="${STATE_DIR}/${STATE_KEY}.${BRANCH_KEY}.pr.md"

  if [ -n "$PR_FILE" ]; then
    [ -f "$PR_FILE" ] || die "PR description file not found: $PR_FILE"
    src="file:$PR_FILE"
    body="$(cat "$PR_FILE")"
  elif [ -f "$ROOT/.review-pr.md" ]; then
    src="file:$ROOT/.review-pr.md"
    body="$(cat "$ROOT/.review-pr.md")"
  elif command -v pbpaste >/dev/null 2>&1; then
    clip="$(pbpaste -Prefer txt 2>/dev/null || true)"
    if [ -z "$clip" ]; then
      clip_note="the clipboard is empty"
    else
      hits="$(pr_template_hits "$clip")"
      if [ "$hits" -ge 2 ]; then
        src="clipboard"
        body="$clip"
      else
        clip_note="the clipboard has ${#clip} chars, template headings ${hits}/5 (need >=2). Does not look like a PR description, skipped."
      fi
    fi
  fi

  if [ -z "$body" ] && [ -f "$saved_pr" ]; then
    src="saved:$saved_pr (from a previous run on this branch)"
    body="$(cat "$saved_pr")"
  fi

  echo "## PR description (author's template)"
  if [ -n "$clip_note" ]; then
    echo "clipboard: $clip_note"
  fi
  if [ -z "$body" ]; then
    echo "MISSING"
    echo "Needs the PR text: What changed / Why / How to test / Risks / Migrations."
    echo "How to pass it: Copy the description in Bitbucket and run /cross-review right away; or paste it into the chat; or save it to .review-pr.md in the repository root."
    echo "By the process, a PR without a description may be returned without review."
    echo
    return
  fi

  hits="$(pr_template_hits "$body")"
  echo "source: $src"
  echo "template headings found: $hits / 5"
  if [ "$hits" -lt 2 ]; then
    echo "WARNING: the text does not look like the process template."
  fi
  # The clipboard may hold someone else's or the user's own description (for example after /pr-template).
  if [ -n "$TICKET" ] && ! grep -qi -- "$TICKET" <<<"$body"; then
    keys="$(grep -oE '[A-Z][A-Z0-9]{1,9}-[0-9]+' <<<"$body" | sort -u | head -5 | tr '\n' ' ' || true)"
    keys="${keys% }"
    echo "WARNING: the description has no key ${TICKET} (branch ${BRANCH})${keys:+, found: ${keys}}. Make sure this is the description of this PR."
  fi
  echo '```markdown'
  printf '%s\n' "$body"
  echo '```'
  printf '%s\n' "$body" >"$saved_pr"
  echo "saved copy: $saved_pr"
  echo
}

emit_author_hints() {
  echo "## Author PR hints"
  echo "- ticket: ${TICKET:-none}"
  echo "- branch: $BRANCH"
  echo "- review range: $REVIEW_RANGE"
  echo "- size: +${ADD} / -${DEL} = ${TOTAL} in ${FILES} files"
  echo

  names="$(git diff --name-only "$REVIEW_RANGE" -- . "${EXCLUDES[@]}" 2>/dev/null || true)"

  echo "### Migrations"
  mig="$(echo "$names" | grep -iE 'database/.*/migrations/|database/migrations/|_table\.php$' || true)"
  if [ -z "$mig" ]; then
    echo "none"
  else
    echo "$mig"
  fi
  echo

  echo "### Tests"
  tests="$(echo "$names" | grep -iE '(^|/)tests?/|_test\.php$|Test\.php$' || true)"
  if [ -z "$tests" ]; then
    echo "none"
  else
    echo "$tests"
  fi
  echo

  echo "### Risk flags (by path)"
  risks=""
  echo "$names" | grep -qiE 'pay|refund|invoice|billing|acquiring' && risks="${risks}payments / refunds / "
  echo "$names" | grep -qiE 'auth|permission|policy|gate|acl|passport|sanctum' && risks="${risks}auth / "
  echo "$names" | grep -qiE 'migrat' && risks="${risks}DB / "
  echo "$names" | grep -qiE 'job|queue|kafka|rabbit|horizon' && risks="${risks}queues / "
  echo "$names" | grep -qiE 'cache|redis' && risks="${risks}cache / "
  echo "$names" | grep -qiE 'http|client|webhook|callback|integration|sdk' && risks="${risks}integrations / "
  if [ -z "$risks" ]; then
    echo "none"
  else
    echo "$risks"
  fi
  echo

  echo "### API / HTTP files"
  httpf="$(echo "$names" | grep -iE 'routes/|Controller\.php$|Request\.php$|Resource\.php$|Endpoint' || true)"
  if [ -z "$httpf" ]; then
    echo "none"
  else
    echo "$httpf"
  fi
  echo
}

BASE="$(detect_base)"
load_state

if [ "$DO_SAVE" -eq 1 ]; then
  ROUND="${ROUND_HINT:-}"
  if [ -z "$ROUND" ]; then
    if [ "$SAVED_BRANCH" = "$BRANCH" ] && [ "$SAVED_SHA" = "$HEAD_SHA" ] && [ "$SAVED_ROUND" -gt 0 ]; then
      ROUND="$SAVED_ROUND"
    elif [ "$SAVED_BRANCH" = "$BRANCH" ] && [ "$SAVED_ROUND" -gt 0 ]; then
      ROUND=$((SAVED_ROUND + 1))
    else
      ROUND=1
    fi
  fi
  save_state
  exit 0
fi

MERGE_BASE="$(git merge-base "$BASE" HEAD 2>/dev/null || true)"
if [ -z "$MERGE_BASE" ]; then
  die "no merge-base with $BASE. Run git fetch."
fi

if [ -n "$TICKET_OVERRIDE" ]; then
  TICKET="$TICKET_OVERRIDE"
else
  TICKET="$(extract_ticket "$BRANCH")"
fi

TASK_PARENT=""
TASK_HEAD=""
TICKET_FOUND=0
HEAD_PREFIX_OTHER=0
resolve_task_range

BRANCH_RANGE="${MERGE_BASE}...${HEAD_SHA}"
FULL_RANGE="$BRANCH_RANGE"
REVIEW_RANGE="$FULL_RANGE"
SCOPE="branch-vs-base"
MODE="full"
ROUND=1
PREV_SHA=""

if [ "$FORCE_FULL" -eq 0 ] && [ "$TICKET_FOUND" -eq 1 ]; then
  FULL_RANGE="${TASK_PARENT}...${TASK_HEAD}"
  REVIEW_RANGE="$FULL_RANGE"
  SCOPE="task ${TICKET}"
fi

if [ -n "$SINCE" ]; then
  SINCE_SHA="$(git rev-parse --verify "${SINCE}^{commit}" 2>/dev/null || true)"
  [ -n "$SINCE_SHA" ] || die "since sha not found: $SINCE"
  REVIEW_RANGE="${SINCE_SHA}...${HEAD_SHA}"
  MODE="incremental"
  PREV_SHA="$SINCE_SHA"
  ROUND="${ROUND_HINT:-2}"
elif [ "$FORCE_FULL" -eq 0 ] && [ "$SAVED_BRANCH" = "$BRANCH" ] && [ -n "$SAVED_SHA" ]; then
  if git merge-base --is-ancestor "$SAVED_SHA" HEAD 2>/dev/null; then
    if [ "$SAVED_SHA" = "$HEAD_SHA" ]; then
      MODE="no_new_commits"
      PREV_SHA="$SAVED_SHA"
      ROUND="${SAVED_ROUND:-1}"
    else
      REVIEW_RANGE="${SAVED_SHA}...${HEAD_SHA}"
      MODE="incremental"
      PREV_SHA="$SAVED_SHA"
      if [ -n "$ROUND_HINT" ]; then
        ROUND="$ROUND_HINT"
      else
        ROUND=$((SAVED_ROUND + 1))
      fi
    fi
  fi
fi

if [ -n "$ROUND_HINT" ] && [ "$MODE" = "full" ]; then
  ROUND="$ROUND_HINT"
fi

read ADD DEL TOTAL FILES <<EOF
$(count_diff_lines "$FULL_RANGE")
EOF

read INC_ADD INC_DEL INC_TOTAL INC_FILES <<EOF
$(count_diff_lines "$REVIEW_RANGE")
EOF

DIRTY="$(git status --porcelain)"
REMOTE=""
if git remote get-url origin >/dev/null 2>&1; then
  REMOTE="$(git remote get-url origin)"
fi

echo "# Review git context"
if [ "$AUTHOR" -eq 1 ]; then
  echo "- role: author (own branch)"
else
  echo "- role: reviewer (foreign branch)"
fi
echo
echo "- repo: $ROOT"
echo "- remote: ${REMOTE:-none}"
echo "- branch: $BRANCH"
echo "- HEAD: $SHORT_HEAD ($HEAD_SHA)"
echo "- base: $BASE"
echo "- merge-base: $(git rev-parse --short "$MERGE_BASE")"
echo "- ticket: ${TICKET:-none}"
echo "- scope: $SCOPE"
echo "- round: $ROUND"
echo "- mode: $MODE"
echo "- branch range vs base: $BRANCH_RANGE"
echo "- full range: $FULL_RANGE"
echo "- review range: $REVIEW_RANGE"
if [ -n "$PREV_SHA" ]; then
  echo "- previous reviewed sha: $(git rev-parse --short "$PREV_SHA")"
fi
echo "- review diff lines (no lock/generated): +${ADD} / -${DEL} = ${TOTAL} in ${FILES} files"
if [ "$MODE" = "incremental" ]; then
  echo "- incremental lines: +${INC_ADD} / -${INC_DEL} = ${INC_TOTAL} in ${INC_FILES} files"
fi
echo "- state file: $STATE_FILE"

# Only git fetch updates origin/* refs: without it the base and the author's branch are yesterday's.
FETCH_HEAD_FILE="$(git rev-parse --git-path FETCH_HEAD)"
if [ -f "$FETCH_HEAD_FILE" ]; then
  fetched_at="$(stat -f %m "$FETCH_HEAD_FILE" 2>/dev/null || stat -c %Y "$FETCH_HEAD_FILE" 2>/dev/null || echo 0)"
  fetch_age_h=$(( ($(date +%s) - fetched_at) / 3600 ))
  echo "- last fetch: ${fetch_age_h}h ago"
  if [ "$fetch_age_h" -ge 12 ]; then
    echo "WARNING: last fetch is older than 12 h — the base and the author's branch may have moved on. First: git fetch origin"
  fi
else
  echo "WARNING: last fetch: never — first: git fetch origin"
fi
echo

if [ "$TOTAL" -le 300 ]; then
  echo "- size vs process: ok (<=300)"
elif [ "$TOTAL" -le 500 ]; then
  echo "- size vs process: acceptable (300-500). Author should still keep it reviewable."
else
  echo "- size vs process: too large (500+). Ask why it cannot be split. Review logic-critical files first."
fi
echo

if [ "$AUTHOR" -eq 1 ]; then
  echo "## Uncommitted (not in the PR until committed)"
else
  echo "## Uncommitted (NOT part of PR review)"
fi
if [ -z "$DIRTY" ]; then
  echo "working tree clean"
else
  if [ "$AUTHOR" -eq 1 ]; then
    echo "DIRTY TREE: for self-review show it separately from the committed changes. The Bitbucket PR does not have it."
  else
    echo "DIRTY TREE: review only the commits. Uncommitted changes are not part of the PR."
  fi
  echo '```'
  echo "$DIRTY"
  echo '```'
  echo
  echo "### Uncommitted stat"
  git diff --stat HEAD -- . "${EXCLUDES[@]}" || true
fi
echo

echo "## Commits in review range"
git log --oneline --no-merges "$(echo "$REVIEW_RANGE" | sed 's/\.\.\./../')" || true
echo

if [ "$SCOPE" != "branch-vs-base" ] && [ "$MODE" = "full" ]; then
  echo "## Note"
  echo "Reviewing task ${TICKET}, not the whole branch diff against ${BASE}."
  echo "Whole branch vs base: git diff --stat ${BRANCH_RANGE}"
  echo "Whole PR without the task filter: /cross-review full"
  echo
fi

if [ "$MODE" = "incremental" ]; then
  echo "## New commits since previous review"
  # --not BASE: commits that came in with a merge of the base are not the author's work.
  git log --oneline --no-merges "${PREV_SHA}..${HEAD_SHA}" --not "$BASE" || true
  echo
  if ! git merge-base --is-ancestor "$MERGE_BASE" "$PREV_SHA" 2>/dev/null; then
    echo "## WARNING: the base was merged into the branch after the previous round (${BASE})"
    echo "Diff ${REVIEW_RANGE} includes the base's commits — don't review by it."
    echo "Only the author's new commits:"
    echo "git log -p --no-merges ${PREV_SHA}..${HEAD_SHA} --not ${BASE} -- . ${EXCLUDES_QUOTED}"
    echo "Merge conflicts (if the author resolved any): git show --remerge-diff <merge-sha>"
    echo
  fi
fi

if [ "$MODE" = "no_new_commits" ]; then
  echo "## Note"
  echo "HEAD matches the previous review. No new diff. Check only the open items of the previous round."
  echo
fi

echo "## Changed files (full PR, excludes applied)"
git diff --name-status "$FULL_RANGE" -- . "${EXCLUDES[@]}" || true
echo

if [ "$MODE" = "incremental" ]; then
  echo "## Changed files (this round)"
  git diff --name-status "$REVIEW_RANGE" -- . "${EXCLUDES[@]}" || true
  echo
fi

echo "## Diff stat (review range)"
git diff --stat "$REVIEW_RANGE" -- . "${EXCLUDES[@]}" || true
echo

if [ "$INC_TOTAL" -gt 0 ] && [ "$INC_TOTAL" -le 250 ]; then
  echo "## Patch (review range, small enough to inline)"
  echo '```diff'
  git diff --find-renames "$REVIEW_RANGE" -- . "${EXCLUDES[@]}" || true
  echo '```'
else
  echo "## Patch"
  echo "Patch not inlined (empty or >250 lines). Read it with:"
  echo "git diff --find-renames ${REVIEW_RANGE} -- . ${EXCLUDES_QUOTED}"
fi
echo

echo "## Commits with bodies (review range)"
git log --no-merges --format='%h%n%s%n%b%n---' "$(echo "$REVIEW_RANGE" | sed 's/\.\.\./../')" | tail -n 80
echo

if [ "$AUTHOR" -eq 1 ]; then
  emit_author_hints
fi

if [ "$DRAFT" -eq 0 ]; then
  emit_pr_description
fi

echo "## Suggested follow-up after finishing this review"
echo "$0 save"
