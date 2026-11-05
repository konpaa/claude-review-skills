#!/usr/bin/env bash
# bash 3.2 compatible (macOS). Installs the skills from this folder into ~/.claude/skills as symlinks.
#
# Install from a clone/copy of the WHOLE folder: pr-template and review-reply use the scripts and process.md
# from cross-review through relative symlinks, so a single skill folder does not work on its own.
# Don't move the folder after installing — the links in ~/.claude/skills would dangle (run this again).
set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd -P)"
DEST="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
SKILLS="cross-review pr-template review-reply merge-from"

mkdir -p "$DEST"

broken="$(find -L "$REPO" -type l -not -path '*/.git/*' 2>/dev/null || true)"
if [ -n "$broken" ]; then
  echo "ERROR: broken symlinks inside $REPO (not the whole folder copied, or symlinks lost?):" >&2
  echo "$broken" >&2
  exit 1
fi

chmod +x "$REPO"/*/scripts/*.sh 2>/dev/null || true

for skill in $SKILLS; do
  target="$DEST/$skill"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "SKIP $skill: $target exists and is not a symlink — left untouched, remove it by hand"
    continue
  fi
  ln -sfn "$REPO/$skill" "$target"
  echo "OK   /$skill -> $REPO/$skill"
done

TEAM_FILE="${HOME}/.claude/review-team.md"
echo
if [ -f "$TEAM_FILE" ]; then
  echo "Team settings: $TEAM_FILE"
else
  echo "No team settings. For the output language, task links and reviewer suggestions:"
  echo "  cp \"$REPO/team.example.md\" \"$TEAM_FILE\"   # then fill in your own data"
fi

echo
echo "Restart Claude Code in the root of the project repository, then type / and pick the command."
