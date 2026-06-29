#!/bin/zsh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$SCRIPT_DIR/scripts/install-mac.sh"

clear
printf "PDFold Installer / Updater\n"
printf "==========================\n\n"
printf "This will build PDFold locally, install it to ~/Applications,\n"
printf "refresh the Desktop launcher, and open the app when done.\n\n"

if [[ ! -x "$INSTALLER" ]]; then
    chmod +x "$INSTALLER" 2>/dev/null || true
fi

"$INSTALLER"
STATUS=$?

printf "\n"
if [[ $STATUS -eq 0 ]]; then
    printf "Done. PDFold is ready.\n"
else
    printf "Setup did not finish. The installer printed the log path above.\n"
fi

printf "This window will close automatically.\n"
sleep 1
exit $STATUS
