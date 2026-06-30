#!/bin/zsh
set -euo pipefail

APP_NAME="PDFold"
BUNDLE_ID="com.ud.PDFold"
INSTALL_CACHE="$HOME/.pdfold"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME.command"
DESKTOP_UNINSTALLER="$HOME/Desktop/Uninstall $APP_NAME.command"
LEGACY_DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME"
LEGACY_DESKTOP_UPDATER="$HOME/Desktop/Update $APP_NAME.command"

KEEP_USER_DATA=0

usage() {
    cat <<USAGE
PDFold uninstaller

Usage:
  scripts/uninstall-mac.sh [options]

Options:
  --keep-user-data  Keep PDFold app support, preferences, caches, and sandbox data.
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
        rm -rf "$path"
        print_note "Removed $path"
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

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
    print_step "Closing $APP_NAME"
    /usr/bin/osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    for _ in {1..20}; do
        pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

print_step "Removing installed app and commands"
remove_path "$INSTALLED_APP"
remove_path "$DESKTOP_LAUNCHER"
remove_path "$LEGACY_DESKTOP_LAUNCHER"
remove_path "$LEGACY_DESKTOP_UPDATER"
remove_path "$DESKTOP_UNINSTALLER"
remove_path "$INSTALL_CACHE"

if [[ $KEEP_USER_DATA -eq 0 ]]; then
    print_step "Removing PDFold app data"
    remove_path "$HOME/Library/Application Support/$APP_NAME"
    remove_path "$HOME/Library/Containers/$BUNDLE_ID"
    remove_path "$HOME/Library/Preferences/$BUNDLE_ID.plist"
    remove_path "$HOME/Library/Caches/$BUNDLE_ID"
    remove_path "$HOME/Library/Saved Application State/$BUNDLE_ID.savedState"
else
    print_step "Keeping PDFold app data"
fi

cat <<MESSAGE

$APP_NAME has been uninstalled.

Saved .pdfoldproj workspace files were not removed.
MESSAGE
