#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="pdFold"
LEGACY_APP_NAME="PDFold"
BUNDLE_ID="com.ud.PDFold"
INSTALL_CACHE="$HOME/.pdfold"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
LEGACY_INSTALLED_APP="$HOME/Applications/$LEGACY_APP_NAME.app"
DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME.command"
DESKTOP_UNINSTALLER="$HOME/Desktop/Uninstall $APP_NAME.command"
LEGACY_DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME"
LEGACY_DESKTOP_UPDATER="$HOME/Desktop/Update $APP_NAME.command"
OLD_DESKTOP_LAUNCHER="$HOME/Desktop/$LEGACY_APP_NAME.command"
OLD_DESKTOP_UNINSTALLER="$HOME/Desktop/Uninstall $LEGACY_APP_NAME.command"
OLD_LEGACY_DESKTOP_LAUNCHER="$HOME/Desktop/$LEGACY_APP_NAME"
OLD_LEGACY_DESKTOP_UPDATER="$HOME/Desktop/Update $LEGACY_APP_NAME.command"

KEEP_USER_DATA=0
REMOVE_ERRORS=()

usage() {
    cat <<USAGE
pdFold uninstaller

Usage:
  scripts/uninstall-mac.sh [options]

Options:
  --keep-user-data  Keep pdFold app support, preferences, caches, and sandbox data.
  --help            Show this help.

Saved .pdfoldproj workspace files are not removed.
USAGE
}

print_step() {
    printf "\n==> %s\n" "$1"
}

print_note() {
    printf "    %s\n" "$1"
}

remove_path() {
    local path="$1"
    [[ -n "$path" && "$path" != "/" ]] || return 0
    if [[ -e "$path" || -L "$path" ]]; then
        if /bin/rm -rf "$path" 2>/dev/null; then
            print_note "Removed $path"
            return 0
        fi

        /usr/bin/osascript - "$path" >/dev/null 2>&1 <<'APPLESCRIPT' || true
on run argv
    tell application "Finder" to delete POSIX file (item 1 of argv)
end run
APPLESCRIPT

        if [[ ! -e "$path" && ! -L "$path" ]]; then
            print_note "Removed $path"
        else
            REMOVE_ERRORS+=("$path")
            print_note "Could not remove $path"
        fi
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --keep-user-data)
            KEEP_USER_DATA=1
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            printf "Uninstall failed: unknown option: %s\n" "$1" >&2
            exit 1
            ;;
    esac
    shift
done

[[ "$(uname -s)" == "Darwin" ]] || {
    printf "Uninstall failed: %s only runs on macOS.\n" "$APP_NAME" >&2
    exit 1
}

printf "%s Uninstaller\n" "$APP_NAME"
printf "=================\n"

if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    print_step "Closing $APP_NAME"
    /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        /bin/sleep 0.25
    done
    if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        /usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
        for _ in {1..20}; do
            /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
            /bin/sleep 0.25
        done
    fi
    if /usr/bin/pgrep -x "$APP_NAME" >/dev/null 2>&1; then
        /usr/bin/pkill -9 -x "$APP_NAME" >/dev/null 2>&1 || true
    fi
fi

print_step "Removing installed app and commands"
remove_path "$INSTALLED_APP"
remove_path "$LEGACY_INSTALLED_APP"
remove_path "$DESKTOP_LAUNCHER"
remove_path "$LEGACY_DESKTOP_LAUNCHER"
remove_path "$LEGACY_DESKTOP_UPDATER"
remove_path "$DESKTOP_UNINSTALLER"
remove_path "$OLD_DESKTOP_LAUNCHER"
remove_path "$OLD_DESKTOP_UNINSTALLER"
remove_path "$OLD_LEGACY_DESKTOP_LAUNCHER"
remove_path "$OLD_LEGACY_DESKTOP_UPDATER"
remove_path "$INSTALL_CACHE"

if [[ $KEEP_USER_DATA -eq 0 ]]; then
    print_step "Removing pdFold app data"
    remove_path "$HOME/Library/Application Support/$APP_NAME"
    remove_path "$HOME/Library/Application Support/$LEGACY_APP_NAME"
    remove_path "$HOME/Library/Containers/$BUNDLE_ID"
    remove_path "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    remove_path "$HOME/Library/Caches/$BUNDLE_ID"
    remove_path "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
else
    print_step "Keeping pdFold app data"
fi

if [[ ${#REMOVE_ERRORS[@]} -gt 0 ]]; then
    printf "\n%s install artifacts were removed, but some app data is protected by macOS and could not be removed automatically:\n" "$APP_NAME" >&2
    for path in "${REMOVE_ERRORS[@]}"; do
        printf "  %s\n" "$path" >&2
    done
    printf "\nSaved .pdfoldproj workspace files were not removed.\n" >&2
    printf "Remove those paths from Finder, or grant Terminal Full Disk Access and run this uninstaller again.\n" >&2
    exit 1
fi

cat <<MESSAGE

$APP_NAME has been uninstalled.

Saved .pdfoldproj workspace files were not removed.
MESSAGE
