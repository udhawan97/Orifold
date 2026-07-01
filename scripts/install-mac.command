#!/bin/zsh -f
set -u

APP_NAME="pdFold"
SCRIPT_DIR="$(cd -- "$(dirname -- "$0")" && pwd)"
PROJECT_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
INSTALLER="$SCRIPT_DIR/install-mac.sh"
LOG_FILE="$PROJECT_ROOT/.build/install.log"

printf "\033]0;%s Installer\007" "$APP_NAME"
printf "\n"
printf "%s Installer / Updater\n" "$APP_NAME"
printf "==========================\n\n"
printf "Project: %s\n" "$PROJECT_ROOT"
printf "Log:     %s\n\n" "$LOG_FILE"

if [[ ! -f "$INSTALLER" ]]; then
    printf "Could not find the installer script:\n%s\n\n" "$INSTALLER" >&2
    printf "Press Return to close this window.\n"
    read -r
    exit 1
fi

if [[ ! -x "$INSTALLER" ]]; then
    chmod +x "$INSTALLER" 2>/dev/null || true
fi

/bin/zsh -f "$INSTALLER"
STATUS=$?

printf "\n"
if [[ $STATUS -eq 0 ]]; then
    printf "%s is ready.\n" "$APP_NAME"
    printf "The app should be open now. This window will close automatically.\n"
    exit 0
fi

printf "Setup did not finish.\n" >&2
printf "Check the log for details:\n%s\n\n" "$LOG_FILE" >&2
printf "Press Return to close this window.\n"
read -r
exit "$STATUS"
