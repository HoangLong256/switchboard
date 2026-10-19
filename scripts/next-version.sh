#!/bin/sh
# Prints the next version tag from the commits since the last one, or nothing when no release is due.
#   feat: … / feature: …  → minor   v0.2.1 → v0.3.0
#   fix: …  / bug: …      → patch   v0.2.1 → v0.2.2
# A scope is allowed ("feat(editor): …"). Other commits (docs:, ci:, chore:, plain messages) don't release.
# sh scripts/next-version.sh [rev]   (default HEAD)
set -eu
cd "$(dirname "$0")/.."
REV="${1:-HEAD}"

LAST="$(git describe --tags --abbrev=0 --match 'v[0-9]*.[0-9]*.[0-9]*' "$REV" 2>/dev/null || true)"
if [ -n "$LAST" ]; then
  # already released
  [ "$(git rev-list -n 1 "$LAST")" = "$(git rev-parse "$REV")" ] && exit 0
  SUBJECTS="$(git log --format=%s "$LAST..$REV")"
else
  LAST=v0.0.0
  SUBJECTS="$(git log --format=%s "$REV")"
fi

if printf '%s\n' "$SUBJECTS" | grep -Eiq '^(feat|feature)(\([^)]*\))?!?:'; then
  BUMP=minor
elif printf '%s\n' "$SUBJECTS" | grep -Eiq '^(fix|bug)(\([^)]*\))?!?:'; then
  BUMP=patch
else
  exit 0
fi

IFS=. read -r MAJOR MINOR PATCH <<EOF
${LAST#v}
EOF
case $BUMP in
  minor) echo "v$MAJOR.$((MINOR + 1)).0" ;;
  patch) echo "v$MAJOR.$MINOR.$((PATCH + 1))" ;;
esac
