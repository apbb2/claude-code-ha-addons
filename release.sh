#!/bin/bash
# Release helper — bumps version, stamps changelog with TODAY's date, commits, pushes.
# Usage:
#   ./release.sh <version> [section] "note" ["note" ...]
#   ./release.sh 3.0.2 Fixed "Terminal froze on reconnect" "Scrollback lost after detach"
#   ./release.sh 3.0.3 "Rebuild to bundle latest Claude Code release."   (section defaults to Changed)
set -e
cd "$(dirname "$0")"

VERSION="$1"; shift || true
if [ -z "$VERSION" ] || [ $# -eq 0 ]; then
    echo "usage: ./release.sh <version> [Added|Changed|Fixed|Security] \"note\" [\"note\" ...]" >&2
    exit 1
fi

case "$1" in
    Added|Changed|Fixed|Security) SECTION="$1"; shift ;;
    *) SECTION="Changed" ;;
esac

TODAY=$(date +%Y-%m-%d)
CONFIG=claudecode/config.yaml
CHANGELOG=claudecode/CHANGELOG.md

# Bump version in config.yaml
awk -v v="$VERSION" '/^version: /{print "version: \"" v "\""; next} {print}' "$CONFIG" > "$CONFIG.tmp" \
    && mv "$CONFIG.tmp" "$CONFIG"

# Build the changelog entry with today's date — never hand-written, never stale
{
    echo "## [$VERSION] - $TODAY"
    echo
    echo "### $SECTION"
    for note in "$@"; do echo "- $note"; done
    echo
} > /tmp/changelog-entry.md

# Insert entry above the previous newest entry (first '## [' line)
awk '/^## \[/ && !done { while ((getline line < "/tmp/changelog-entry.md") > 0) print line; done=1 } { print }' \
    "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
rm -f /tmp/changelog-entry.md

echo "=== $CONFIG ==="
grep '^version:' "$CONFIG"
echo "=== $CHANGELOG (new entry) ==="
sed -n "/## \[$VERSION\]/,/^## \[/p" "$CHANGELOG" | sed '$d'

git add "$CONFIG" "$CHANGELOG"
git commit -m "v$VERSION: $1"

# Build images from a staging branch FIRST. HA only reads main, so users never
# see a version whose images don't exist yet (they'd get pull errors).
echo "Pushing to release branch for image build..."
git push --force origin HEAD:refs/heads/release

echo "Waiting for image build (GitHub Actions)..."
sleep 10
RUN_ID=$(gh run list --workflow=builder.yaml --branch release --limit 1 --json databaseId --jq '.[0].databaseId')
if gh run watch "$RUN_ID" --exit-status; then
    echo "CI green — v$VERSION images are live on ghcr.io. Publishing to main..."
    git push
    echo "Released v$VERSION ($TODAY)."
else
    echo "CI FAILED — v$VERSION was NOT published (main is untouched, users unaffected)." >&2
    echo "Fix the build, then re-run: ./release.sh (images rebuild from the release branch)" >&2
    exit 1
fi
