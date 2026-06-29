#!/bin/zsh
set -euo pipefail

APP_NAME="PDFold"
PROJECT_FILE="PDFold.xcodeproj"
SCHEME="PDFold"
CONFIGURATION="Release"
OPEN_AFTER_INSTALL=1
CLEAN_BUILD=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="$PROJECT_ROOT/.build/xcode"
LOG_FILE="$PROJECT_ROOT/.build/install.log"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
STAGED_APP="$PROJECT_ROOT/.build/stage/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
DESKTOP_ALIAS="$HOME/Desktop/$APP_NAME"

usage() {
    cat <<USAGE
PDFold local installer

Usage:
  scripts/install-mac.sh [options]

Options:
  --clean      Remove the local build folder before building.
  --no-open    Install/update the app without launching it afterward.
  --help       Show this help.

Run this script again any time to update PDFold after pulling new code.
USAGE
}

print_step() {
    printf "\n==> %s\n" "$1"
}

print_note() {
    printf "    %s\n" "$1"
}

fail() {
    printf "\nInstall failed: %s\n" "$1" >&2
    printf "Log: %s\n" "$LOG_FILE" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=1
            ;;
        --no-open)
            OPEN_AFTER_INSTALL=0
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "Unknown option: $1"
            ;;
    esac
    shift
done

mkdir -p "$PROJECT_ROOT/.build"

command -v xcodebuild >/dev/null 2>&1 || fail "Xcode is required. Install Xcode from the Mac App Store, open it once, then run this again."
command -v codesign >/dev/null 2>&1 || fail "codesign was not found. Xcode command line tools may need to finish installing."

if ! xcodebuild -version >/dev/null 2>&1; then
    fail "xcodebuild is not ready. Open Xcode once and accept any license or setup prompts, then run this again."
fi

cd "$PROJECT_ROOT"

cat > "$LOG_FILE" <<LOG
PDFold install log
Project: $PROJECT_ROOT
Started: $(date)
LOG

if [[ $CLEAN_BUILD -eq 1 ]]; then
    print_step "Cleaning local build folder"
    rm -rf "$DERIVED_DATA_PATH"
fi

if [[ -d "$INSTALLED_APP" ]]; then
    print_step "Updating $APP_NAME"
else
    print_step "Installing $APP_NAME"
fi

print_note "Building the app locally with Xcode..."
if ! xcodebuild \
    -project "$PROJECT_FILE" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    build 2>&1 | tee -a "$LOG_FILE"; then
    fail "The Xcode build failed. The log above usually has the useful bit."
fi

[[ -d "$BUILT_APP" ]] || fail "Build completed, but $BUILT_APP was not created."

print_step "Preparing clean app bundle"
rm -rf "$PROJECT_ROOT/.build/stage"
mkdir -p "$PROJECT_ROOT/.build/stage"
ditto --norsrc "$BUILT_APP" "$STAGED_APP"
xattr -cr "$STAGED_APP" || true

print_step "Preparing local app signature"
codesign --force --deep --sign - "$STAGED_APP" >>"$LOG_FILE" 2>&1 || fail "Could not sign the local app build."
codesign --verify --deep --strict "$STAGED_APP" >>"$LOG_FILE" 2>&1 || fail "The local app signature could not be verified."

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    print_step "Closing the currently running app"
    /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

print_step "Copying app to $INSTALLED_APP"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALLED_APP"
ditto --norsrc "$STAGED_APP" "$INSTALLED_APP"
xattr -cr "$INSTALLED_APP"

if [[ $OPEN_AFTER_INSTALL -eq 1 ]]; then
    print_step "Opening $APP_NAME"
    open "$INSTALLED_APP" || fail "The app was installed, but macOS could not open it."
fi

print_step "Refreshing Desktop launcher"
if [[ -d "$HOME/Desktop" ]]; then
    rm -f "$DESKTOP_ALIAS"
    if ! ln -s "$INSTALLED_APP" "$DESKTOP_ALIAS" 2>>"$LOG_FILE"; then
        print_note "Could not refresh the Desktop launcher. You can still open the app from $INSTALLED_APP."
    fi
else
    print_note "Desktop folder not found, so no launcher was created."
fi

cat <<MESSAGE

PDFold is ready.

App:     $INSTALLED_APP
Desktop: $DESKTOP_ALIAS
Log:     $LOG_FILE

To update later, pull or download the latest code and run this installer again.
MESSAGE
