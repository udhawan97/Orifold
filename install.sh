#!/bin/zsh
set -euo pipefail

PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="Orifold"
REPO="udhawan97/Orifold"
RAW_BASE="https://raw.githubusercontent.com/$REPO/main"
WORK_DIR="$HOME/.orifold"
SRC_DIR="$WORK_DIR/src"
INSTALLER="$SRC_DIR/scripts/install-mac.sh"
VERBOSE="${ORIFOLD_INSTALL_VERBOSE:-0}"
ALLOW_SOURCE_BUILD="${ORIFOLD_ALLOW_SOURCE_BUILD:-0}"

print_step() {
    printf "\n==> %s\n" "$1"
}

print_note() {
    printf "    %s\n" "$1"
}

print_debug() {
    [[ "$VERBOSE" == "1" ]] || return 0
    printf "    [debug] %s\n" "$1"
}

fail() {
    printf "\nInstall failed: %s\n" "$1" >&2
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "$APP_NAME only runs on macOS."

/bin/mkdir -p "$WORK_DIR"

print_step "Installing or updating $APP_NAME"
print_note "Trying the prebuilt app first. No Xcode or Command Line Tools needed."
print_debug "Set ORIFOLD_ALLOW_SOURCE_BUILD=1 to permit a developer source build fallback."

REMOTE_INSTALLER="$WORK_DIR/install-mac.sh"
PREBUILT_LOG="$WORK_DIR/prebuilt-install.log"
if /usr/bin/curl -fsSL "$RAW_BASE/scripts/install-mac.sh" -o "$REMOTE_INSTALLER"; then
    chmod +x "$REMOTE_INSTALLER" 2>/dev/null || true
    installer_args=(--prebuilt-only)
    [[ "$VERBOSE" == "1" ]] && installer_args+=(--verbose)
    if /bin/zsh "$REMOTE_INSTALLER" "${installer_args[@]}" >"$PREBUILT_LOG" 2>&1; then
        cat "$PREBUILT_LOG"
        exit 0
    fi
    print_note "The prebuilt app was not available."
    print_note "Prebuilt attempt log: $PREBUILT_LOG"
    if [[ "$VERBOSE" == "1" ]]; then
        tail -n 60 "$PREBUILT_LOG" 2>/dev/null || true
    fi
else
    print_note "Could not download the remote installer."
fi

if [[ "$ALLOW_SOURCE_BUILD" != "1" ]]; then
    fail "No prebuilt Orifold release could be installed. The maintainer needs to publish a GitHub release asset named Orifold.zip. Developer source builds can opt in with ORIFOLD_ALLOW_SOURCE_BUILD=1."
fi

print_note "Developer source build fallback enabled."

if ! command -v swift >/dev/null 2>&1; then
    print_step "Apple Command Line Tools are needed for the fallback build"
    print_note "macOS will show Apple's installer. When it finishes, paste the one-line command again."
    xcode-select --install >/dev/null 2>&1 || true
    exit 1
fi

print_step "Downloading source"
/bin/rm -rf "$SRC_DIR"
/bin/mkdir -p "$SRC_DIR"

if command -v git >/dev/null 2>&1; then
    git clone --depth 1 "https://github.com/$REPO.git" "$SRC_DIR"
else
    TARBALL="$WORK_DIR/source.tar.gz"
    /usr/bin/curl -fsSL "https://codeload.github.com/$REPO/tar.gz/refs/heads/main" -o "$TARBALL"
    /usr/bin/tar -xzf "$TARBALL" -C "$WORK_DIR"
    if [[ -d "$WORK_DIR/Orifold-main" ]]; then
        mv "$WORK_DIR/Orifold-main" "$SRC_DIR"
    else
        fail "Source archive did not contain Orifold-main."
    fi
fi

[[ -f "$INSTALLER" ]] || fail "Source downloaded, but the installer was not found."
chmod +x "$INSTALLER" 2>/dev/null || true
installer_args=()
[[ "$VERBOSE" == "1" ]] && installer_args+=(--verbose)
exec /bin/zsh "$INSTALLER" "${installer_args[@]}"
