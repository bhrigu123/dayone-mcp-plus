#!/bin/bash
# Publishes a release: builds the notarized zip (scripts/release.sh), tags and uploads it to
# GitHub Releases, then updates the cask in the Homebrew tap.
#
# Bump Config.version first; each version can only be published once.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/common.sh

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: commit or stash your changes first." >&2
  exit 1
fi

scripts/release.sh
VERSION="$("dist/$APP_NAME.app/Contents/MacOS/$EXECUTABLE" --version)"
ZIP="dist/$EXECUTABLE-$VERSION.zip"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
TAG="v$VERSION"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "error: $TAG already exists; bump Config.version." >&2
  exit 1
fi

echo "==> Tagging $TAG and creating the GitHub release"
git tag -a "$TAG" -m "$APP_NAME $VERSION"
git push origin HEAD "$TAG"
gh release create "$TAG" "$ZIP" --repo "$GITHUB_REPO" --title "$APP_NAME $VERSION" --generate-notes

echo "==> Updating the cask in $TAP_REPO"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh repo clone "$TAP_REPO" "$TMP/tap" -- --quiet
mkdir -p "$TMP/tap/Casks"
scripts/cask.sh "$VERSION" "$SHA" > "$TMP/tap/Casks/$EXECUTABLE.rb"
git -C "$TMP/tap" add "Casks/$EXECUTABLE.rb"
git -C "$TMP/tap" commit --quiet -m "$EXECUTABLE $VERSION"
git -C "$TMP/tap" push --quiet

echo "==> Published $VERSION. Install with: brew install --cask ${TAP_REPO%%/*}/${TAP_REPO#*/homebrew-}/$EXECUTABLE"
