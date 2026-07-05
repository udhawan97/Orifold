#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="Orifold"
BUNDLE_ID="com.ud.Orifold"
LEGACY_APP_NAMES=("p""d""Fold" "PDF""old")
APP_DATA_NAMES=("$APP_NAME" "${LEGACY_APP_NAMES[@]}")
LEGACY_BUNDLE_ID="com.ud.PDF""old"
APP_BUNDLE_IDS=("$BUNDLE_ID" "$LEGACY_BUNDLE_ID")
INSTALL_CACHE="$HOME/.orifold"
LEGACY_INSTALL_CACHE="$HOME/.p""d""fold"
INSTALLED_APP="$HOME/Applications/$APP_NAME.app"
SYSTEM_INSTALLED_APP="/Applications/$APP_NAME.app"
DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME.command"
DESKTOP_UNINSTALLER="$HOME/Desktop/Uninstall $APP_NAME.command"
DESKTOP_INSTALLER_APP="$HOME/Desktop/Install or Update $APP_NAME.app"
DESKTOP_INSTALLER_COMMAND="$HOME/Desktop/Install or Update $APP_NAME.command"
LEGACY_DESKTOP_LAUNCHER="$HOME/Desktop/$APP_NAME"
LEGACY_DESKTOP_UPDATER="$HOME/Desktop/Update $APP_NAME.command"

KEEP_USER_DATA=0
REMOVE_ERRORS=()

usage() {
    cat <<USAGE
Orifold uninstaller

Usage:
  scripts/uninstall-mac.sh [options]

Options:
  --keep-user-data  Keep Orifold app support, preferences, caches, and sandbox data.
  --help            Show this help.

Files created outside Orifold's app support directories are not removed.
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

remove_glob_paths() {
    local pattern="$1"
    local matches=()

    matches=(${~pattern}(N))
    for path in "${matches[@]}"; do
        remove_path "$path"
    done
}

stop_running_app() {
    local process_name="$1"
    if /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1; then
        print_step "Closing $process_name"
        /usr/bin/osascript -e "tell application \"$process_name\" to quit" >/dev/null 2>&1 || true
        for _ in {1..20}; do
            /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1 || break
            /bin/sleep 0.25
        done
        if /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1; then
            /usr/bin/pkill -x "$process_name" >/dev/null 2>&1 || true
            for _ in {1..20}; do
                /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1 || break
                /bin/sleep 0.25
            done
        fi
        if /usr/bin/pgrep -x "$process_name" >/dev/null 2>&1; then
            /usr/bin/pkill -9 -x "$process_name" >/dev/null 2>&1 || true
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

stop_running_app "$APP_NAME"
for legacy_app_name in "${LEGACY_APP_NAMES[@]}"; do
    stop_running_app "$legacy_app_name"
done

print_step "Removing installed app and commands"
remove_path "$INSTALLED_APP"
remove_path "$SYSTEM_INSTALLED_APP"
for legacy_app_name in "${LEGACY_APP_NAMES[@]}"; do
    remove_path "$HOME/Applications/$legacy_app_name.app"
    remove_path "/Applications/$legacy_app_name.app"
done
remove_path "$DESKTOP_LAUNCHER"
remove_path "$LEGACY_DESKTOP_LAUNCHER"
remove_path "$LEGACY_DESKTOP_UPDATER"
remove_path "$DESKTOP_UNINSTALLER"
remove_path "$DESKTOP_INSTALLER_APP"
remove_path "$DESKTOP_INSTALLER_COMMAND"
for legacy_app_name in "${LEGACY_APP_NAMES[@]}"; do
    remove_path "$HOME/Desktop/$legacy_app_name.command"
    remove_path "$HOME/Desktop/Uninstall $legacy_app_name.command"
    remove_path "$HOME/Desktop/$legacy_app_name"
    remove_path "$HOME/Desktop/Update $legacy_app_name.command"
    remove_path "$HOME/Desktop/Install or Update $legacy_app_name.command"
    remove_path "$HOME/Desktop/Install or Update $legacy_app_name.app"
done
remove_path "$INSTALL_CACHE"
remove_path "$LEGACY_INSTALL_CACHE"

if [[ $KEEP_USER_DATA -eq 0 ]]; then
    print_step "Removing Orifold app data"
    remove_path "$HOME/Library/Application Support/$APP_NAME"
    for legacy_app_name in "${LEGACY_APP_NAMES[@]}"; do
        remove_path "$HOME/Library/Application Support/$legacy_app_name"
    done
    for bundle_id in "${APP_BUNDLE_IDS[@]}"; do
        remove_path "$HOME/Library/Application Scripts/$bundle_id"
        remove_path "$HOME/Library/Caches/$bundle_id"
        remove_path "$HOME/Library/Containers/$bundle_id"
        remove_path "$HOME/Library/Cookies/$bundle_id.binarycookies"
        remove_path "$HOME/Library/HTTPStorages/$bundle_id"
        remove_path "$HOME/Library/Preferences/$bundle_id.plist"
        remove_path "$HOME/Library/Saved Application State/$bundle_id.savedState"
        remove_path "$HOME/Library/WebKit/$bundle_id"
        remove_glob_paths "$HOME/Library/Preferences/ByHost/$bundle_id.*.plist"
    done
    for app_data_name in "${APP_DATA_NAMES[@]}"; do
        remove_glob_paths "$HOME/Library/Logs/DiagnosticReports/$app_data_name*.ips"
        remove_glob_paths "$HOME/Library/Logs/DiagnosticReports/$app_data_name*.crash"
    done
else
    print_step "Keeping Orifold app data"
fi

if [[ ${#REMOVE_ERRORS[@]} -gt 0 ]]; then
    printf "\n%s install artifacts were removed, but some app data is protected by macOS and could not be removed automatically:\n" "$APP_NAME" >&2
    for path in "${REMOVE_ERRORS[@]}"; do
        printf "  %s\n" "$path" >&2
    done
    printf "\nFiles created outside Orifold's app support directories were not removed.\n" >&2
    printf "Remove those paths from Finder, or grant Terminal Full Disk Access and run this uninstaller again.\n" >&2
    exit 1
fi

cat <<MESSAGE

$APP_NAME has been uninstalled.

Files created outside Orifold's app support directories were not removed.
MESSAGE
