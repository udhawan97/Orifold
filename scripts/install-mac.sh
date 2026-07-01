#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="pdFold"
LEGACY_APP_NAME="PDFold"
REPO="udhawan97/PDFold"
RELEASE_TAG="release-v3"
CONFIGURATION="release"
OPEN_AFTER_INSTALL=1
CLEAN_BUILD=0
PREBUILT_ONLY=0
VERBOSE=0
PACKAGE_PATH=""
PACKAGE_ONLY=0

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ ! -f "$PROJECT_ROOT/Package.swift" ]]; then
    PROJECT_ROOT="$SCRIPT_DIR"
fi
SOURCE_AVAILABLE=0
[[ -f "$PROJECT_ROOT/Package.swift" ]] && SOURCE_AVAILABLE=1
BUILD_DIR="$PROJECT_ROOT/.build"
LOG_FILE="$BUILD_DIR/install.log"
STAGE_ROOT="${TMPDIR:-/tmp}/pdfold-install-$$"
STAGED_APP="$STAGE_ROOT/$APP_NAME.app"
INSTALL_DIR="$HOME/Applications"
INSTALLED_APP="$INSTALL_DIR/$APP_NAME.app"
LEGACY_INSTALLED_APP="$INSTALL_DIR/$LEGACY_APP_NAME.app"
DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME.command"
DESKTOP_UNINSTALLER="$HOME/Desktop/Uninstall $APP_NAME.command"
LEGACY_DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME"
LEGACY_DESKTOP_UPDATER="$HOME/Desktop/Update $APP_NAME.command"
OLD_DESKTOP_LAUNCHER="$HOME/Desktop/$LEGACY_APP_NAME.command"
OLD_DESKTOP_UNINSTALLER="$HOME/Desktop/Uninstall $LEGACY_APP_NAME.command"
OLD_LEGACY_DESKTOP_LAUNCHER="$HOME/Desktop/$LEGACY_APP_NAME"
OLD_LEGACY_DESKTOP_UPDATER="$HOME/Desktop/Update $LEGACY_APP_NAME.command"
RELEASE_API="https://api.github.com/repos/$REPO/releases/tags/$RELEASE_TAG"

usage() {
    cat <<USAGE
pdFold installer

Usage:
  scripts/install-mac.sh [options]

Options:
  --clean          Remove local SwiftPM build output before building.
  --no-open        Install/update without launching afterward.
  --prebuilt-only  Install only from the v3 GitHub release.
  --verbose        Print detailed install diagnostics to the console.
  --package PATH   Build and write a distributable zip to PATH.
  --package-only   With --package, build the zip without installing locally.
  --help           Show this help.

Re-running this script updates pdFold.
USAGE
}

print_step() {
    printf "\n==> %s\n" "$1"
    [[ -n "${LOG_FILE:-}" ]] && printf "\n==> %s\n" "$1" >>"$LOG_FILE"
}

print_note() {
    printf "    %s\n" "$1"
    [[ -n "${LOG_FILE:-}" ]] && printf "    %s\n" "$1" >>"$LOG_FILE"
}

print_debug() {
    [[ $VERBOSE -eq 1 ]] || return 0
    printf "    [debug] %s\n" "$1"
    [[ -n "${LOG_FILE:-}" ]] && printf "    [debug] %s\n" "$1" >>"$LOG_FILE"
}

fail() {
    printf "\nInstall failed: %s\n" "$1" >&2
    printf "Log: %s\n" "$LOG_FILE" >&2
    if [[ -f "$LOG_FILE" ]]; then
        printf "\nLast log lines:\n" >&2
        tail -n 40 "$LOG_FILE" >&2 || true
    fi
    cleanup
    exit 1
}

cleanup() {
    [[ -n "${STAGE_ROOT:-}" && -d "$STAGE_ROOT" ]] && /bin/rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean)
            CLEAN_BUILD=1
            ;;
        --no-open)
            OPEN_AFTER_INSTALL=0
            ;;
        --prebuilt-only)
            PREBUILT_ONLY=1
            ;;
        --verbose)
            VERBOSE=1
            ;;
        --package)
            shift
            [[ $# -gt 0 ]] || fail "--package requires a path."
            PACKAGE_PATH="$1"
            ;;
        --package-only)
            PACKAGE_ONLY=1
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

[[ "$(uname -s)" == "Darwin" ]] || fail "$APP_NAME only runs on macOS."

/bin/mkdir -p "$BUILD_DIR" "$STAGE_ROOT"
cat > "$LOG_FILE" <<LOG
pdFold install log
Project: $PROJECT_ROOT
Started: $(date)
macOS: $(sw_vers -productVersion 2>/dev/null || printf "unknown")
Architecture: $(uname -m)
Verbose: $VERBOSE
LOG

latest_release_zip_url() {
    print_debug "Checking release API: $RELEASE_API"
    /usr/bin/python3 - "$RELEASE_API" "$LOG_FILE" "$APP_NAME.zip" <<'PY'
import json
import sys
import urllib.request

url = sys.argv[1]
log_file = sys.argv[2]
asset_name = sys.argv[3]
try:
    with urllib.request.urlopen(url, timeout=20) as response:
        data = json.load(response)
except Exception as error:
    with open(log_file, "a", encoding="utf-8") as log:
        log.write(f"Release lookup failed: {error}\n")
    sys.exit(1)

for asset in data.get("assets", []):
    if asset.get("name") == asset_name and asset.get("browser_download_url"):
        print(asset["browser_download_url"])
        sys.exit(0)
with open(log_file, "a", encoding="utf-8") as log:
    available = ", ".join(asset.get("name", "<unnamed>") for asset in data.get("assets", [])) or "none"
    log.write(f"No {asset_name} asset found. Available assets: {available}\n")
sys.exit(1)
PY
}

verify_required_frameworks() {
    local app_path="$1"
    local executable="$app_path/Contents/MacOS/$APP_NAME"
    local missing=0

    [[ -x "$executable" ]] || fail "The app executable is missing or not executable: $executable"

    print_debug "Checking dynamic libraries for $executable"
    if otool -L "$executable" | grep -q '@rpath/PDFium.framework/PDFium'; then
        if [[ ! -e "$app_path/Contents/Frameworks/PDFium.framework/PDFium" ]]; then
            printf "Missing required framework: %s\n" "$app_path/Contents/Frameworks/PDFium.framework/PDFium" >>"$LOG_FILE"
            missing=1
        fi
    fi

    [[ $missing -eq 0 ]] || fail "$APP_NAME was built, but a required embedded framework is missing."
}

verify_app_bundle() {
    local app_path="$1"
    print_step "Verifying app bundle"
    verify_required_frameworks "$app_path"
    codesign --verify --deep --strict "$app_path" >>"$LOG_FILE" 2>&1 || fail "The installed app signature could not be verified."
}

capture_launch_diagnostics() {
    print_note "Capturing recent macOS launch diagnostics in the install log."
    /usr/bin/log show \
        --predicate "process == '$APP_NAME' OR eventMessage CONTAINS[c] '$APP_NAME' OR eventMessage CONTAINS[c] 'PDFium'" \
        --last 2m \
        --style compact >>"$LOG_FILE" 2>&1 || true
}

install_staged_app() {
    [[ -d "$STAGED_APP" ]] || fail "No staged app bundle was prepared."

    if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        print_step "Closing the currently running app"
        /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
        for _ in {1..20}; do
            /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            /bin/sleep 0.25
        done
    fi

    print_step "Copying app to $INSTALLED_APP"
    /bin/mkdir -p "$INSTALL_DIR"
    /bin/rm -rf "$INSTALLED_APP" "$LEGACY_INSTALLED_APP"
    /usr/bin/ditto --norsrc "$STAGED_APP" "$INSTALLED_APP"
    /usr/bin/xattr -cr "$INSTALLED_APP" 2>/dev/null || true
    verify_app_bundle "$INSTALLED_APP"

    print_step "Refreshing Desktop commands"
    if [[ -d "$HOME/Desktop" ]]; then
        /bin/rm -f "$DESKTOP_LAUNCHER" "$LEGACY_DESKTOP_LAUNCHER" "$LEGACY_DESKTOP_UPDATER" \
            "$OLD_DESKTOP_LAUNCHER" "$OLD_DESKTOP_UNINSTALLER" "$OLD_LEGACY_DESKTOP_LAUNCHER" "$OLD_LEGACY_DESKTOP_UPDATER"
        cat > "$DESKTOP_LAUNCHER" <<'LAUNCHER'
#!/bin/zsh
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/install.sh | /bin/zsh
LAUNCHER
        chmod +x "$DESKTOP_LAUNCHER" 2>/dev/null || print_note "Could not make the Desktop launcher executable."
        cat > "$DESKTOP_UNINSTALLER" <<'UNINSTALLER'
#!/bin/zsh
set -euo pipefail
PATH="/usr/bin:/bin:/usr/sbin:/sbin"
/usr/bin/curl -fsSL https://raw.githubusercontent.com/udhawan97/PDFold/main/scripts/uninstall-mac.sh | /bin/zsh
UNINSTALLER
        chmod +x "$DESKTOP_UNINSTALLER" 2>/dev/null || print_note "Could not make the Desktop uninstaller executable."
    else
        print_note "Desktop folder not found, so the launcher and uninstaller were not created."
    fi

    if [[ $OPEN_AFTER_INSTALL -eq 1 ]]; then
        print_step "Opening $APP_NAME"
        open "$INSTALLED_APP" || fail "The app was installed, but macOS could not open it."
        /bin/sleep 1
        if ! /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
            capture_launch_diagnostics
            fail "$APP_NAME opened but did not remain running. Check the install log for recent macOS launch diagnostics."
        fi
    fi
}

install_prebuilt_release() {
    local zip_url zip_path unzip_dir found_app
    zip_url="$(latest_release_zip_url)" || return 1
    zip_path="$STAGE_ROOT/$APP_NAME.zip"
    unzip_dir="$STAGE_ROOT/prebuilt"

    print_step "Downloading prebuilt $APP_NAME"
    /usr/bin/curl -fL "$zip_url" -o "$zip_path" >>"$LOG_FILE" 2>&1 || return 1
    /bin/mkdir -p "$unzip_dir"
    /usr/bin/ditto -x -k "$zip_path" "$unzip_dir" >>"$LOG_FILE" 2>&1 || return 1
    found_app="$(find "$unzip_dir" -maxdepth 3 -name "$APP_NAME.app" -type d -print -quit)"
    [[ -n "$found_app" ]] || printf "Prebuilt zip did not contain %s.app\n" "$APP_NAME" >>"$LOG_FILE"
    [[ -n "$found_app" ]] || return 1
    /bin/rm -rf "$STAGED_APP"
    /usr/bin/ditto --norsrc "$found_app" "$STAGED_APP"
    /usr/bin/xattr -cr "$STAGED_APP" 2>/dev/null || true
    verify_app_bundle "$STAGED_APP"
    install_staged_app
    return 0
}

build_icon() {
    local source_dir iconset
    source_dir="$PROJECT_ROOT/PDFold/Resources/Assets.xcassets/AppIcon.appiconset"
    iconset="$STAGE_ROOT/AppIcon.iconset"
    /bin/mkdir -p "$iconset"

    cp "$source_dir/AppIcon-16.png" "$iconset/icon_16x16.png"
    cp "$source_dir/AppIcon-32.png" "$iconset/icon_16x16@2x.png"
    cp "$source_dir/AppIcon-32.png" "$iconset/icon_32x32.png"
    cp "$source_dir/AppIcon-64.png" "$iconset/icon_32x32@2x.png"
    cp "$source_dir/AppIcon-128.png" "$iconset/icon_128x128.png"
    cp "$source_dir/AppIcon-256.png" "$iconset/icon_128x128@2x.png"
    cp "$source_dir/AppIcon-256.png" "$iconset/icon_256x256.png"
    cp "$source_dir/AppIcon-512.png" "$iconset/icon_256x256@2x.png"
    cp "$source_dir/AppIcon-512.png" "$iconset/icon_512x512.png"
    cp "$source_dir/AppIcon-1024.png" "$iconset/icon_512x512@2x.png"
    /usr/bin/iconutil -c icns "$iconset" -o "$STAGED_APP/Contents/Resources/AppIcon.icns"
}

write_info_plist() {
    local plist
    plist="$STAGED_APP/Contents/Info.plist"
    cp "$PROJECT_ROOT/PDFold/Resources/Info.plist" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleDevelopmentRegion en" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable $APP_NAME" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.ud.PDFold" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleName $APP_NAME" "$plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$plist"
}

build_from_source() {
    command -v swift >/dev/null 2>&1 || fail "Swift was not found. Install Apple's free Command Line Tools, then run this again."
    command -v codesign >/dev/null 2>&1 || fail "codesign was not found. Install Apple's free Command Line Tools, then run this again."

    cd "$PROJECT_ROOT"

    if [[ $CLEAN_BUILD -eq 1 ]]; then
        print_step "Cleaning local SwiftPM build output"
        /bin/rm -rf "$PROJECT_ROOT/.build/release" "$PROJECT_ROOT/.build/checkouts" "$PROJECT_ROOT/.build/repositories"
    fi

    print_step "Building $APP_NAME with SwiftPM"
    print_debug "swift: $(command -v swift)"
    swift --version >>"$LOG_FILE" 2>&1 || true
    swift build -c "$CONFIGURATION" >>"$LOG_FILE" 2>&1 || fail "The SwiftPM build failed."

    local built_binary
    built_binary="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
    print_debug "Built binary: $built_binary"
    [[ -x "$built_binary" ]] || fail "Build completed, but the $APP_NAME executable was not created."

    print_step "Assembling app bundle"
    /bin/rm -rf "$STAGED_APP"
    /bin/mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Frameworks" "$STAGED_APP/Contents/Resources"
    cp "$built_binary" "$STAGED_APP/Contents/MacOS/$APP_NAME"
    if [[ -d "$(dirname "$built_binary")/PDFium.framework" ]]; then
        print_debug "Embedding PDFium.framework"
        /usr/bin/ditto --norsrc "$(dirname "$built_binary")/PDFium.framework" "$STAGED_APP/Contents/Frameworks/PDFium.framework"
        install_name_tool -add_rpath "@executable_path/../Frameworks" "$STAGED_APP/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    elif otool -L "$built_binary" | grep -q '@rpath/PDFium.framework/PDFium'; then
        fail "Build completed, but PDFium.framework was not found next to the SwiftPM binary."
    fi
    write_info_plist
    build_icon
    cp "$PROJECT_ROOT/PDFold/Resources/PDFold.entitlements" "$STAGED_APP/Contents/Resources/PDFold.entitlements"
    /usr/bin/xattr -cr "$STAGED_APP" 2>/dev/null || true
    verify_required_frameworks "$STAGED_APP"

    print_step "Signing app bundle"
    codesign --force --deep --sign - --entitlements "$PROJECT_ROOT/PDFold/Resources/PDFold.entitlements" "$STAGED_APP" >>"$LOG_FILE" 2>&1 || fail "Could not sign the app."
    codesign --verify --deep --strict "$STAGED_APP" >>"$LOG_FILE" 2>&1 || fail "The app signature could not be verified."
}

write_package() {
    local package_dir package_abs
    [[ -n "$PACKAGE_PATH" ]] || return 0
    package_dir="$(cd "$(dirname "$PACKAGE_PATH")" && pwd)"
    package_abs="$package_dir/$(basename "$PACKAGE_PATH")"
    print_step "Writing release zip"
    /bin/rm -f "$package_abs"
    (cd "$STAGE_ROOT" && /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_NAME.app" "$package_abs")
    print_note "Package: $package_abs"
}

if [[ -z "$PACKAGE_PATH" && ( $PREBUILT_ONLY -eq 1 || $SOURCE_AVAILABLE -eq 0 ) ]]; then
    if install_prebuilt_release; then
        cat <<MESSAGE

$APP_NAME is ready.

App:     $INSTALLED_APP
Desktop: $DESKTOP_LAUNCHER
Remove:  $DESKTOP_UNINSTALLER
Log:     $LOG_FILE
MESSAGE
        exit 0
    fi

    if [[ $PREBUILT_ONLY -eq 1 ]]; then
        fail "No prebuilt GitHub release asset named $APP_NAME.zip is available for $RELEASE_TAG yet."
    fi

    print_note "No prebuilt release was available. Building from source instead."
fi

if [[ $SOURCE_AVAILABLE -eq 0 ]]; then
    fail "No source checkout was found for the fallback build."
fi

build_from_source
write_package

if [[ $PACKAGE_ONLY -eq 0 ]]; then
    install_staged_app
fi

if [[ $PACKAGE_ONLY -eq 1 ]]; then
    cat <<MESSAGE

$APP_NAME package is ready.

Package: $PACKAGE_PATH
Log:     $LOG_FILE
MESSAGE
else
    cat <<MESSAGE

$APP_NAME is ready.

App:     $INSTALLED_APP
Desktop: $DESKTOP_LAUNCHER
Remove:  $DESKTOP_UNINSTALLER
Log:     $LOG_FILE
MESSAGE
fi
