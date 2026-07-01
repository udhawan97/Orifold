#!/bin/zsh -f
set -u

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="pdFold"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
UNINSTALLER="$SCRIPT_DIR/scripts/uninstall-mac.sh"

printf "\033]0;%s Uninstaller\007" "$APP_NAME"
printf "\n"
printf "%s Uninstaller\n" "$APP_NAME"
printf "=================\n\n"

if [[ ! -f "$UNINSTALLER" ]]; then
    printf "Could not find the uninstaller script:\n%s\n\n" "$UNINSTALLER" >&2
    printf "Press Return to close this window.\n"
    read -r
    exit 1
fi

if [[ ! -x "$UNINSTALLER" ]]; then
    chmod +x "$UNINSTALLER" 2>/dev/null || true
fi

/bin/zsh -f "$UNINSTALLER"
STATUS=$?

printf "\n"
if [[ $STATUS -eq 0 ]]; then
    printf "%s has been uninstalled. This window will close automatically.\n" "$APP_NAME"
    exit 0
fi

printf "Uninstall did not finish.\n\n" >&2
printf "Press Return to close this window.\n"
read -r
exit "$STATUS"
