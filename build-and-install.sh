#!/bin/bash
set -euo pipefail

PROJECT_NAME="Rectangle"
BUILD_DIR="$HOME/.local/builds/$PROJECT_NAME"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Remove Homebrew-managed installation if present
if brew list --cask rectangle &>/dev/null; then
  echo "Homebrew cask 'rectangle' detected — removing with --zap..."
  brew uninstall --zap --cask rectangle
  echo "✓ Homebrew cask removed"
fi

echo "Building $PROJECT_NAME..."
if ! xcodebuild -project "$SCRIPT_DIR/Rectangle.xcodeproj" \
  -scheme Rectangle \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  build -quiet; then
  echo "Build failed. Re-running with full output:"
  xcodebuild -project "$SCRIPT_DIR/Rectangle.xcodeproj" \
    -scheme Rectangle \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    build
  exit 1
fi

# Quit Rectangle if running
WAS_RUNNING=false
if pgrep -xq Rectangle; then
  WAS_RUNNING=true
  echo "Quitting Rectangle..."
  osascript -e 'tell application "Rectangle" to quit' 2>/dev/null || true
  sleep 1
  # Force kill if it didn't quit gracefully
  pkill -x Rectangle 2>/dev/null || true
fi

rm -rf /Applications/Rectangle.app
cp -R "$BUILD_DIR/Build/Products/Debug/Rectangle.app" /Applications/
echo "✓ Installed Rectangle.app to /Applications"

if $WAS_RUNNING; then
  open /Applications/Rectangle.app
  echo "✓ Relaunched Rectangle"
fi
