#!/bin/bash

# brew-release.sh - Update Homebrew cask formula with new release
# Usage: ./brew-release.sh <path-to-dmg>

set -e

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
VERSION=$(echo "$FILENAME" | sed -n 's/CleanBoard-\([0-9.]*\)-Installer\.dmg/\1/p')

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

# Update cleanboard.rb
CASK_FILE="cleanboard.rb"

if [ ! -f "$CASK_FILE" ]; then
    echo "Error: $CASK_FILE not found in current directory"
    exit 1
fi

echo "Updating $CASK_FILE..."

# Create temporary file with updated content
cat > "$CASK_FILE.tmp" << EOF
cask "cleanboard" do
  version "$VERSION"
  sha256 "$SHA256"

  url "https://github.com/tompodab/cleanboard/releases/download/#{version}/CleanBoard-#{version}-Installer.dmg"
  name "CleanBoard"
  desc "Lightweight app that removes formatting from copied text by hitting copy twice"
  homepage "https://cleanboard.app"

  app "CleanBoard.app"

  zap trash: [
    "~/Library/Application Support/CleanBoard",
    "~/Library/Preferences/com.cleanboard.app.plist",
    "~/Library/Caches/com.cleanboard.app",
  ]
end
EOF

# Replace old file with new one
mv "$CASK_FILE.tmp" "$CASK_FILE"

echo "✓ Successfully updated $CASK_FILE"
echo ""

# Show the changes
echo "Changes made:"
git diff "$CASK_FILE"
echo ""

# Confirm before proceeding
read -p "Do you want to commit and push these changes? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # Add and commit
    echo "Committing changes..."
    git add "$CASK_FILE"
    git commit -m "Update to version $VERSION"

    # Push to GitHub
    echo "Pushing to GitHub..."
    git push

    echo ""
    echo "✓ Successfully released version $VERSION!"
else
    echo "Aborted. Changes have been made to $CASK_FILE but not committed."
    echo "You can manually commit with: git add $CASK_FILE && git commit -m \"Update to version $VERSION\""
fi
