#!/usr/bin/env bash
# bash 3.2 compatible (macOS). Put stdin on the clipboard as UTF-8 and verify it landed intact.
#
# Why a separate script instead of bare pbcopy: when LANG/LC_CTYPE is not set in the shell
# (common for non-interactive runs), pbcopy marks the clipboard content as MacRoman.
# A pbcopy|pbpaste round trip then looks correct, but pasting non-ASCII text into a browser
# gives mojibake. Here the locale is set explicitly and the result is verified byte by byte.
set -euo pipefail

usage() {
  echo "usage: copy-utf8.sh [--label <name>] [file]"
  echo "       ... | copy-utf8.sh [--label <name>]"
}

LABEL="clipboard"
SRC=""

while [ $# -gt 0 ]; do
  case "$1" in
    --label)
      [ $# -ge 2 ] || { usage >&2; exit 2; }
      LABEL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      SRC="$1"
      shift
      ;;
  esac
done

FALLBACK_DIR="${HOME}/.claude/review-state"
mkdir -p "$FALLBACK_DIR"
FALLBACK="${FALLBACK_DIR}/${LABEL}.md"

if [ -n "$SRC" ]; then
  [ -f "$SRC" ] || { echo "ERROR: file not found: $SRC" >&2; exit 1; }
  cat "$SRC" > "$FALLBACK"
else
  cat > "$FALLBACK"
fi

BYTES="$(wc -c < "$FALLBACK" | tr -d ' ')"
if [ "$BYTES" = "0" ]; then
  echo "ERROR: empty input — the clipboard was not touched." >&2
  exit 1
fi

if ! command -v pbcopy >/dev/null 2>&1; then
  echo "pbcopy is not available. The text is saved to: $FALLBACK"
  exit 3
fi

# An explicit UTF-8 locale is the only difference between a working call and a broken one.
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 pbcopy < "$FALLBACK"

if LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 pbpaste | cmp -s - "$FALLBACK"; then
  echo "OK: ${BYTES} bytes of UTF-8 on the clipboard, identical byte by byte."
  echo "Backup copy in case pasting fails: $FALLBACK"
else
  echo "WARNING: the clipboard does not match the source text — paste from the file, not from the clipboard." >&2
  echo "Text: $FALLBACK" >&2
  exit 4
fi
