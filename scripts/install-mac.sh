#!/bin/zsh
set -euo pipefail

APP_NAME="PDFold"
PROJECT_FILE="PDFold.xcodeproj"
SCHEME="PDFold"
CONFIGURATION="Release"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/.build/xcode"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
DESKTOP_ALIAS="$HOME/Desktop/$APP_NAME"

print_step() {
    printf "\n%s\n" "$1"
}

fail() {
    printf "\nInstall failed: %s\n" "$1" >&2
    exit 1
}

command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is required, but xcodebuild was not found."

cd "$PROJECT_ROOT"

print_step "Building $APP_NAME..."
xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build

[[ -d "$BUILT_APP" ]] || fail "Build completed, but $BUILT_APP was not created."

print_step "Preparing local app signature..."
xattr -cr "$BUILT_APP"
codesign --force --deep --sign - "$BUILT_APP" >/dev/null
codesign --verify --deep --strict "$BUILT_APP"

print_step "Installing to $INSTALLED_APP..."
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto "$BUILT_APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"

print_step "Creating Desktop launcher..."
rm -f "$DESKTOP_ALIAS"
/usr/bin/osascript <<APPLESCRIPT
tell application "Finder"
    set appFile to POSIX file "$INSTALLED_APP" as alias
    set desktopFolder to path to desktop folder
    make new alias file at desktopFolder to appFile with properties {name:"$APP_NAME"}
end tell
APPLESCRIPT

print_step "Opening $APP_NAME..."
open "$INSTALLED_APP"

cat <<MESSAGE

PDFold is installed.

App:     $INSTALLED_APP
Desktop: $DESKTOP_ALIAS

You can launch it from the Desktop icon any time. The papers have been folded. Tastefully.
MESSAGE
