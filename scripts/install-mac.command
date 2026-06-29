#!/bin/zsh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

clear
printf "PDFold Installer / Updater\n"
printf "==========================\n"
printf "\nTip: you can also double-click \"Install or Update PDFold.command\" in the project root.\n\n"

"$SCRIPT_DIR/install-mac.sh"
STATUS=$?

printf "\n"
if [[ $STATUS -eq 0 ]]; then
    printf "Done. This window will close automatically.\n"
else
    printf "Something went sideways. This window will close automatically.\n"
fi

sleep 1
exit $STATUS
