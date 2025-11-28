#!/bin/bash

# brew-release.sh - Update Homebrew cask formula with new release
# Usage: ./brew-release.sh <path-to-dmg>

set -euo pipefail

TAP_REPO_URL="${TAP_REPO_URL:-git@github.com:tompodab/homebrew-cleanboard.git}"
TAP_FULL_NAME="tompodab/cleanboard"
CASK_TOKEN="cleanboard"

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path-to-dmg>"
    echo "Example: $0 /path/to/CleanBoard-2.4.0-Installer.dmg"
    exit 1
fi

DMG_PATH="$1"

# Verify DMG file exists
if [ ! -f "$DMG_PATH" ]; then
    echo "Error: DMG file not found: $DMG_PATH"
    exit 1
fi

# Extract version from filename (e.g., CleanBoard-2.4.0-Installer.dmg -> 2.4.0)
FILENAME=$(basename "$DMG_PATH")
VERSION=$(echo "$FILENAME" | sed -n 's/CleanBoard-\([0-9][0-9A-Za-z._-]*\)-Installer\.dmg/\1/p')

if [ -z "$VERSION" ]; then
    echo "Error: Could not extract version from filename: $FILENAME"
    echo "Expected format: CleanBoard-X.Y.Z-Installer.dmg"
    exit 1
fi

echo "Detected version: $VERSION"

# Calculate SHA256
echo "Calculating SHA256 hash..."
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "SHA256: $SHA256"

# Build cask content in a temporary file
TMP_CASK="$(mktemp "/tmp/${CASK_TOKEN}.XXXX.rb")"
TAP_CLONE_DIR=""
cask_audit_dir=""
cleanup() {
    rm -f "$TMP_CASK"
    if [ -n "$cask_audit_dir" ] && [ -d "$cask_audit_dir" ]; then
        rm -rf "$cask_audit_dir"
    fi
    if [ -n "$TAP_CLONE_DIR" ] && [ -d "$TAP_CLONE_DIR" ]; then
        rm -rf "$TAP_CLONE_DIR"
    fi
}
trap cleanup EXIT

cat > "$TMP_CASK" << EOF
cask "$CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/tompodab/cleanboard/releases/download/#{version}/CleanBoard-#{version}-Installer.dmg",
      verified: "github.com/tompodab/cleanboard/"
  name "CleanBoard"
  desc "Lightweight app that removes formatting from copied text by hitting copy twice"
  homepage "https://cleanboard.app/"

  app "CleanBoard.app"

  zap trash: [
    "~/Library/Application Support/CleanBoard",
    "~/Library/Caches/com.cleanboard.app",
    "~/Library/Preferences/com.cleanboard.app.plist",
  ]
end
EOF

echo "✓ Generated cask content"
echo ""

# Sync the updated cask to the tap repository
if ! command -v git >/dev/null 2>&1; then
    echo "Git not found; cannot update tap repository."
    exit 1
fi

echo "Cloning tap repository ($TAP_REPO_URL)..."
TAP_CLONE_DIR="$(mktemp -d "/tmp/cleanboard-tap.XXXX")"
git clone "$TAP_REPO_URL" "$TAP_CLONE_DIR"

TAP_BRANCH=$(git -C "$TAP_CLONE_DIR" rev-parse --abbrev-ref HEAD)
TAP_CASK_PATH="$TAP_CLONE_DIR/Casks/${CASK_TOKEN}.rb"
mkdir -p "$(dirname "$TAP_CASK_PATH")"
cp "$TMP_CASK" "$TAP_CASK_PATH"

# Always run style/audit before pushing
if command -v brew >/dev/null 2>&1; then
    AUDIT_TAP_NAME="local/cleanboard-audit"
    echo "Preparing temporary tap for audit..."
    cask_audit_dir="$(mktemp -d "/tmp/${CASK_TOKEN}-audit.XXXX")"
    git -C "$cask_audit_dir" init -q
    mkdir -p "$cask_audit_dir/Casks"
    cp "$TMP_CASK" "$cask_audit_dir/Casks/${CASK_TOKEN}.rb"
    git -C "$cask_audit_dir" add .
    git -C "$cask_audit_dir" commit -qm "Add cask for audit"

    brew tap "$AUDIT_TAP_NAME" "$cask_audit_dir"

    echo "Running brew style..."
    if brew style --cask "${AUDIT_TAP_NAME}/${CASK_TOKEN}"; then
        echo "✓ brew style passed"
    else
        echo "brew style failed; aborting before push."
        brew untap "$AUDIT_TAP_NAME"
        exit 1
    fi

    echo "Running brew audit (without notability check)..."
    if brew audit --cask --online "${AUDIT_TAP_NAME}/${CASK_TOKEN}"; then
        echo "✓ brew audit passed"
    else
        echo "brew audit failed; aborting before push."
        brew untap "$AUDIT_TAP_NAME"
        exit 1
    fi

    brew untap "$AUDIT_TAP_NAME"
    echo ""
else
    echo "Error: Homebrew not found; audit is required before push."
    exit 1
fi

if git -C "$TAP_CLONE_DIR" status --porcelain | grep -q .; then
    git -C "$TAP_CLONE_DIR" add "Casks/${CASK_TOKEN}.rb"
    git -C "$TAP_CLONE_DIR" commit -m "Update ${CASK_TOKEN} to ${VERSION}"
    git -C "$TAP_CLONE_DIR" push origin "$TAP_BRANCH"
    echo "✓ Pushed tap update to $TAP_REPO_URL (branch: $TAP_BRANCH)"
else
    echo "Tap repository already up to date; no changes to commit."
fi
