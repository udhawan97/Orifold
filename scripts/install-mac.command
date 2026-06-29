#!/bin/zsh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

clear
printf "PDFold Mac Installer\n"
printf "====================\n"

"$SCRIPT_DIR/install-mac.sh"
STATUS=$?

printf "\n"
if [[ $STATUS -eq 0 ]]; then
    printf "Done. Press any key to close this window.\n"
else
    printf "Something went sideways. Press any key to close this window.\n"
fi

read -k 1 -s
exit $STATUS
