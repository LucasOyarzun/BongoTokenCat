#!/bin/bash
# Cut a release: test, build, publish to GitHub Releases, bump the Homebrew cask.
#
# Usage:
#   ./scripts/release.sh 0.1.0
#   RELEASE_NOTES_FILE=/tmp/notes.md ./scripts/release.sh 0.1.0
#
# The version lives in one place — VERSION in scripts/build-app.sh — and every
# other mention of it (Info.plist, git tag, release title, cask) is derived from
# there, so they cannot drift apart.
#
# Order matters: everything that can fail runs *before* the push. A failed build
# leaves the version bump uncommitted, so origin/main is untouched and rerunning
# is safe.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="BongoTokenCat"
REPO="LucasOyarzun/BongoTokenCat"
TAP_REPO="LucasOyarzun/homebrew-tap"
CASK_PATH="Casks/bongo-token-cat.rb"
CASK_SOURCE="packaging/homebrew/bongo-token-cat.rb"
ZIP="build/$APP_NAME.zip"

VERSION="${1:-}"
[ -n "$VERSION" ] || { echo "usage: release.sh <version>   (e.g. 0.1.0)" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "✗ not a semver version: $VERSION" >&2; exit 1; }

fail() { echo "✗ $1" >&2; exit 1; }

# ── Preflight ───────────────────────────────────────────────────────────────
# Checked up front rather than at the step that needs them: discovering a missing
# tap after the GitHub Release is already public means a half-published version.
check_preconditions() {
    echo "==> preflight"
    local branch
    branch=$(git rev-parse --abbrev-ref HEAD)
    [ "$branch" = "main" ] || fail "release from main, not $branch"
    [ -z "$(git status --porcelain)" ] || fail "working tree is dirty — commit or stash first"
    command -v gh >/dev/null || fail "gh is not installed (brew install gh)"
    gh auth status >/dev/null 2>&1 || fail "gh is not authenticated (gh auth login)"
    gh api "repos/$TAP_REPO" >/dev/null 2>&1 \
        || fail "tap repo $TAP_REPO not found — create it before the first release"
    git fetch -q origin main
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] \
        || fail "local main differs from origin/main — pull or push first"
    echo "    ok"
}

bump_version() {
    echo "==> version $PREVIOUS_VERSION -> $VERSION (not committed yet)"
    sed -i '' "s/^VERSION=\"[0-9.]*\"/VERSION=\"$VERSION\"/" scripts/build-app.sh
}

# Build and verify before anything leaves the machine. The Info.plist check
# catches a bump that silently failed to apply, which would otherwise ship a zip
# labelled with the previous version.
build_and_package() {
    echo "==> building"
    ./scripts/build-app.sh >/dev/null
    local built
    built=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" \
        "build/$APP_NAME.app/Contents/Info.plist")
    [ "$built" = "$VERSION" ] || fail "built bundle says $built, expected $VERSION"
    rm -f "$ZIP"
    ditto -c -k --keepParent "build/$APP_NAME.app" "$ZIP"
    echo "    $ZIP ($(du -h "$ZIP" | cut -f1))"
}

publish_release() {
    echo "==> pushing v$VERSION"
    # The bump is a no-op when build-app.sh already names this version — the first
    # release, or a rerun after a later step failed. Committing an empty stage exits
    # non-zero and would abort the release under `set -e`.
    if git diff --quiet -- scripts/build-app.sh; then
        echo "    version already recorded, nothing to commit"
    else
        git add scripts/build-app.sh
        git commit -q -m "release: bump version to $VERSION"
    fi
    git push -q origin main

    local notes_args=(--notes "Release v$VERSION")
    [ -n "${RELEASE_NOTES_FILE:-}" ] && notes_args=(--notes-file "$RELEASE_NOTES_FILE")
    gh release create "v$VERSION" "$ZIP" --repo "$REPO" \
        --title "$APP_NAME v$VERSION" --target main "${notes_args[@]}"
}

# The cask pins the checksum of the exact zip just uploaded. Homebrew verifies it
# on download, so a tampered or truncated asset fails loudly instead of installing.
update_cask() {
    echo "==> updating cask in $TAP_REPO"
    local checksum rendered existing_sha
    checksum=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
    rendered=$(mktemp)
    sed -e "s/^  version \".*\"/  version \"$VERSION\"/" \
        -e "s/^  sha256 \".*\"/  sha256 \"$checksum\"/" \
        "$CASK_SOURCE" > "$rendered"
    grep -q "version \"$VERSION\"" "$rendered" || fail "cask version substitution failed"

    existing_sha=$(gh api "repos/$TAP_REPO/contents/$CASK_PATH" --jq '.sha' 2>/dev/null || true)
    local args=(-f "message=bongo-token-cat $VERSION"
                -f "content=$(base64 < "$rendered" | tr -d '\n')")
    [ -n "$existing_sha" ] && args+=(-f "sha=$existing_sha")
    gh api --method PUT "repos/$TAP_REPO/contents/$CASK_PATH" "${args[@]}" >/dev/null
    rm -f "$rendered"
    echo "    sha256 $checksum"
}

PREVIOUS_VERSION=$(grep -oE '^VERSION="[0-9.]+"' scripts/build-app.sh | grep -oE '[0-9.]+')

check_preconditions
echo "==> running tests"
./scripts/test.sh >/dev/null || fail "tests failed"
bump_version
build_and_package
publish_release
update_cask

cat <<DONE

released $APP_NAME v$VERSION

verify with:
  brew update && brew upgrade --cask bongo-token-cat
DONE
