#!/data/data/com.termux/files/usr/bin/bash
################################################################################
# OpenClaw Android Installer - No PRoot / No Debian
# Version: 2026.10.20
# Description: Install OpenClaw directly inside Termux, without proot-distro
#              and without a Linux distribution. Uses the glibc dynamic linker
#              from Termux's glibc-runner package, official Node.js linux-arm64
#              and the Android compatibility patches from
#              https://github.com/AidanPark/openclaw-android
# Repository: https://github.com/anhkind/openclaw-android
################################################################################

set -e

# ------------------------------------------------------------------------------
# Script configuration
# ------------------------------------------------------------------------------
SCRIPT_VERSION="2026.10.20"
SCRIPT_URL="https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh"
VERSION_URL="https://raw.githubusercontent.com/anhkind/openclaw-android/main/VERSION"
REPO_URL="https://github.com/anhkind/openclaw-android"
REFERENCE_URL="https://github.com/AidanPark/openclaw-android"

# OpenClaw version verified against the embedded Android patches.
# Use --latest or --openclaw to override (patches may need updating).
OPENCLAW_VERIFIED_VERSION="2026.10.2"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-$OPENCLAW_VERIFIED_VERSION}"
OPENCLAW_PACKAGE="openclaw"

# Node.js line. OpenClaw supports >=24.16.0 <25 and >=26.1.0.
NODE_MAJOR="${OPENCLAW_NODE_MAJOR:-24}"
NODE_VERSION="${OPENCLAW_NODE_VERSION:-}"
NODE_VERSION="${NODE_VERSION#v}"

# No Debian/proot: OpenClaw + Node + glibc cache need roughly 1.5-2 GB.
MIN_STORAGE_MB=2048
RECOMMENDED_STORAGE_MB=4096

PROJECT_DIR="$HOME/.openclaw-android"
# Keep our generated helpers inside the runtime directory. Do not write into
# $HOME/.openclaw: that is OpenClaw's own state/configuration directory.
START_HELPER="$PROJECT_DIR/start-openclaw.sh"
UPDATE_HELPER="$PROJECT_DIR/update-claw.sh"
SELF_UPDATE_FILE="$PROJECT_DIR/install.sh.new"
BIN_DIR="$PROJECT_DIR/bin"
NODE_DIR="$PROJECT_DIR/node"
NODE_NEW="$PROJECT_DIR/node.new"
NODE_OLD="$PROJECT_DIR/node.old"
COMPAT_DIR="$PROJECT_DIR/lib"
COMPAT_FILE="$COMPAT_DIR/glibc-compat.js"
PATCH_DIR="$PROJECT_DIR/patches"
INSTALLER_COPY="$PROJECT_DIR/installer/install.sh"
GLIBC_LDSO="${PREFIX:-/data/data/com.termux/files/usr}/glibc/lib/ld-linux-aarch64.so.1"
BASHRC="$HOME/.bashrc"
BASHRC_START="# >>> openclaw-android (no-proot) >>>"
BASHRC_END="# <<< openclaw-android (no-proot) <<<"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${MAGENTA}==>${NC} ${CYAN}$1${NC}\n"; }

# ------------------------------------------------------------------------------
# Interactive helpers (work with curl | bash by reading /dev/tty)
# ------------------------------------------------------------------------------
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response=""

    if [ "$ASSUME_YES" = "true" ]; then
        return 0
    fi

    # -r only says the node is readable; opening it still fails without a
    # controlling terminal (cron, CI, `bash install.sh </dev/null`), which would
    # print a redirection error and silently take the default. Probe it first.
    if [ -r /dev/tty ] && { true < /dev/tty; } 2>/dev/null; then
        echo -e "${YELLOW}${prompt} (y/n)${NC}"
        read -r response < /dev/tty 2>/dev/null || response=""
    elif [ -t 0 ]; then
        echo -e "${YELLOW}${prompt} (y/n)${NC}"
        read -r response || response=""
    else
        log_warn "No interactive terminal available, using default: ${default}"
        response="$default"
    fi

    [ -z "$response" ] && response="$default"
    [[ "$response" =~ ^[Yy]$ ]]
}

# Return 0 if version $1 is greater than version $2 (dot-separated numbers)
version_gt() {
    local IFS=.
    local i v1 v2
    local -a ver1=($1)
    local -a ver2=($2)

    for ((i = 0; i < ${#ver1[@]} || i < ${#ver2[@]}; i++)); do
        v1="${ver1[i]:-0}"
        v2="${ver2[i]:-0}"
        if ((10#$v1 > 10#$v2)); then
            return 0
        elif ((10#$v1 < 10#$v2)); then
            return 1
        fi
    done
    return 1
}

show_banner() {
    clear 2>/dev/null || printf '\033c'
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║          OpenClaw for Android                 ║
    ║          No PRoot - No Debian                 ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "  Version: ${GREEN}${SCRIPT_VERSION}${NC}"
    echo -e "  Repository: ${BLUE}${REPO_URL}${NC}"
    echo -e "  Reference:  ${BLUE}${REFERENCE_URL}${NC}"
    echo -e ""
    echo -e "${YELLOW}  DISCLAIMER:${NC} Community installer. OpenClaw © its original creators."
    echo -e ""
}

# ------------------------------------------------------------------------------
# Update check
# ------------------------------------------------------------------------------
check_for_updates() {
    log_step "Checking for installer updates..."

    if ! command -v curl &> /dev/null; then
        log_warn "Unable to check for updates (curl not available)"
        return 0
    fi

    LATEST_VERSION=$(curl -fsSL --max-time 15 "$VERSION_URL" 2>/dev/null | head -1 | tr -d '[:space:]')

    if ! [[ "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        log_warn "Unable to check for updates (invalid version format received)"
        LATEST_VERSION="$SCRIPT_VERSION"
    fi
    [ -z "$LATEST_VERSION" ] && LATEST_VERSION="$SCRIPT_VERSION"

    if version_gt "$LATEST_VERSION" "$SCRIPT_VERSION"; then
        log_warn "New installer version available: $LATEST_VERSION (current: $SCRIPT_VERSION)"
        if ask_yes_no "Would you like to update the installer?" "n"; then
            log_info "Downloading latest installer..."
            mkdir -p "$PROJECT_DIR"
            if ! curl -fsSL --max-time 60 "$SCRIPT_URL" -o "$SELF_UPDATE_FILE"; then
                log_error "Failed to download the latest installer"
                rm -f "$SELF_UPDATE_FILE"
                log_info "Continuing with current version..."
            else
                # Re-exec only when the downloaded copy really is newer than the
                # running one. The VERSION file can be ahead of the published
                # script (one VERSION file serves both installers), and without
                # this check every run would download and exec the same script
                # forever - an endless loop when --yes answers the prompt.
                local downloaded_version
                downloaded_version=$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"$/\1/p' \
                    "$SELF_UPDATE_FILE" 2>/dev/null | head -1)

                if [ "${OPENCLAW_INSTALLER_UPDATED:-0}" = "1" ]; then
                    log_warn "Already restarted once with a downloaded installer - not restarting again"
                    rm -f "$SELF_UPDATE_FILE"
                elif [ -z "$downloaded_version" ] || \
                        ! version_gt "$downloaded_version" "$SCRIPT_VERSION"; then
                    log_warn "The published installer reports ${downloaded_version:-no version}, not newer than ${SCRIPT_VERSION}"
                    log_info "Continuing with the current installer (the repository VERSION file may be ahead of the published script)."
                    rm -f "$SELF_UPDATE_FILE"
                else
                    chmod +x "$SELF_UPDATE_FILE"
                    log_success "Installer updated to ${downloaded_version}! Restarting..."
                    export OPENCLAW_INSTALLER_UPDATED=1
                    exec "$SELF_UPDATE_FILE" "${SCRIPT_ARGS[@]}"
                fi
            fi
        else
            log_info "Continuing with current version..."
        fi
    else
        log_success "Installer is up to date!"
    fi
}

# ------------------------------------------------------------------------------
# Environment checks
# ------------------------------------------------------------------------------
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        log_error "This script must be run in Termux!"
        log_info "Install Termux from F-Droid: https://f-droid.org/en/packages/com.termux/"
        exit 1
    fi
    if [ -z "${PREFIX:-}" ]; then
        log_error "\$PREFIX is not set - this does not look like Termux."
        exit 1
    fi
    log_success "Termux environment detected (PREFIX=$PREFIX)"

    # Keep Android from suspending the install while packages are downloaded.
    if command -v termux-wake-lock &>/dev/null; then
        termux-wake-lock 2>/dev/null || true
        log_info "Wake lock enabled (use 'termux-wake-unlock' to release it)"
    fi
}

check_architecture() {
    log_step "Checking CPU architecture..."

    local arch
    arch="$(uname -m 2>/dev/null || echo unknown)"
    log_info "Architecture: $arch"

    case "$arch" in
        aarch64|arm64)
            log_success "64-bit ARM architecture supported"
            ;;
        armv7l|armv8l|arm|armhf|i686|i386)
            log_error "32-bit architecture detected ($arch)"
            log_error "The glibc loader and official Node.js builds need 64-bit ARM."
            log_info "Install 64-bit Termux (arm64 build) and retry:"
            log_info "  https://github.com/termux/termux-app/releases"
            exit 1
            ;;
        x86_64|amd64)
            log_error "x86_64 Termux is not supported by this installer."
            log_info "OpenClaw on Android targets arm64 phones (OnePlus 11 is arm64)."
            exit 1
            ;;
        *)
            log_error "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

check_android_version() {
    log_step "Checking Android version..."

    ANDROID_VERSION=$(getprop ro.build.version.release 2>/dev/null || echo "unknown")
    log_info "Android version: $ANDROID_VERSION"

    if [[ "$ANDROID_VERSION" =~ ^[0-9]+ ]] && [ "${ANDROID_VERSION%%.*}" -lt 12 ]; then
        log_warn "Android 12+ is recommended for best compatibility"
        if ! ask_yes_no "Continue anyway?" "n"; then
            log_info "Installation cancelled"
            exit 0
        fi
    else
        log_success "Android version compatible"
    fi
}

check_storage() {
    log_step "Checking available storage..."

    AVAILABLE_KB=$(df -Pk "$HOME" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ -z "$AVAILABLE_KB" ] || ! [[ "$AVAILABLE_KB" =~ ^[0-9]+$ ]]; then
        AVAILABLE_KB=$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')
    fi

    if [ -z "$AVAILABLE_KB" ] || ! [[ "$AVAILABLE_KB" =~ ^[0-9]+$ ]]; then
        log_warn "Unable to check available storage automatically"
        log_info "Please ensure you have at least ${MIN_STORAGE_MB}MB free (4GB+ recommended)"
        if ! ask_yes_no "Continue anyway?" "n"; then
            log_info "Installation cancelled"
            exit 0
        fi
        return 0
    fi

    AVAILABLE_MB=$((AVAILABLE_KB / 1024))
    log_info "Available storage: ${AVAILABLE_MB}MB"

    if [ "$AVAILABLE_MB" -lt "$MIN_STORAGE_MB" ]; then
        log_error "Insufficient storage! At least ${MIN_STORAGE_MB}MB required, ${AVAILABLE_MB}MB available"
        log_info "Free some space and try again"
        exit 1
    fi

    if [ "$AVAILABLE_MB" -lt "$RECOMMENDED_STORAGE_MB" ]; then
        log_warn "4GB+ recommended for a comfortable install (Node.js + OpenClaw)"
    fi

    log_success "Storage check passed"
}

check_existing_install() {
    log_step "Checking for an existing installation..."

    local proot_rootfs="$PREFIX/var/lib/proot-distro/installed-rootfs"

    # A no-PRoot install is updated in place, so it never prompts.
    if [ -d "$PROJECT_DIR/node" ]; then
        log_info "Existing no-PRoot installation found - it will be updated in place"
        return 0
    fi

    # The two modes are independent (no migration is provided). A Debian/PRoot
    # install would stay untouched but share OpenClaw's own ~/.openclaw state, so
    # ask before mixing the two.
    if [ -d "$proot_rootfs/debian" ]; then
        log_warn "A PRoot/Debian OpenClaw installation was found:"
        log_warn "  $proot_rootfs/debian"
        log_warn "This installer does not migrate or remove it. The Debian installation"
        log_warn "stays as it is, and both would share the ~/.openclaw configuration."
        if ! ask_yes_no "Continue with the no-PRoot installation?" "y"; then
            log_info "Installation cancelled - nothing was changed."
            exit 0
        fi
    else
        log_success "No existing installation found"
    fi
}

# ------------------------------------------------------------------------------
# Termux packages and glibc runtime
# ------------------------------------------------------------------------------
install_termux_packages() {
    log_step "Installing Termux packages..."

    if [ "$MODE" = "update" ] && command -v pacman &>/dev/null && command -v curl &>/dev/null; then
        log_info "Update mode: skipping full Termux package upgrade"
        return 0
    fi

    log_info "Updating package lists..."
    pkg update -y || log_warn "pkg update reported errors, continuing..."

    log_info "Upgrading existing packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" \
        || log_warn "apt-get upgrade reported errors, continuing..."

    # Nothing is compiled here: npm runs with --ignore-scripts and native builds
    # do not work on Android in this layout. So no git/python/make/cmake/clang
    # toolchain - it is several hundred MB that the install never uses. Install
    # it yourself if you know you need it.
    log_info "Installing required Termux packages..."
    pkg install -y \
        curl \
        tar \
        xz-utils \
        coreutils \
        pacman \
        || {
            log_error "Failed to install required Termux packages"
            exit 1
        }

    # Optional: provides $PREFIX/etc/resolv.conf. Without it, sync_glibc_resolv
    # falls back to the phone's own DNS servers.
    pkg install -y resolv-conf || log_warn "resolv-conf not installed (using the device DNS servers)"

    # Best effort for users who installed a C toolchain themselves: node-gyp
    # looks for a plain `ar`, while Termux ships llvm-ar.
    if [ ! -e "$PREFIX/bin/ar" ] && [ -x "$PREFIX/bin/llvm-ar" ]; then
        ln -s "$PREFIX/bin/llvm-ar" "$PREFIX/bin/ar" 2>/dev/null || true
    fi

    log_success "Termux packages installed"
}

install_glibc() {
    log_step "Installing glibc runtime (glibc-runner)..."

    local pacman_conf="$PREFIX/etc/pacman.conf"
    local verify_conf="$PREFIX/tmp/oa-pacman.conf"

    if [ ! -x "$GLIBC_LDSO" ]; then
        log_info "Installing pacman..."
        pkg install -y pacman || {
            log_error "Failed to install pacman"
            exit 1
        }

        if [ ! -f "$pacman_conf" ]; then
            log_error "pacman configuration not found: $pacman_conf"
            log_info "Run 'pkg reinstall pacman' and try again."
            exit 1
        fi

        # The keyring must exist before anything is installed from the pacman repo.
        local keyring_dir="$PREFIX/etc/pacman.d/gnupg"
        if [ ! -d "$keyring_dir" ] || [ -z "$(ls -A "$keyring_dir" 2>/dev/null)" ]; then
            log_info "Initializing pacman keyring (this can take a few minutes)..."
            local init_rc=0
            if command -v timeout &>/dev/null; then
                timeout 900 pacman-key --init 2>/dev/null || init_rc=$?
            else
                pacman-key --init 2>/dev/null || init_rc=$?
            fi
            if [ "$init_rc" -ne 0 ]; then
                # Do not leave a half-generated keyring that a later run would trust.
                rm -rf "$keyring_dir"
                log_error "Could not initialize the pacman keyring (exit code $init_rc)."
                log_info "Use the device for a minute (key generation needs entropy), then retry."
                exit 1
            fi
        fi
        # Idempotent: make sure the Termux signing keys are loaded even when the
        # keyring directory already existed.
        if ! pacman-key --populate; then
            log_error "Could not load the Termux signing keys (pacman-key --populate failed)."
            log_info "Run 'pkg reinstall pacman' and try again."
            exit 1
        fi

        # Termux ships "SigLevel = DatabaseRequired PackageOptional", i.e. the
        # database must be signed but packages may be unsigned. Require package
        # signatures too (the keyring above is populated for exactly that), even
        # when the user's pacman.conf relaxed them.
        mkdir -p "$PREFIX/tmp"
        local sig_level_re='^[[:space:]]*#?[[:space:]]*SigLevel[[:space:]]*='
        if ! grep -qE "$sig_level_re" "$pacman_conf"; then
            log_warn "No SigLevel line in $pacman_conf - packages may be installed unsigned"
        fi
        if ! sed -E "s|$sig_level_re.*|SigLevel = PackageRequired DatabaseRequired|" \
                "$pacman_conf" > "$verify_conf"; then
            log_error "Could not prepare the pacman configuration ($pacman_conf)"
            log_info "Run 'pkg reinstall pacman' and try again."
            exit 1
        fi
        if ! grep -q '^SigLevel = PackageRequired DatabaseRequired$' "$verify_conf"; then
            log_warn "Could not raise SigLevel in the pacman configuration - package signatures stay optional"
        fi

        # -Syu, not -Sy: glibc-runner and its glibc dependency live in a separate
        # prefix ($PREFIX/glibc), but installing the newest package from a freshly
        # synced database without upgrading the rest is the classic partial
        # upgrade that pacman is known to break on.
        # bash and resolv-conf are Termux (apt) packages; patchelf is only used by
        # `grun --setup`, which this installer does not use - it calls the loader
        # directly - so all three are assumed installed instead of pulled in.
        log_info "Installing glibc-runner..."
        if ! pacman --config "$verify_conf" -Syu --needed glibc-runner --noconfirm \
                --assume-installed bash,patchelf,resolv-conf; then
            rm -f "$verify_conf"
            log_error "Failed to install glibc-runner"
            log_info "Check your network and the device date/time, then retry."
            log_info "If it keeps failing, run 'pkg reinstall pacman' and try again."
            exit 1
        fi
        rm -f "$verify_conf"
    else
        log_success "glibc dynamic linker already present"
    fi

    if [ ! -x "$GLIBC_LDSO" ]; then
        log_error "glibc dynamic linker not found at $GLIBC_LDSO"
        exit 1
    fi

    # glibc getaddrinfo reads $PREFIX/glibc/etc/hosts for localhost.
    mkdir -p "$PREFIX/glibc/etc"
    if [ ! -f "$PREFIX/glibc/etc/hosts" ]; then
        cat > "$PREFIX/glibc/etc/hosts" << 'HOSTS'
127.0.0.1 localhost localhost.localdomain
::1 localhost ip6-localhost ip6-loopback
HOSTS
        log_success "Created glibc /etc/hosts"
    fi

    sync_glibc_resolv

    mkdir -p "$PROJECT_DIR"
    touch "$PROJECT_DIR/.glibc-arch"
    log_success "glibc runtime ready ($GLIBC_LDSO)"
}

sync_glibc_resolv() {
    # glibc resolves through $PREFIX/glibc/etc/resolv.conf (its compiled
    # sysconfdir). Android/Termux keep the (bionic) file at
    # $PREFIX/etc/resolv.conf, so without this copy glibc's getaddrinfo() has no
    # name servers at all and every resolver path outside the Node shim fails.
    local glibc_resolv="$PREFIX/glibc/etc/resolv.conf"
    local termux_resolv="$PREFIX/etc/resolv.conf"
    local tmp="$PREFIX/glibc/etc/.resolv.conf.new"

    mkdir -p "$PREFIX/glibc/etc"

    if [ -s "$termux_resolv" ]; then
        # Re-copy when the source is newer (a network change can rewrite it).
        if [ ! -s "$glibc_resolv" ] || [ "$termux_resolv" -nt "$glibc_resolv" ]; then
            if cp -f "$termux_resolv" "$tmp" 2>/dev/null && mv -f "$tmp" "$glibc_resolv"; then
                log_success "glibc resolver configuration updated"
            else
                rm -f "$tmp" 2>/dev/null || true
                log_warn "Could not write $glibc_resolv"
            fi
        fi
        return 0
    fi

    [ -s "$glibc_resolv" ] && return 0

    # The resolv-conf package is optional: fall back to the phone's own DNS
    # servers (Android properties), then to public resolvers.
    local servers=""
    if command -v getprop &>/dev/null; then
        servers=$(getprop 2>/dev/null \
            | sed -n 's/^\[net\.dns[1-4]\]: \[\(.*\)\]$/\1/p' \
            | grep -E '^[0-9A-Fa-f:.]+$' \
            | head -4 || true)
    fi
    [ -n "$servers" ] || servers=$(printf '8.8.8.8\n8.8.4.4')

    if printf '%s\n' "$servers" | sed 's/^/nameserver /' > "$tmp" 2>/dev/null && \
            mv -f "$tmp" "$glibc_resolv"; then
        log_success "Created glibc resolv.conf ($(printf '%s' "$servers" | tr '\n' ' '))"
    else
        rm -f "$tmp" 2>/dev/null || true
        log_warn "Could not create $glibc_resolv"
    fi
}

setup_environment() {
    export PATH="$BIN_DIR:$NODE_DIR/bin:$HOME/.local/bin:$PATH"
    export TMPDIR="$PREFIX/tmp"
    export TMP="$TMPDIR"
    export TEMP="$TMPDIR"
    # Only what OpenClaw actually reads (process.env.OPENCLAW_NO_AUTO_UPDATE).
    export OPENCLAW_NO_AUTO_UPDATE=1

    mkdir -p "$PREFIX/tmp" "$PROJECT_DIR" "$BIN_DIR" "$COMPAT_DIR" "$PATCH_DIR"
    mkdir -p "$PROJECT_DIR/installer"
}

# ------------------------------------------------------------------------------
# Embedded Android compatibility files
# ------------------------------------------------------------------------------
write_compat_shim() {
    log_step "Installing Android compatibility shim..."

    mkdir -p "$COMPAT_DIR" "$PATCH_DIR"
    cat > "$COMPAT_FILE" << 'GLIBC_COMPAT_JS'
/**
 * glibc-compat.js - Minimal compatibility shim for glibc Node.js on Android
 *
 * This is the successor to bionic-compat.js, drastically reduced for glibc.
 *
 * What's NOT needed anymore (glibc handles these):
 * - process.platform override (glibc Node.js reports 'linux' natively)
 * - renameat2 / spawn.h stubs (glibc includes them)
 * - CXXFLAGS / GYP_DEFINES overrides (glibc is standard Linux)
 *
 * What's still needed (kernel/Android-level restrictions, not libc):
 * - os.cpus() fallback: SELinux blocks /proc/stat on Android 8+
 * - os.networkInterfaces() safety: EACCES on some Android configurations
 * - /bin/sh path shim: Android 7-8 lacks /bin/sh (Android 9+ has it)
 *
 * Loaded via node wrapper script: node --require <path>/glibc-compat.js
 */

'use strict';

const os = require('os');
const fs = require('fs');
const path = require('path');

// ─── process.execPath fix ────────────────────────────────────
// When node runs via grun (ld.so node.real), process.execPath points to
// ld.so instead of the node wrapper. Apps that spawn child node processes
// using process.execPath (e.g., openclaw) will call ld.so directly,
// bypassing the wrapper's LD_PRELOAD unset and compat loading.
// Fix: point process.execPath to the wrapper script.

const _wrapperPath = process.env._OA_WRAPPER_PATH || path.join(
  process.env.HOME || '/data/data/com.termux/files/home',
  '.openclaw-android', 'bin', 'node'
);
try {
  if (fs.existsSync(_wrapperPath)) {
    Object.defineProperty(process, 'execPath', {
      value: _wrapperPath,
      writable: true,
      configurable: true,
    });
  }
} catch {}


// ─── LD_PRELOAD cleanup ─────────────────────────────────────
// The node wrapper unsets LD_PRELOAD to prevent bionic libtermux-exec.so
// from loading into the glibc node.real process.
//
// Previously, we restored LD_PRELOAD here so bionic child processes
// (like /bin/sh) would get libtermux-exec.so for path translation
// (e.g., /usr/bin/env → $PREFIX/bin/env in shebang resolution).
//
// However, libtermux-exec.so re-injects LD_PRELOAD into execve() calls
// even after the shell unsets it. This causes glibc processes (ld.so)
// spawned from node to crash with "Could not find a PHDR" errors.
//
// Fix: Do NOT restore LD_PRELOAD. Instead, the spawn/spawnSync wrapper
// below handles shebang resolution (#!/usr/bin/env → PATH lookup) in
// JavaScript, eliminating the need for libtermux-exec.so in child processes.

delete process.env.LD_PRELOAD;
delete process.env._OA_ORIG_LD_PRELOAD;


// ─── os.cpus() fallback ─────────────────────────────────────
// Android 8+ (API 26+) blocks /proc/stat via SELinux + hidepid=2.
// libuv reads /proc/stat for CPU info → returns empty array.
// Tools using os.cpus().length for parallelism (e.g., make -j) break with 0.

const _originalCpus = os.cpus;

os.cpus = function cpus() {
  const result = _originalCpus.call(os);
  if (result.length > 0) {
    return result;
  }
  // Return a single fake CPU entry so .length is at least 1
  return [{ model: 'unknown', speed: 0, times: { user: 0, nice: 0, sys: 0, idle: 0, irq: 0 } }];
};

// ─── os.networkInterfaces() safety ──────────────────────────
// Some Android configurations throw EACCES when reading network
// interface information. Wrap with try-catch to prevent crashes.
//
// Additionally, Android/Termux typically only exposes the loopback
// interface (`lo`) to Node.js. In that situation, OpenClaw's Bonjour
// advertiser can't send multicast announcements and logs noisy
// "Announcement failed as of socket errors!" repeatedly.
// Auto-disable Bonjour via OPENCLAW_DISABLE_BONJOUR when only
// loopback interfaces are visible.

const _originalNetworkInterfaces = os.networkInterfaces;

function _createLoopbackInterfaces() {
  return {
    lo: [
      {
        address: '127.0.0.1',
        netmask: '255.0.0.0',
        family: 'IPv4',
        mac: '00:00:00:00:00:00',
        internal: true,
        cidr: '127.0.0.1/8',
      },
    ],
  };
}

function _hasNonLoopbackInterface(interfaces) {
  try {
    return Object.values(interfaces).some(entries =>
      Array.isArray(entries) && entries.some(entry => entry && entry.internal === false)
    );
  } catch {
    return false;
  }
}

os.networkInterfaces = function networkInterfaces() {
  let interfaces;
  try {
    interfaces = _originalNetworkInterfaces.call(os);
  } catch {
    interfaces = _createLoopbackInterfaces();
  }
  if (!process.env.OPENCLAW_DISABLE_BONJOUR && !_hasNonLoopbackInterface(interfaces)) {
    process.env.OPENCLAW_DISABLE_BONJOUR = '1';
  }
  return interfaces;
};

// ─── Shell override for exec/execSync ────────────────────────
// Node.js child_process hardcodes /bin/sh as the default shell on Linux.
// On Android:
//   - Android 7-8: /bin/sh doesn't exist at all
//   - Android 9+: /bin/sh exists (/system/bin/sh) but is minimal (toybox/mksh)
//     and lacks Termux PATH, environment, and proper command support
// Always use Termux's shell for exec/execSync to ensure consistent behavior.
//
// Note: exec/execSync build their shell command inside Node's internal spawn,
// which cannot be intercepted by patching child_process.spawn. A simple command
// (no pipes, redirects, ...) that needs the glibc loader or a shebang fix is
// therefore re-routed to the file-based APIs, so the spawn/execFile wrapping
// below applies to it too.

{
  const child_process = require('child_process');
  const termuxSh = (process.env.PREFIX || '/data/data/com.termux/files/usr') + '/bin/sh';

  if (fs.existsSync(termuxSh)) {
    const _originalExec = child_process.exec;
    const _originalExecSync = child_process.execSync;

    child_process.exec = function exec(command, options, callback) {
      if (typeof options === 'function') {
        callback = options;
        options = {};
      }
      options = options || {};
      // An explicitly requested shell is the caller's decision: leave it alone.
      const userShell = options.shell;
      const fixed = userShell ? null : _oaShellCommandFix(command, options.env);
      if (fixed) {
        const fileOptions = Object.assign({}, options, { shell: false });
        if (fixed.env) fileOptions.env = fixed.env;
        return child_process.execFile(fixed.file, fixed.args, fileOptions, callback);
      }
      if (!userShell) {
        options.shell = termuxSh;
      }
      return _originalExec.call(child_process, command, options, callback);
    };

    child_process.execSync = function execSync(command, options) {
      options = options || {};
      const userShell = options.shell;
      const fixed = userShell ? null : _oaShellCommandFix(command, options.env);
      if (fixed) {
        const fileOptions = Object.assign({}, options, { shell: false });
        if (fixed.env) fileOptions.env = fixed.env;
        return child_process.execFileSync(fixed.file, fixed.args, fileOptions);
      }
      if (!userShell) {
        options.shell = termuxSh;
      }
      return _originalExecSync.call(child_process, command, options);
    };
  }
}

// ─── DNS resolver fix ────────────────────────────────────────
// glibc's getaddrinfo() reads /data/data/com.termux/files/usr/glibc/etc/resolv.conf
// for DNS servers. This file may be missing or inaccessible:
// - Standalone APK: runs under com.openclaw.android, can't access com.termux paths
// - Termux: resolv-conf package may not be installed
// Without a valid resolv.conf, dns.lookup() fails with EAI_AGAIN errors.
//
// Fix: Override both dns.lookup (callback) and dns.promises.lookup (promise)
// to use c-ares resolver (dns.resolve) which respects dns.setServers(),
// then fall back to getaddrinfo.

try {
  const dns = require('dns');

  // Read DNS servers from our resolv.conf or use Google DNS as fallback.
  // glibc's own reader uses $PREFIX/glibc/etc/resolv.conf; the Termux (bionic)
  // copy lives at $PREFIX/etc/resolv.conf. The installer keeps the glibc copy in
  // sync, so prefer it and fall back to the bionic file.
  const _oaPrefix = process.env.PREFIX || '/data/data/com.termux/files/usr';
  const _resolvCandidates = [
    _oaPrefix + '/glibc/etc/resolv.conf',
    _oaPrefix + '/etc/resolv.conf',
  ];
  // c-ares rejects zone-scoped addresses (fe80::1%wlan0) and other junk.
  const _usableNameServer = (server) => {
    const bare = String(server || '').replace(/^\[|\]$/g, '');
    return bare.length > 0 && !bare.includes('%') && /^[0-9A-Fa-f:.]+$/.test(bare);
  };

  let dnsServers = [];
  for (const candidate of _resolvCandidates) {
    try {
      const parsed = fs.readFileSync(candidate, 'utf8').match(/^nameserver\s+(\S+)/gm);
      if (parsed) {
        const servers = parsed
          .map(line => line.replace(/^nameserver\s+/, '').trim())
          .filter(_usableNameServer);
        if (servers.length > 0) {
          dnsServers = servers;
          break;
        }
      }
    } catch {}
  }
  if (dnsServers.length === 0) {
    dnsServers = ['8.8.8.8', '8.8.4.4'];
  }

  // Set DNS servers for c-ares resolver
  try { dns.setServers(dnsServers); } catch {}

  // Override dns.lookup (callback API) to use c-ares resolver
  const _originalLookup = dns.lookup;

  // Localhost must never go to external DNS. Android/glibc may lack /etc/hosts,
  // causing getaddrinfo to fail or return 0.0.0.0. Short-circuit it here.
  const _localhostNames = new Set(['localhost', 'localhost.localdomain', 'ip6-localhost', 'ip6-loopback']);

  dns.lookup = function lookup(hostname, options, callback) {
    if (typeof options === 'function') {
      callback = options;
      options = {};
    }
    const originalOptions = options;
    const opts = typeof options === 'number' ? { family: options } : (options || {});
    const wantAll = opts.all === true;
    const family = opts.family || 0;

    // Short-circuit localhost — never send to external DNS
    if (_localhostNames.has(hostname)) {
      if (family === 6) {
        if (wantAll) return callback(null, [{ address: '::1', family: 6 }]);
        return callback(null, '::1', 6);
      }
      if (wantAll) return callback(null, [{ address: '127.0.0.1', family: 4 }]);
      return callback(null, '127.0.0.1', 4);
    }

    const resolve = (fam, cb) => {
      const fn = fam === 6 ? dns.resolve6 : dns.resolve4;
      fn(hostname, cb);
    };

    const tryResolve = (fam) => {
      resolve(fam, (err, addresses) => {
        if (!err && addresses && addresses.length > 0) {
          const resFam = fam === 6 ? 6 : 4;
          if (wantAll) {
            callback(null, addresses.map(a => ({ address: a, family: resFam })));
          } else {
            callback(null, addresses[0], resFam);
          }
        } else if (family === 0 && fam === 4) {
          tryResolve(6);
        } else {
          _originalLookup.call(dns, hostname, originalOptions, callback);
        }
      });
    };

    tryResolve(family === 6 ? 6 : 4);
  };

  // Override dns.promises.lookup (promise API) to use c-ares resolver.
  // OpenClaw's SSRF guard uses this API for web_search DNS resolution.
  const _originalPromiseLookup = dns.promises.lookup;
  dns.promises.lookup = async function lookup(hostname, options) {
    const opts = typeof options === 'number' ? { family: options } : (options || {});
    const wantAll = opts.all === true;
    const family = opts.family || 0;

    // Short-circuit localhost
    if (_localhostNames.has(hostname)) {
      if (family === 6) {
        return wantAll ? [{ address: '::1', family: 6 }] : { address: '::1', family: 6 };
      }
      return wantAll ? [{ address: '127.0.0.1', family: 4 }] : { address: '127.0.0.1', family: 4 };
    }

    const resolve = (fam) => {
      return new Promise((res, rej) => {
        const fn = fam === 6 ? dns.resolve6 : dns.resolve4;
        fn(hostname, (err, addresses) => err ? rej(err) : res(addresses));
      });
    };

    const tryResolve = async (fam) => {
      try {
        const addresses = await resolve(fam);
        if (addresses && addresses.length > 0) {
          const resFam = fam === 6 ? 6 : 4;
          if (wantAll) {
            return addresses.map(a => ({ address: a, family: resFam }));
          }
          return { address: addresses[0], family: resFam };
        }
      } catch {}
      if (family === 0 && fam === 4) return tryResolve(6);
      return _originalPromiseLookup.call(dns.promises, hostname, options);
    };

    return tryResolve(family === 6 ? 6 : 4);
  };
} catch {}

// ─── ELF binary auto-wrapping for spawn/spawnSync ──────────
// npm/npx-installed native binaries (e.g., @zed-industries/codex-acp)
// are standard Linux ELF files whose interpreter is /lib/ld-linux-aarch64.so.1.
// Android lacks this path, so the kernel returns ENOENT on direct execution.
// Intercept child_process spawn APIs to detect ELF binaries and automatically
// route them through the glibc dynamic linker (ld.so).

const _glibcLdso = (process.env.PREFIX || '/data/data/com.termux/files/usr')
  + '/glibc/lib/ld-linux-aarch64.so.1';
const _glibcLibPath = (process.env.PREFIX || '/data/data/com.termux/files/usr')
  + '/glibc/lib';

function _needsGlibcWrap(filePath) {
  // Read ELF header and check PT_INTERP to distinguish glibc binaries
  // from bionic (Android/Termux) binaries. Only glibc binaries need wrapping.
  // Bionic binaries use /system/bin/linker64; glibc use /lib/ld-linux-*.so.1
  try {
    const fd = fs.openSync(filePath, 'r');
    try {
      const ehdr = Buffer.alloc(64);
      if (fs.readSync(fd, ehdr, 0, 64, 0) < 64) return false;
      // Check ELF magic
      if (ehdr[0] !== 0x7f || ehdr[1] !== 0x45 || ehdr[2] !== 0x4c || ehdr[3] !== 0x46) return false;
      // ELF64: e_phoff at offset 32 (8 bytes), e_phentsize at 54 (2 bytes), e_phnum at 56 (2 bytes)
      const phoff = Number(ehdr.readBigUInt64LE(32));
      const phentsize = ehdr.readUInt16LE(54);
      const phnum = ehdr.readUInt16LE(56);
      // Scan program headers for PT_INTERP (type = 3)
      for (let i = 0; i < phnum; i++) {
        const phBuf = Buffer.alloc(phentsize);
        if (fs.readSync(fd, phBuf, 0, phentsize, phoff + i * phentsize) < phentsize) continue;
        const pType = phBuf.readUInt32LE(0);
        if (pType === 3) { // PT_INTERP
          const interpOff = Number(phBuf.readBigUInt64LE(8));
          const interpSize = Number(phBuf.readBigUInt64LE(32));
          const interpBuf = Buffer.alloc(Math.min(interpSize, 256));
          fs.readSync(fd, interpBuf, 0, interpBuf.length, interpOff);
          const interp = interpBuf.toString('utf8').replace(/\0+$/, '');
          return interp.includes('ld-linux');
        }
      }
      return false;
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return false;
  }
}

function _resolveCommand(command, env) {
  if (command.includes('/')) {
    try { return fs.realpathSync(command); } catch { return command; }
  }
  const searchPath = (env && env.PATH) || process.env.PATH || '';
  const dirs = searchPath.split(':');
  for (const dir of dirs) {
    const full = path.join(dir, command);
    try {
      fs.accessSync(full, fs.constants.X_OK);
      return full;
    } catch {}
  }
  return null;
}

function _readShebang(filePath) {
  // Read first 256 bytes to extract shebang line from script files.
  // Returns null if not a script, or { interpreter, args } if shebang found.
  try {
    const fd = fs.openSync(filePath, 'r');
    try {
      const buf = Buffer.alloc(256);
      const n = fs.readSync(fd, buf, 0, 256, 0);
      if (n < 2 || buf[0] !== 0x23 || buf[1] !== 0x21) return null; // not #!
      const line = buf.toString('utf8', 2, n).split('\n')[0].trim();
      const parts = line.split(/\s+/);
      return { interpreter: parts[0], args: parts.slice(1) };
    } finally {
      fs.closeSync(fd);
    }
  } catch {
    return null;
  }
}

function _resolveShebang(resolved, spawnEnv) {
  // For a resolved file path, check if it has a shebang pointing to a
  // non-existent interpreter (e.g. #!/usr/bin/env node on Android).
  // Returns { interpPath, interpArgs } or null if no fixup needed.
  const shebang = _readShebang(resolved);
  if (!shebang) return null;

  let interpPath = shebang.interpreter;
  let interpArgs = shebang.args;

  if (interpPath === '/usr/bin/env' && interpArgs.length > 0) {
    // #!/usr/bin/env <cmd> — resolve <cmd> from PATH
    let cmdIdx = 0;
    while (cmdIdx < interpArgs.length && interpArgs[cmdIdx].startsWith('-')) cmdIdx++;
    if (cmdIdx >= interpArgs.length) return null;
    const cmd = interpArgs[cmdIdx];
    const resolvedCmd = _resolveCommand(cmd, spawnEnv);
    if (!resolvedCmd) return null;
    interpPath = resolvedCmd;
    interpArgs = interpArgs.slice(0, cmdIdx).concat(interpArgs.slice(cmdIdx + 1));
  } else if (!fs.existsSync(interpPath)) {
    // Interpreter at non-existent absolute path — try resolving by basename from PATH
    const basename = path.basename(interpPath);
    const resolvedInterp = _resolveCommand(basename, spawnEnv);
    if (!resolvedInterp) return null;
    interpPath = resolvedInterp;
  } else {
    // Shebang interpreter exists, kernel can handle it
    return null;
  }

  return { interpPath, interpArgs };
}

// Detect shell invocation patterns: spawn('/path/to/sh', ['-c', 'cmd args...'])
// or spawn('cmd', args, { shell: true })
function _isShellInvocation(file, args) {
  if (!args || args.length < 2 || args[0] !== '-c') return null;
  const base = path.basename(file);
  if (base !== 'sh' && base !== 'bash' && base !== 'dash' && base !== 'zsh') return null;
  return args[1]; // the shell command string
}

function _tryFixShellCommand(cmdStr, spawnEnv) {
  // Extract the command name from a simple shell command string.
  // Only handle simple cases: "cmd arg1 arg2..." — no pipes, redirects, etc.
  const shellChars = /[|><&;`$(){}]/;
  if (shellChars.test(cmdStr)) return null;

  const parts = cmdStr.trim().split(/\s+/);
  if (parts.length === 0) return null;
  const cmd = parts[0];
  const cmdArgs = parts.slice(1);

  const resolved = _resolveCommand(cmd, spawnEnv);
  if (!resolved) return null;

  // glibc ELF binary
  if (_needsGlibcWrap(resolved)) {
    const env = Object.assign({}, spawnEnv);
    delete env.LD_PRELOAD;
    return {
      file: _glibcLdso,
      args: ['--library-path', _glibcLibPath, resolved].concat(cmdArgs),
      env: env,
    };
  }

  // Script with broken shebang
  const shebang = _resolveShebang(resolved, spawnEnv);
  if (shebang) {
    return {
      file: shebang.interpPath,
      args: shebang.interpArgs.concat([resolved]).concat(cmdArgs),
    };
  }

  return null;
}

function _tryWrapSpawn(file, args, options) {
  const spawnEnv = options && options.env ? options.env : process.env;

  // Detect shell invocations: spawn('sh', ['-c', 'command...']) or spawn(cmd, args, { shell: true })
  // npm/npx uses spawn('/path/to/sh', ['-c', 'cmd args...']) to execute package binaries.
  // Without libtermux-exec.so, #!/usr/bin/env shebangs in these scripts fail.
  if (options && options.shell) {
    // shell: true — Node.js will convert to sh -c 'file args...'
    if (!file.includes(' ') && !(/[|><&;`$()]/).test(file)) {
      const resolved = _resolveCommand(file, spawnEnv);
      if (resolved) {
        if (_needsGlibcWrap(resolved)) {
          const env = Object.assign({}, spawnEnv);
          delete env.LD_PRELOAD;
          return {
            file: _glibcLdso,
            args: ['--library-path', _glibcLibPath, resolved].concat(args || []),
            options: Object.assign({}, options, { env: env, shell: false }),
          };
        }
        const shebang = _resolveShebang(resolved, spawnEnv);
        if (shebang) {
          return {
            file: shebang.interpPath,
            args: shebang.interpArgs.concat([resolved]).concat(args || []),
            options: Object.assign({}, options, { shell: false }),
          };
        }
      }
    }
    return null;
  }

  // Direct shell invocation: spawn('/path/to/sh', ['-c', 'cmd args...'])
  const shellCmd = _isShellInvocation(file, args);
  if (shellCmd) {
    const fix = _tryFixShellCommand(shellCmd, spawnEnv);
    if (fix) {
      return {
        file: fix.file,
        args: fix.args,
        options: fix.env ? Object.assign({}, options, { env: fix.env }) : options,
      };
    }
    return null;
  }

  const resolved = _resolveCommand(file, spawnEnv);
  if (!resolved) return null;
  if (resolved === _glibcLdso || resolved.endsWith('/ld-linux-aarch64.so.1')) return null;

  // Case 1: glibc ELF binary — wrap with ld.so
  if (_needsGlibcWrap(resolved)) {
    const env = Object.assign({}, spawnEnv);
    delete env.LD_PRELOAD;
    return {
      file: _glibcLdso,
      args: ['--library-path', _glibcLibPath, resolved].concat(args || []),
      options: Object.assign({}, options, { env: env }),
    };
  }

  // Case 2: Script with shebang pointing to non-existent path
  const shebang = _resolveShebang(resolved, spawnEnv);
  if (!shebang) return null;

  return {
    file: shebang.interpPath,
    args: shebang.interpArgs.concat([resolved]).concat(args || []),
    options: options,
  };
}

// Used by the exec/execSync overrides above: resolve a simple shell command the
// same way spawn does, so native glibc binaries and broken shebangs work there
// too. Returns null when the command is not a simple one (the shell handles it),
// when the caller chose its own shell, or when there is no glibc loader.
function _oaShellCommandFix(command, env) {
  if (typeof command !== 'string') return null;
  if (!fs.existsSync(_glibcLdso)) return null;
  try {
    return _tryFixShellCommand(command, env || process.env);
  } catch {
    return null;
  }
}

if (fs.existsSync(_glibcLdso)) {
  const _cp = require('child_process');

  // Normalize optional args parameter: spawn(cmd[, args][, opts])
  function _normalizeArgs(args, options) {
    if (args != null && !Array.isArray(args)) {
      return { args: [], options: args };
    }
    return { args: args || [], options: options };
  }

  const _origSpawn = _cp.spawn;
  _cp.spawn = function spawn(command, args, options) {
    const n = _normalizeArgs(args, options);
    const w = _tryWrapSpawn(command, n.args, n.options);
    if (w) return _origSpawn.call(_cp, w.file, w.args, w.options);
    return _origSpawn.call(_cp, command, args, options);
  };

  const _origSpawnSync = _cp.spawnSync;
  _cp.spawnSync = function spawnSync(command, args, options) {
    const n = _normalizeArgs(args, options);
    const w = _tryWrapSpawn(command, n.args, n.options);
    if (w) return _origSpawnSync.call(_cp, w.file, w.args, w.options);
    return _origSpawnSync.call(_cp, command, args, options);
  };

  const _origExecFile = _cp.execFile;
  _cp.execFile = function execFile(file, args, options, callback) {
    // execFile(file[, args][, options], callback)
    if (typeof args === 'function') {
      callback = args; args = []; options = {};
    } else if (typeof options === 'function') {
      callback = options;
      if (Array.isArray(args)) { options = {}; } else { options = args; args = []; }
    }
    const w = _tryWrapSpawn(file, args, options);
    if (w) return _origExecFile.call(_cp, w.file, w.args, w.options, callback);
    return _origExecFile.call(_cp, file, args, options, callback);
  };

  const _origExecFileSync = _cp.execFileSync;
  _cp.execFileSync = function execFileSync(file, args, options) {
    const n = _normalizeArgs(args, options);
    const w = _tryWrapSpawn(file, n.args, n.options);
    if (w) return _origExecFileSync.call(_cp, w.file, w.args, w.options);
    return _origExecFileSync.call(_cp, file, args, options);
  };
}
GLIBC_COMPAT_JS
    cp "$COMPAT_FILE" "$PATCH_DIR/glibc-compat.js"

    log_success "glibc-compat.js installed at $COMPAT_FILE"
}

write_hardlink_patcher() {
    mkdir -p "$PATCH_DIR"
    cat > "$PATCH_DIR/openclaw-patch-hardlink.js" << 'HARDLINK_JS'
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2]);
const CHECK = process.argv.includes('--check');
const ONLY_B3 = process.argv.includes('--only-b3');
const listAt = process.argv.indexOf('--list');
const LIST_FILE = listAt > 0 ? process.argv[listAt + 1] : '';
let patched = 0, already = 0, problems = 0;
// how many files each class located (patched or already patched): a class with none is NOTARGET
const found = { classifier: 0, backup: 0, archive: 0, fssafe: 0 };
const read = (f) => fs.readFileSync(f, 'latin1');
const rel = (f) => path.relative(root, f);
const FSSAFE_DIST = path.join(root, 'node_modules', '@openclaw', 'fs-safe', 'dist') + path.sep;
// the package declares fs-safe: then a file of it has to be found (not required for --only-b3: not unpacked yet)
let needFsSafe = false;
try {
  const pj = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  needFsSafe = !!(pj.dependencies && pj.dependencies['@openclaw/fs-safe']);
} catch (e) { /* an unreadable package.json: not required */ }
// Atomic: a full disk must not leave a cut-off bundle (a broken OpenClaw); write a temp file next to it, then
// rename it over the original. A failed write is a problem (counted, reported), the original stays as it was.
const write = (f, s) => {
  if (CHECK) return true;
  const tmp = f + '.oa-tmp';
  try {
    fs.writeFileSync(tmp, s, 'latin1');
    fs.chmodSync(tmp, fs.statSync(f).mode & 0o7777);
    fs.renameSync(tmp, f);
    return true;
  } catch (e) {
    try { fs.unlinkSync(tmp); } catch (e2) { /* nothing to clean */ }
    console.log('WRITEFAIL ' + rel(f) + ' (' + (e && e.code ? e.code : String(e)) + ')');
    problems++;
    return false;
  }
};

// ---- F1: two classifier sets, each `NAME = [/* @__PURE__ */] new Set([ <quote>CODE<quote>, ... ])` (quotes may
// be ", ' or `, on one line or several; minified bundles use back quotes on one line):
//   HARDLINK_FALLBACK_CODES    - the hard link is refused  -> copy
//   NATIVE_COPY_FALLBACK_CODES - the clone/reflink step of that copy is refused (ioctl FICLONE: EACCES on
//                                Android, found on the device after the first fix) -> plain copy
const SETS = ['HARDLINK_FALLBACK_CODES', 'NATIVE_COPY_FALLBACK_CODES'];
const B3_BODY_MARK = 'Cannot discard a recovery publication created by an earlier run';
// Add EACCES to one set; returns 'patched' | 'already' | 'nomatch'
function addEacces(text, name) {
  const re = new RegExp('(' + name + '\\s*=\\s*(?:\\/\\*[^*]*\\*\\/\\s*)?new Set\\(\\[\\s*)((["\'`])[^\\]]*)\\]\\)');
  const m = re.exec(text);
  if (!m) return { status: 'nomatch', text };
  if (/EACCES/.test(m[2])) return { status: 'already', text };
  const q = m[3];
  const out = text.slice(0, m.index) + m[1] + q + 'EACCES' + q + ',' + m[2] + '])' + text.slice(m.index + m[0].length);
  return { status: 'patched', text: out };
}

// ---- F1c: fs-safe 0.24 (OpenClaw 2026.10). Its native copy has no code set: createNativeCopyFile falls back to a
// plain copy only on ENOTSUP, and assertNativeCopyCompleted lists the "not supported" codes in a literal. EACCES is
// added to both (the same code in fs-safe's copy-file-input.js and in the bundles that inline it; the bundlers
// format the list differently, so whitespace is not part of the pattern). The list is edited only in a file that
// has the ENOTSUP-only fallback (fs-safe 0.21 and 0.24 alike; the code sets of F1 are a separate thing: they
// decide the hard link and the clone step, this decides what the plain-copy fallback itself accepts).
const NF_OLD = /code === "ENOTSUP"( && input\.clone !== "always")/;
const NF_DONE = /code === "ENOTSUP" \|\| code === "EACCES"\) && input\.clone !== "always"/;
const NL_OLD = /(\[\s*"ENOTSUP",\s*"EOPNOTSUPP",\s*"ENOSYS",\s*"EXDEV",\s*"EINVAL")(\s*\]\.includes\(copied\.errorCode\))/;
const NL_DONE = /"EINVAL",\s*"EACCES"\s*\]\.includes\(copied\.errorCode\)/;
const NATIVE_COPY_DEF = /function createNativeCopyFile\w*\(/;

// ---- F4: the pid namespace inode of the gateway lock (OpenClaw 2026.10; see the header)
const NS_OLD = /(?<!return )\b([\w$]+)\.statSync\((["'`])\/proc\/self\/ns\/pid\2, \{ bigint: (?:true|!0) \}\)\.ino\.toString\(\)/;
const NS_DONE = /\/proc\/self\/ns\/pid[^;]{0,60}\.ino\.toString\(\); \} catch \{ return "unavailable"; \}/;
const NS_DEF = /function readGatewayLockProcessNamespace\(/;
const NATIVE_LIST_DEF = /function assertNativeCopyCompleted\w*\(/;

// ---- F3: moveMigrationArtifact by rename when the hard link is refused (see the header)
const B3_MARK = '__oaMoveMigrationArtifactOrig';
const B3_DEF = /async function moveMigrationArtifact\(/;
function b3Helper(requireSync, syncDir) {
  return `/* B3_SESSION_ARCHIVE_PATCH v2 (OpenClaw on Android): hard links are refused, archive by rename */
async function __oaMoveByRename(sourcePath, targetPath, expected, onPublished, publishSourceRemoval) {
	const sourceThere = !!fs.lstatSync(sourcePath, { bigint: true, throwIfNoEntry: false });
	const targetThere = !!fs.lstatSync(targetPath, { bigint: true, throwIfNoEntry: false });
	if (sourceThere && targetThere) throw new Error("artifact archive path already exists");
	let movedHere = false;
	if (sourceThere) {
		if (!sameMigrationArtifact(readMigrationArtifactIdentity(sourcePath), expected)) throw new Error("artifact changed before publication");
		fs.renameSync(sourcePath, targetPath);
		movedHere = true;
	}
	${requireSync}(await ${syncDir}(path.dirname(targetPath)), "Recovery artifact publication");
	const verifyMoved = () => {
		if (fs.lstatSync(sourcePath, { bigint: true, throwIfNoEntry: false }) || !sameMigrationArtifact(readMigrationArtifactIdentity(targetPath), expected)) throw new Error("artifact changed during publication");
	};
	let published = false;
	const removeSource = () => {
		verifyMoved();
		if (onPublished) {
			onPublished();
			published = true;
			verifyMoved();
		}
		published = true;
	};
	let retainedSource = false;
	const retainSource = () => {
		// as in OpenClaw's own code: a publication made by an earlier run cannot be discarded
		if (!movedHere) throw new Error("Cannot discard a recovery publication created by an earlier run.");
		verifyMoved();
		fs.renameSync(targetPath, sourcePath);
		retainedSource = true;
	};
	try {
		if (publishSourceRemoval) publishSourceRemoval(removeSource, retainSource);
		else removeSource();
	} catch (error) {
		// failed before the move was final: put the file back under its own name (OpenClaw's own code
		// keeps both names then), so that a rerun sees the same state as after a refused hard link
		if (movedHere && !published && !retainedSource) {
			try {
				if (!fs.lstatSync(sourcePath, { bigint: true, throwIfNoEntry: false }) && sameMigrationArtifact(readMigrationArtifactIdentity(targetPath), expected)) fs.renameSync(targetPath, sourcePath);
			} catch (restoreError) { /* keep the original error */ }
		}
		throw error;
	} finally {
		if (retainedSource) ${requireSync}(await ${syncDir}(path.dirname(targetPath)), "Recovery artifact deferral");
	}
	${requireSync}(await ${syncDir}(path.dirname(sourcePath)), "Recovery artifact source");
	if (!sameMigrationArtifact(readMigrationArtifactIdentity(targetPath), expected)) throw new Error("artifact changed during publication");
}
async function moveMigrationArtifact(sourcePath, targetPath, expected, onPublished, publishSourceRemoval) {
	const missing = (p) => !fs.lstatSync(p, { bigint: true, throwIfNoEntry: false });
	// an interrupted rename-based move: the source is gone, the archive copy is there
	if (missing(sourcePath) && !missing(targetPath)) return __oaMoveByRename(sourcePath, targetPath, expected, onPublished, publishSourceRemoval);
	try {
		return await ${B3_MARK}(sourcePath, targetPath, expected, onPublished, publishSourceRemoval);
	} catch (error) {
		// only a refused hard link (the codes of the B2 fallback list), before anything was published
		if (error && ["EACCES", "EPERM", "ENOTSUP", "EOPNOTSUPP", "ENOSYS"].includes(error.code) && !missing(sourcePath) && missing(targetPath)) return __oaMoveByRename(sourcePath, targetPath, expected, onPublished, publishSourceRemoval);
		throw error;
	}
}
`;
}
const B3_TAG = '/* B3_SESSION_ARCHIVE_PATCH';
const B3_TAG_CURRENT = B3_TAG + ' v2 ';
const B3_HELPER_NAMES = /([\w$]+)\(await ([\w$]+)\(path\.dirname\(/;
// A bundle with a second, unwrapped definition would pass on the marker alone: count them (the wrapper is the one)
const b3Defs = (t) => t.split(B3_DEF).length - 1;
function patchB3(text) {
  if (b3Defs(text) > 1) return { status: 'nomatch', text };
  if (text.includes(B3_MARK)) {
    if (text.includes(B3_TAG_CURRENT)) return { status: 'already', text };
    // patched by an earlier version of this helper: replace it (it sits right before the renamed original)
    const a = text.indexOf(B3_TAG);
    const oidx = text.indexOf('async function ' + B3_MARK + '(');
    if (a < 0 || oidx < a) return { status: 'nomatch', text };
    const m = B3_HELPER_NAMES.exec(text.slice(oidx, oidx + 8000));
    if (!m) return { status: 'nomatch', text };
    return { status: 'patched', text: text.slice(0, a) + b3Helper(m[1], m[2]) + text.slice(oidx) };
  }
  const idx = text.search(B3_DEF);
  if (idx < 0) return { status: 'nomatch', text };
  // the names this bundle uses for the directory-sync helpers (minified bundles rename them)
  const m = B3_HELPER_NAMES.exec(text.slice(idx, idx + 8000));
  if (!m) return { status: 'nomatch', text };
  const rest = text.slice(idx).replace(B3_DEF, 'async function ' + B3_MARK + '(');
  return { status: 'patched', text: text.slice(0, idx) + b3Helper(m[1], m[2]) + rest };
}

// ---- the files to look at: the ones the caller's grep found a marker in (dist/ and fs-safe), plus the backup bundle
const candidates = new Set();
if (LIST_FILE) {
  for (const line of fs.readFileSync(LIST_FILE, 'utf8').split('\n')) if (line) candidates.add(path.resolve(line));
}
const backupFiles = new Set();
const distDir = path.join(root, 'dist');
if (!ONLY_B3 && fs.existsSync(distDir)) {
  for (const n of fs.readdirSync(distDir)) if (/^backup-create-.*\.mjs$/.test(n)) backupFiles.add(path.join(distDir, n));
}
for (const f of backupFiles) candidates.add(f);

for (const file of [...candidates].sort()) {
  let s;
  try { s = read(file); } catch (e) { continue; }
  const original = s;
  const r = rel(file);
  const patchedBefore = patched, alreadyBefore = already;
  const inFsSafe = file.startsWith(FSSAFE_DIST);
  const classifierBefore = found.classifier;
  if (!ONLY_B3) {
    // F1
    for (const name of SETS) {
      if (!new RegExp('\\b' + name + '\\s*=').test(s)) continue;   // a mention without the definition is no target
      const res = addEacces(s, name);
      if (res.status === 'nomatch') { console.log('NOMATCH ' + r + ' (' + name + ')'); problems++; continue; }
      found.classifier++;
      if (res.status === 'already') { already++; continue; }
      s = res.text; patched++; console.log((CHECK ? 'TODO ' : 'PATCHED ') + r + ' (' + name + ')');
    }
    // F1c
    const nfOld = NF_OLD.test(s), nfDone = NF_DONE.test(s);
    if (nfOld) {
      s = s.replace(new RegExp(NF_OLD.source, 'g'), '(code === "ENOTSUP" || code === "EACCES")$1');
      found.classifier++; patched++;
      console.log((CHECK ? 'TODO ' : 'PATCHED ') + r + ' (native copy: EACCES falls back to a plain copy)');
    } else if (nfDone) {
      found.classifier++; already++;
    }
    if (nfOld || nfDone) {
      if (NL_OLD.test(s)) {
        s = s.replace(new RegExp(NL_OLD.source, 'g'), '$1, "EACCES"$2');
        patched++; console.log((CHECK ? 'TODO ' : 'PATCHED ') + r + ' (native copy: EACCES is a "not supported" code)');
      } else if (NL_DONE.test(s)) {
        already++;
      } else if (NATIVE_LIST_DEF.test(s)) {
        console.log('NOMATCH ' + r + ' (native copy: list of "not supported" codes)'); problems++;
      }
    } else if (NATIVE_COPY_DEF.test(s) && !/\bNATIVE_COPY_FALLBACK_CODES\s*=/.test(s)) {
      // defines the native copy, but neither in the 0.21 shape (a code set, handled by F1) nor in the 0.24 shape
      console.log('NOMATCH ' + r + ' (native copy fallback in a form the patch does not know)'); problems++;
    }
    if (inFsSafe && found.classifier > classifierBefore) found.fssafe++;
    // F4
    if (s.includes('/proc/self/ns/pid')) {
      if (NS_DONE.test(s) && !NS_OLD.test(s)) {
        already++;
      } else if (NS_OLD.test(s)) {
        s = s.replace(new RegExp(NS_OLD.source, 'g'), (m, o, q) => '(() => { try { return ' + o + '.statSync(' + q + '/proc/self/ns/pid' + q + ', { bigint: true }).ino.toString(); } catch { return "unavailable"; } })()');
        patched++; console.log((CHECK ? 'TODO ' : 'PATCHED ') + r + ' (gateway lock: pid namespace unavailable on Android)');
      } else if (NS_DEF.test(s)) {
        console.log('NOMATCH ' + r + ' (gateway lock pid namespace in a form the patch does not know)'); problems++;
      }
    }
    // F1b
    if (backupFiles.has(file)) {
      const n = s.split('strategy: "link-required"').length - 1;
      found.backup++;
      if (n === 0) { already++; }
      else {
        s = s.split('strategy: "link-required"').join('strategy: "link-or-copy"');
        patched++; console.log((CHECK ? 'TODO ' : 'PATCHED ') + r + ' (' + n + ' link-required -> link-or-copy)');
      }
    }
  }
  // F3
  if (s.includes('function moveMigrationArtifact(') || s.includes(B3_MARK)) {
    const res = patchB3(s);
    if (res.status === 'nomatch') { console.log('NOMATCH ' + r + ' (B3 moveMigrationArtifact)'); problems++; }
    else {
      found.archive++;
      if (res.status === 'already') already++;
      else { s = res.text; patched++; console.log((CHECK ? 'TODO ' : 'PATCHED ') + r + ' (B3 moveMigrationArtifact)'); }
    }
  } else if (s.includes(B3_BODY_MARK)) {
    // the body of the function is here, its definition is not in the known form: this bundle is not patched
    console.log('NOMATCH ' + r + ' (B3 moveMigrationArtifact: definition in a form the patch does not know)'); problems++;
  }
  if (s !== original && !write(file, s)) {
    // not written (already counted as a problem): nothing of this file was patched
    patched = patchedBefore; already = alreadyBefore;
  }
}

// ---- a class that located nothing: this package does not fit the patch (loud, never silent)
if (!ONLY_B3) {
  if (!found.classifier) { console.log('NOTARGET classifier (HARDLINK_FALLBACK_CODES / native copy fallback)'); problems++; }
  if (!found.backup) { console.log('NOTARGET backup (dist/backup-create-*.mjs)'); problems++; }
  if (needFsSafe && !found.fssafe) { console.log('NOTARGET fs-safe (node_modules/@openclaw/fs-safe/dist: the package depends on it)'); problems++; }
}
if (!found.archive) { console.log('NOTARGET archive (moveMigrationArtifact)'); problems++; }
console.log('SUMMARY ' + (CHECK ? 'todo=' : 'patched=') + patched + ' already=' + already + ' problems=' + problems);
process.exit(problems || (CHECK && patched) ? 3 : 0);
HARDLINK_JS
}

# ------------------------------------------------------------------------------
# Node.js (official linux-arm64 build through glibc ld.so)
# ------------------------------------------------------------------------------
write_node_wrappers() {
    mkdir -p "$BIN_DIR"

    # Node wrapper: glibc ld.so loads node.real directly. patchelf is NOT used
    # (Android seccomp kills patchelf'd binaries with SIGSEGV).
    cat > "$BIN_DIR/node" << NODE_WRAPPER
#!$PREFIX/bin/bash
[ -n "\$LD_PRELOAD" ] && export _OA_ORIG_LD_PRELOAD="\$LD_PRELOAD"
unset LD_PRELOAD
export _OA_WRAPPER_PATH="$BIN_DIR/node"
# OpenClaw's native fs-safe helper probes openat2, which Android kills with SIGSYS.
export FS_SAFE_TEST_NO_OPENAT2="\${FS_SAFE_TEST_NO_OPENAT2:-1}"
export OPENCLAW_NO_AUTO_UPDATE="\${OPENCLAW_NO_AUTO_UPDATE:-1}"
_OA_COMPAT="$COMPAT_FILE"
[ -s "\$_OA_COMPAT" ] || _OA_COMPAT="$PATCH_DIR/glibc-compat.js"
if [ -f "\$_OA_COMPAT" ]; then
    case "\${NODE_OPTIONS:-}" in
        *glibc-compat.js*) ;;
        *) export NODE_OPTIONS="\${NODE_OPTIONS:+\$NODE_OPTIONS }-r \$_OA_COMPAT" ;;
    esac
fi
exec "$GLIBC_LDSO" --library-path "$PREFIX/glibc/lib" "$NODE_DIR/bin/node.real" "\$@"
NODE_WRAPPER
    chmod +x "$BIN_DIR/node"

    # npm wrapper: keep every global install inside the OpenClaw environment and
    # re-apply the OpenClaw shim/patches after an install or update of the CLI.
    cat > "$BIN_DIR/npm" << NPM_WRAPPER
#!$PREFIX/bin/bash
export npm_config_prefix="\${npm_config_prefix:-$PROJECT_DIR}"
"$BIN_DIR/node" "$NODE_DIR/lib/node_modules/npm/bin/npm-cli.js" "\$@"
_oa_npm_rc=\$?
if [ "\${OA_SKIP_NPM_POST:-}" != "1" ]; then
    case " \$* " in
        *" -g "*|*" --global "*)
            case " \$* " in
                *openclaw*)
                    if [ -x "$INSTALLER_COPY" ]; then
                        OA_SKIP_NPM_POST=1 "$PREFIX/bin/bash" "$INSTALLER_COPY" --repair --yes >/dev/null 2>&1 || true
                    fi
                    ;;
            esac
            ;;
    esac
fi
exit \$_oa_npm_rc
NPM_WRAPPER
    chmod +x "$BIN_DIR/npm"

    cat > "$BIN_DIR/npx" << NPX_WRAPPER
#!$PREFIX/bin/bash
exec "$BIN_DIR/node" "$NODE_DIR/lib/node_modules/npm/bin/npx-cli.js" "\$@"
NPX_WRAPPER
    chmod +x "$BIN_DIR/npx"

    # corepack ships with a #!/usr/bin/env node shebang; point it at our wrapper.
    if [ -f "$NODE_DIR/bin/corepack" ] && head -1 "$NODE_DIR/bin/corepack" 2>/dev/null | grep -q '#!/usr/bin/env node'; then
        sed -i "1s|#!/usr/bin/env node|#!$BIN_DIR/node|" "$NODE_DIR/bin/corepack"
    fi
}

resolve_node_download() {
    if [ -n "$NODE_VERSION" ]; then
        log_step "Resolving Node.js v${NODE_VERSION}..."
    else
        log_step "Resolving Node.js ${NODE_MAJOR}.x..."
    fi

    if [ -n "$NODE_VERSION" ]; then
        NODE_DIST_BASE="https://nodejs.org/dist/v${NODE_VERSION}"
    else
        NODE_DIST_BASE="https://nodejs.org/dist/latest-v${NODE_MAJOR}.x"
    fi

    local shasums
    if ! shasums=$(curl -fsSL --max-time 60 "$NODE_DIST_BASE/SHASUMS256.txt"); then
        log_error "Failed to download Node.js checksums from $NODE_DIST_BASE"
        exit 1
    fi

    if [ -n "$NODE_VERSION" ]; then
        NODE_TARBALL="node-v${NODE_VERSION}-linux-arm64.tar.xz"
    else
        NODE_TARBALL=$(printf '%s\n' "$shasums" \
            | awk '{print $2}' \
            | grep -E "^node-v${NODE_MAJOR}\.[0-9]+\.[0-9]+-linux-arm64\.tar\.xz$" \
            | head -1)
    fi

    if [ -z "$NODE_TARBALL" ]; then
        log_error "Could not find a linux-arm64 Node.js ${NODE_MAJOR}.x build"
        exit 1
    fi

    NODE_VERSION=$(printf '%s' "$NODE_TARBALL" | sed -E 's/^node-v([0-9]+\.[0-9]+\.[0-9]+)-linux-arm64\.tar\.xz$/\1/')
    NODE_EXPECTED_SHA=$(printf '%s\n' "$shasums" | awk -v f="$NODE_TARBALL" '$2 == f {print $1; exit}')

    if ! [[ "$NODE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || [ -z "$NODE_EXPECTED_SHA" ]; then
        log_error "Could not resolve a valid Node.js version (got: ${NODE_VERSION:-unknown})"
        exit 1
    fi

    log_success "Node.js v${NODE_VERSION} (${NODE_TARBALL})"
}

installed_node_version() {
    local out=""
    if [ -x "$BIN_DIR/node" ]; then
        out=$("$BIN_DIR/node" --version 2>/dev/null || true)
    elif [ -x "$NODE_DIR/bin/node.real" ]; then
        out=$(env -u LD_PRELOAD -u NODE_OPTIONS "$GLIBC_LDSO" \
            --library-path "$PREFIX/glibc/lib" "$NODE_DIR/bin/node.real" --version 2>/dev/null || true)
    fi
    printf '%s' "${out#v}"
}

install_nodejs() {
    log_step "Installing Node.js v${NODE_VERSION} (glibc)..."

    # A previous run may have stopped between the two renames of the swap.
    if [ -d "$NODE_OLD" ] && [ ! -d "$NODE_DIR" ]; then
        mv "$NODE_OLD" "$NODE_DIR"
        log_warn "Restored Node.js from an interrupted update"
    fi

    local current
    current="$(installed_node_version)"
    if [ "$current" = "$NODE_VERSION" ] && [ -x "$NODE_DIR/bin/node.real" ]; then
        log_success "Node.js v${NODE_VERSION} already installed"
        rm -rf "$NODE_OLD" "$NODE_NEW"
        write_node_wrappers
        configure_npm
        return 0
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d "$PREFIX/tmp/node-install.XXXXXX") || {
        log_error "Could not create a temporary directory"
        exit 1
    }

    local tarball_path="$tmp_dir/$NODE_TARBALL"
    log_info "Downloading $NODE_TARBALL (~30 MB)..."
    if ! curl -fL --retry 3 --max-time 600 "$NODE_DIST_BASE/$NODE_TARBALL" -o "$tarball_path"; then
        rm -rf "$tmp_dir"
        log_error "Failed to download Node.js v${NODE_VERSION}"
        log_info "Check your network connection and try again."
        exit 1
    fi

    local actual_sha
    actual_sha=$(sha256sum "$tarball_path" | awk '{print $1}')
    if [ "$actual_sha" != "$NODE_EXPECTED_SHA" ]; then
        rm -rf "$tmp_dir"
        log_error "Checksum mismatch for $NODE_TARBALL"
        log_info "expected: $NODE_EXPECTED_SHA"
        log_info "actual:   $actual_sha"
        exit 1
    fi
    log_success "sha256 verified"

    log_info "Extracting Node.js..."
    rm -rf "$NODE_NEW"
    mkdir -p "$NODE_NEW"
    if ! tar -xJf "$tarball_path" -C "$NODE_NEW" --strip-components=1; then
        rm -rf "$tmp_dir" "$NODE_NEW"
        log_error "Failed to extract Node.js"
        exit 1
    fi
    rm -rf "$tmp_dir"

    # The wrapper executes node.real through ld.so.
    mv "$NODE_NEW/bin/node" "$NODE_NEW/bin/node.real"

    local staged_version
    staged_version=$(env -u LD_PRELOAD -u NODE_OPTIONS "$GLIBC_LDSO" \
        --library-path "$PREFIX/glibc/lib" "$NODE_NEW/bin/node.real" --version 2>/dev/null || true)

    if [ "$staged_version" != "v$NODE_VERSION" ]; then
        rm -rf "$NODE_NEW"
        log_error "The downloaded Node.js does not run (got: '${staged_version:-nothing}')"
        log_info "This usually means the glibc runtime is incomplete."
        exit 1
    fi
    log_success "Node.js $staged_version runs through the glibc loader"

    local had_previous=false
    rm -rf "$NODE_OLD"
    if [ -d "$NODE_DIR" ]; then
        mv "$NODE_DIR" "$NODE_OLD"
        had_previous=true
    fi
    mv "$NODE_NEW" "$NODE_DIR"

    write_node_wrappers
    configure_npm

    local node_ver npm_ver
    node_ver=$("$BIN_DIR/node" --version 2>/dev/null || true)
    npm_ver=$("$BIN_DIR/npm" --version 2>/dev/null || true)
    if [ "$node_ver" != "v$NODE_VERSION" ] || [ -z "$npm_ver" ]; then
        log_error "Node.js verification failed (node: '${node_ver:-none}', npm: '${npm_ver:-none}')"
        if [ "$had_previous" = "true" ] && [ -d "$NODE_OLD" ]; then
            rm -rf "$NODE_DIR"
            mv "$NODE_OLD" "$NODE_DIR"
            log_info "Restored the previous Node.js installation"
        fi
        exit 1
    fi

    rm -rf "$NODE_OLD"
    log_success "Node.js $node_ver installed (npm $npm_ver)"
}

configure_npm() {
    export npm_config_prefix="$PROJECT_DIR"
    export npm_config_script_shell="$PREFIX/bin/sh"
    export npm_config_fund=false
    export npm_config_audit=false
    export npm_config_update_notifier=false

    "$BIN_DIR/npm" config set fund false >/dev/null 2>&1 || true
    "$BIN_DIR/npm" config set audit false >/dev/null 2>&1 || true
    "$BIN_DIR/npm" config set update-notifier false >/dev/null 2>&1 || true
    "$BIN_DIR/npm" config set script-shell "$PREFIX/bin/sh" >/dev/null 2>&1 || true
}

# ------------------------------------------------------------------------------
# OpenClaw
# ------------------------------------------------------------------------------
locate_openclaw() {
    OPENCLAW_DIR=""
    local candidate root

    for candidate in \
        "$PROJECT_DIR/lib/node_modules/openclaw" \
        "$NODE_DIR/lib/node_modules/openclaw" \
        "$PREFIX/lib/node_modules/openclaw"; do
        if [ -f "$candidate/package.json" ]; then
            OPENCLAW_DIR="$candidate"
            break
        fi
    done

    if [ -z "$OPENCLAW_DIR" ] && [ -x "$BIN_DIR/npm" ]; then
        root=$(npm_config_prefix="$PROJECT_DIR" "$BIN_DIR/npm" root -g 2>/dev/null | tail -1 || true)
        if [ -n "$root" ] && [ -f "$root/openclaw/package.json" ]; then
            OPENCLAW_DIR="$root/openclaw"
        fi
    fi

    [ -n "$OPENCLAW_DIR" ]
}

install_openclaw() {
    log_step "Installing OpenClaw..."

    if [ "$OPENCLAW_VERSION" != "$OPENCLAW_VERIFIED_VERSION" ]; then
        log_warn "Installing OpenClaw ${OPENCLAW_VERSION}; the embedded patches are verified for ${OPENCLAW_VERIFIED_VERSION}"
    fi

    local spec="$OPENCLAW_PACKAGE"
    if [ -n "$OPENCLAW_VERSION" ] && [ "$OPENCLAW_VERSION" != "latest" ]; then
        spec="$OPENCLAW_PACKAGE@$OPENCLAW_VERSION"
    fi

    export npm_config_prefix="$PROJECT_DIR"
    export npm_config_script_shell="$PREFIX/bin/sh"
    export npm_config_fund=false
    export npm_config_audit=false
    export npm_config_update_notifier=false
    export npm_config_ignore_scripts=true
    # Prevent our npm wrapper from running --repair before postinstall/patches.
    export OA_SKIP_NPM_POST=1

    if [ "$REINSTALL" = "true" ]; then
        log_info "Reinstall requested - removing the previous OpenClaw package"
        rm -rf "$PROJECT_DIR/lib/node_modules/openclaw" 2>/dev/null || true
        rm -f "$BIN_DIR/openclaw" "$PREFIX/bin/openclaw" 2>/dev/null || true
    fi

    # Remove our previous launcher (a regular file) as well as any npm symlink:
    # npm refuses to create its bin link over an existing file.
    rm -f "$BIN_DIR/openclaw" "$PREFIX/bin/openclaw" 2>/dev/null || true

    log_info "Running: npm install -g $spec --ignore-scripts"
    log_info "This may take several minutes..."
    if ! "$BIN_DIR/npm" install -g "$spec" --ignore-scripts --no-fund --no-audit; then
        unset OA_SKIP_NPM_POST
        log_error "OpenClaw installation failed"
        log_info "Common causes on Android/Termux:"
        log_info "  - Not enough free storage"
        log_info "  - Network interruption while downloading packages"
        log_info "  - The requested version does not exist on npm"
        log_info "Try: npm cache clean --force, then run the installer again."
        exit 1
    fi
    unset OA_SKIP_NPM_POST

    if ! locate_openclaw; then
        log_error "OpenClaw was installed but its package directory was not found"
        exit 1
    fi
    log_success "OpenClaw package installed at $OPENCLAW_DIR"

    # --ignore-scripts skips OpenClaw's own bundled-plugin postinstall. Run it
    # explicitly, with nested lifecycle scripts disabled (native builds fail here).
    if [ -f "$OPENCLAW_DIR/scripts/postinstall-bundled-plugins.mjs" ]; then
        log_info "Running OpenClaw's bundled-plugin postinstall..."
        if ( cd "$OPENCLAW_DIR" && npm_config_ignore_scripts=true \
                "$BIN_DIR/node" scripts/postinstall-bundled-plugins.mjs ); then
            log_success "Bundled plugins installed"
        else
            log_warn "OpenClaw postinstall reported errors (continuing)"
        fi
    else
        log_warn "OpenClaw postinstall script not found (continuing)"
    fi

    # npm 11.16+ / npm 12 can also exit successfully while lifecycle scripts
    # were skipped. The marker is removed by the postinstall itself.
    if [ -e "$OPENCLAW_DIR/.openclaw-lifecycle-pending" ] || \
            [ -e "$OPENCLAW_DIR/dist/openclaw-install-guard" ]; then
        log_error "OpenClaw lifecycle scripts did not complete"
        log_info "Run this installer again with --reinstall."
        exit 1
    fi
}

apply_path_patches() {
    log_step "Patching Android paths inside OpenClaw..."

    local patched=0 f files

    # Paths are read line by line (`while ... read`), so a file name containing a
    # space cannot be split into two bogus paths the way `for f in $files` would.
    #
    # /tmp -> $PREFIX/tmp. Only files that still contain the original strings are
    # touched, so repeated runs are cheap and idempotent.
    files=$(grep -rlF -e '"/tmp/' -e "'/tmp/" -e '`/tmp/' -e '"/tmp"' -e "'/tmp'" \
        "$OPENCLAW_DIR" --include='*.js' --include='*.mjs' --include='*.cjs' 2>/dev/null || true)
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        sed -i "s|\"\/tmp/|\"$PREFIX/tmp/|g" "$f"
        sed -i "s|'\/tmp/|'$PREFIX/tmp/|g" "$f"
        sed -i "s|\`\/tmp/|\`$PREFIX/tmp/|g" "$f"
        sed -i "s|\"\/tmp\"|\"$PREFIX/tmp\"|g" "$f"
        sed -i "s|'\/tmp'|'$PREFIX/tmp'|g" "$f"
        patched=$((patched + 1))
    done <<< "$files"

    # /bin/sh and /bin/bash do not exist (or are the wrong shell) in Termux;
    # /usr/bin/env does not exist either. Point them at the Termux binaries.
    for pattern in '/bin/sh' '/bin/bash'; do
        files=$( { grep -rl "\"$pattern\"" "$OPENCLAW_DIR" --include='*.js' --include='*.mjs' --include='*.cjs' 2>/dev/null || true
                   grep -rl "'$pattern'" "$OPENCLAW_DIR" --include='*.js' --include='*.mjs' --include='*.cjs' 2>/dev/null || true; } | sort -u)
        while IFS= read -r f; do
            [ -n "$f" ] && [ -f "$f" ] || continue
            sed -i "s|\"$pattern\"|\"$PREFIX$pattern\"|g" "$f" 2>/dev/null || true
            sed -i "s|'$pattern'|'$PREFIX$pattern'|g" "$f" 2>/dev/null || true
            patched=$((patched + 1))
        done <<< "$files"
    done

    files=$( { grep -rl '"/usr/bin/env"' "$OPENCLAW_DIR" --include='*.js' --include='*.mjs' --include='*.cjs' 2>/dev/null || true
               grep -rl "'/usr/bin/env'" "$OPENCLAW_DIR" --include='*.js' --include='*.mjs' --include='*.cjs' 2>/dev/null || true; } | sort -u)
    while IFS= read -r f; do
        [ -n "$f" ] && [ -f "$f" ] || continue
        sed -i "s|\"/usr/bin/env\"|\"$PREFIX/bin/env\"|g" "$f" 2>/dev/null || true
        sed -i "s|'/usr/bin/env'|'$PREFIX/bin/env'|g" "$f" 2>/dev/null || true
        patched=$((patched + 1))
    done <<< "$files"

    if [ "$patched" -eq 0 ]; then
        log_info "No hardcoded paths needed patching"
    else
        log_success "Patched $patched file(s) for Android paths"
    fi
}

apply_hardlink_patch() {
    log_step "Applying Android hard-link / gateway-lock patches..."

    local list_file roots=() out rc=0
    list_file=$(mktemp "$TMPDIR/oa-hardlink-list.XXXXXX") || {
        log_warn "Could not create a temporary file for the hard-link patch"
        return 0
    }

    [ -d "$OPENCLAW_DIR/dist" ] && roots+=("$OPENCLAW_DIR/dist")
    [ -d "$OPENCLAW_DIR/node_modules/@openclaw/fs-safe/dist" ] && \
        roots+=("$OPENCLAW_DIR/node_modules/@openclaw/fs-safe/dist")

    if [ "${#roots[@]}" -eq 0 ]; then
        rm -f "$list_file"
        log_warn "OpenClaw dist directory not found - hard-link patch skipped"
        return 0
    fi

    grep -rlF --include='*.js' --include='*.mjs' --include='*.cjs' \
        -e 'HARDLINK_FALLBACK_CODES' \
        -e 'NATIVE_COPY_FALLBACK_CODES' \
        -e 'function moveMigrationArtifact(' \
        -e '__oaMoveMigrationArtifactOrig' \
        -e 'function createNativeCopyFile' \
        -e 'function assertNativeCopyCompleted' \
        -e 'Cannot discard a recovery publication created by an earlier run' \
        -e '/proc/self/ns/pid' \
        "${roots[@]}" > "$list_file" 2>/dev/null || true

    if command -v timeout &>/dev/null; then
        out=$(timeout 180 "$BIN_DIR/node" "$PATCH_DIR/openclaw-patch-hardlink.js" \
            "$OPENCLAW_DIR" --list "$list_file" 2>&1) || rc=$?
    else
        out=$("$BIN_DIR/node" "$PATCH_DIR/openclaw-patch-hardlink.js" \
            "$OPENCLAW_DIR" --list "$list_file" 2>&1) || rc=$?
    fi
    rm -f "$list_file"

    local summary
    summary=$(printf '%s\n' "$out" | grep '^SUMMARY ' | tail -1 | sed 's/^SUMMARY //' || true)

    # Node has been seen to print its summary and then stay alive until the
    # timeout fires. In that case the patches were already written.
    if [ "$rc" -eq 0 ] || [[ "$summary" == *"problems=0"* ]]; then
        log_success "Android patches applied (${summary:-ok})"
    else
        log_warn "Android patch step reported problems (${summary:-no summary})"
        printf '%s\n' "$out" | grep -E 'NOMATCH|NOTARGET|WRITEFAIL' | while IFS= read -r line; do
            log_warn "$line"
        done
        log_info "OpenClaw may still work, but 'openclaw doctor --fix' can fail with EACCES."
        log_info "This usually means the OpenClaw version is newer than the embedded patches."
    fi
}

write_openclaw_shim() {
    local entry="$OPENCLAW_DIR/openclaw.mjs"
    if [ ! -f "$entry" ]; then
        entry="$OPENCLAW_DIR/dist/index.mjs"
    fi
    if [ ! -f "$entry" ]; then
        log_error "OpenClaw entry point not found in $OPENCLAW_DIR"
        exit 1
    fi

    local shim
    shim=$(cat << SHIM
#!$PREFIX/bin/bash
# OpenClaw launcher for Android/Termux (no proot).
# Generated by termux/no-proot/install.sh. Blocks OpenClaw self-update so the
# patched version stays consistent; use update-claw instead.
export PATH="$BIN_DIR:$NODE_DIR/bin:$PREFIX/bin:\$HOME/.local/bin:\$PATH"
export TMPDIR="$PREFIX/tmp"
export TMP="$PREFIX/tmp"
export TEMP="$PREFIX/tmp"
export OPENCLAW_NO_AUTO_UPDATE="\${OPENCLAW_NO_AUTO_UPDATE:-1}"
_oa_block=false
for _oa_arg in "\$@"; do
    [ "\$_oa_arg" = "--update" ] && _oa_block=true && break
done
if [ "\$_oa_block" = false ]; then
    _oa_skip=false
    _oa_next=false
    for _oa_arg in "\$@"; do
        if [ "\$_oa_next" = true ]; then
            [ "\$_oa_arg" = "status" ] && _oa_block=false
            break
        fi
        if [ "\$_oa_skip" = true ]; then _oa_skip=false; continue; fi
        case "\$_oa_arg" in
            --profile|--container|--log-level) _oa_skip=true ;;
            -*) ;;
            update) _oa_block=true; _oa_next=true ;;
            *) break ;;
        esac
    done
fi
if [ "\$_oa_block" = true ]; then
    echo "[BLOCKED] OpenClaw is updated through this installer to keep the Android patches." >&2
    echo "          Run 'update-claw' instead. ('openclaw update status' is allowed.)" >&2
    exit 1
fi
if [ ! -f "$entry" ]; then
    echo "[FAIL] OpenClaw is not installed ($entry missing). Run 'update-claw'." >&2
    exit 127
fi
exec "$BIN_DIR/node" "$entry" "\$@"
SHIM
)

    # Remove first: '>' would follow an npm symlink and overwrite its target.
    rm -f "$BIN_DIR/openclaw" "$PREFIX/bin/openclaw" 2>/dev/null || true
    printf '%s\n' "$shim" > "$BIN_DIR/openclaw"
    chmod +x "$BIN_DIR/openclaw"
    # Expose the launcher on PATH without creating a second generated script.
    ln -s "$BIN_DIR/openclaw" "$PREFIX/bin/openclaw"

    log_success "OpenClaw launcher installed"
}

write_systemctl_stub() {
    local stub="$BIN_DIR/systemctl"

    cat > "$stub" << 'SYSTEMCTL'
#!/usr/bin/env bash
# systemctl stub for Termux/Android (systemd is unavailable).
#
# Scope: this file lives in ~/.openclaw-android/bin, which is on PATH for
# OpenClaw and start-claw only. It is deliberately NOT linked into
# $PREFIX/bin: a fake systemctl there would shadow the real command for every
# other program in Termux.
#
# Only "restart" is emulated (OpenClaw asks systemctl to restart the gateway).
# Every other invocation answers like systemd does outside systemd - non-zero
# with its message - so OpenClaw takes its normal "no systemd" path instead of
# believing a service manager is present.
for arg in "$@"; do
    if [ "$arg" = "restart" ]; then
        if ! openclaw gateway config.patch \
            "{\"meta\":{\"restartNonce\":\"$(date +%s%N)\"}}" 2>/dev/null; then
            openclaw gateway 2>/dev/null || true
        fi
        exit 0
    fi
done
echo "System has not been booted with systemd as init system (PID 1). Can't operate." >&2
echo "Failed to connect to bus: Host is down" >&2
exit 1
SYSTEMCTL
    # /usr/bin/env does not exist in Termux and glibc child processes do not get
    # termux-exec's path translation, so use the absolute Termux shell.
    sed -i "1s|^#!/usr/bin/env bash$|#!$PREFIX/bin/bash|" "$stub"
    chmod +x "$stub"

    # Remove the symlink older versions of this installer created: the stub must
    # not shadow systemctl globally.
    rm -f "$PREFIX/bin/systemctl" 2>/dev/null || true
}

openclaw_run() {
    local timeout_seconds="$1"
    shift

    if command -v timeout &>/dev/null; then
        timeout "$timeout_seconds" "$BIN_DIR/openclaw" "$@"
    else
        "$BIN_DIR/openclaw" "$@"
    fi
}

configure_openclaw_settings() {
    log_step "Configuring OpenClaw update policy..."

    if [ ! -x "$BIN_DIR/openclaw" ]; then
        log_warn "OpenClaw launcher missing - update policy not configured"
        return 0
    fi

    # OPENCLAW_NO_AUTO_UPDATE=1 already covers the installer run; persisting the
    # setting also disables the Gateway's start-up update check.
    mkdir -p "$HOME/.openclaw"
    local out
    if out=$(openclaw_run 90 config set update.checkOnStart false 2>&1); then
        log_success "Disabled OpenClaw update checks on gateway start"
    else
        log_warn "Could not set update.checkOnStart=false (continuing)"
        printf '%s\n' "$out" | tail -3 | sed 's/^/  /'
    fi
}

run_doctor() {
    log_step "Running OpenClaw doctor (migrations)..."

    export PATH="$BIN_DIR:$NODE_DIR/bin:$HOME/.local/bin:$PATH"
    if command -v timeout &>/dev/null; then
        timeout 300 "$BIN_DIR/openclaw" doctor --fix --non-interactive \
            || log_warn "openclaw doctor reported issues (non-fatal)"
    else
        "$BIN_DIR/openclaw" doctor --fix --non-interactive \
            || log_warn "openclaw doctor reported issues (non-fatal)"
    fi
}

# ------------------------------------------------------------------------------
# Shell configuration and helpers
# ------------------------------------------------------------------------------
configure_bashrc() {
    log_step "Configuring shell environment..."

    touch "$BASHRC"

    # Replace the previous no-proot block so re-running the installer does not
    # duplicate it. Only when both markers are present: deleting from a start
    # marker without an end marker would truncate the rest of the file.
    if grep -qF "$BASHRC_START" "$BASHRC" && grep -qF "$BASHRC_END" "$BASHRC"; then
        sed -i "/$BASHRC_START/,/$BASHRC_END/d" "$BASHRC"
    fi

    cat >> "$BASHRC" << 'BASHRC_BLOCK'

# >>> openclaw-android (no-proot) >>>
# OpenClaw runs directly in Termux through the glibc loader (no proot/Debian).
export PATH="$HOME/.openclaw-android/bin:$HOME/.openclaw-android/node/bin:$HOME/.local/bin:$PATH"
export TMPDIR="$PREFIX/tmp"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"
export OPENCLAW_NO_AUTO_UPDATE=1

alias start-claw='openclaw gateway --bind loopback'
alias update-claw='bash "$HOME/.openclaw-android/update-claw.sh"'
alias claw-status='openclaw gateway status'
alias claw-logs='openclaw logs --follow'
alias claw-doctor='openclaw doctor'
alias claw-dashboard='openclaw dashboard'
alias claw-ps='ps aux | grep -i openclaw | grep -v grep'

if [ -n "${PS1:-}" ] && [ -z "${OPENCLAW_NO_BANNER:-}" ]; then
    echo ""
    echo -e "\033[0;36mOpenClaw (no-proot) ready.\033[0m"
    echo "  First run: openclaw onboard   |   Start: start-claw   |   TUI: openclaw tui"
    echo ""
fi
# <<< openclaw-android (no-proot) <<<
BASHRC_BLOCK

    log_success "Bashrc configured"
}

create_helper_scripts() {
    log_step "Creating helper scripts..."

    mkdir -p "$PROJECT_DIR"

    cat > "$START_HELPER" << 'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
export PATH="$HOME/.openclaw-android/bin:$HOME/.openclaw-android/node/bin:$PREFIX/bin:$HOME/.local/bin:$PATH"
export TMPDIR="$PREFIX/tmp"
export TMP="$TMPDIR"
export TEMP="$TMPDIR"
export OPENCLAW_NO_AUTO_UPDATE=1
exec "$HOME/.openclaw-android/bin/openclaw" gateway --bind loopback "$@"
LAUNCHER
    chmod +x "$START_HELPER"

    cat > "$UPDATE_HELPER" << UPDATER
#!/data/data/com.termux/files/usr/bin/bash
set -e
INSTALLER="$INSTALLER_COPY"
if [ -s "\$INSTALLER" ]; then
    exec "$PREFIX/bin/bash" "\$INSTALLER" --update --yes "\$@"
fi
echo "Installer copy not found; downloading..."
curl -fsSL "$SCRIPT_URL" | bash -s -- --update --yes "\$@"
UPDATER
    chmod +x "$UPDATE_HELPER"

    log_success "Helper scripts created under $PROJECT_DIR: start-openclaw.sh, update-claw.sh"
}

install_self_copy() {
    mkdir -p "$(dirname "$INSTALLER_COPY")"

    local source="${BASH_SOURCE[0]:-}"
    if [ -n "$source" ] && [ -f "$source" ] && [[ "$source" != /dev/fd/* ]] && [[ "$source" != /proc/self/fd/* ]]; then
        cp -f "$source" "$INSTALLER_COPY" 2>/dev/null || true
    fi

    if [ ! -s "$INSTALLER_COPY" ]; then
        curl -fsSL --max-time 30 "$SCRIPT_URL" -o "$INSTALLER_COPY" 2>/dev/null || true
    fi

    if [ -s "$INSTALLER_COPY" ]; then
        chmod +x "$INSTALLER_COPY" 2>/dev/null || true
    else
        log_warn "Could not save a copy of the installer (update-claw will download it)"
        rm -f "$INSTALLER_COPY" 2>/dev/null || true
    fi
}

# ------------------------------------------------------------------------------
# Verification and summary
# ------------------------------------------------------------------------------
verify_install() {
    log_step "Verifying installation..."

    local ok=1

    if [ ! -x "$GLIBC_LDSO" ]; then
        log_error "glibc linker missing: $GLIBC_LDSO"
        ok=0
    else
        log_success "glibc linker present"
    fi

    if [ ! -s "$COMPAT_FILE" ]; then
        log_error "Android compatibility shim missing: $COMPAT_FILE"
        ok=0
    else
        log_success "Android compatibility shim present"
    fi

    local node_ver npm_ver oc_ver
    node_ver=$("$BIN_DIR/node" --version 2>/dev/null || true)
    npm_ver=$("$BIN_DIR/npm" --version 2>/dev/null || true)
    if [ -n "$node_ver" ] && [ -n "$npm_ver" ]; then
        log_success "Node.js $node_ver / npm $npm_ver"
    else
        log_error "Node.js or npm is not working"
        ok=0
    fi

    oc_ver=$(openclaw_run 60 --version 2>/dev/null || true)
    if [ -n "$oc_ver" ]; then
        log_success "OpenClaw $oc_ver"
    else
        log_warn "OpenClaw is installed but 'openclaw --version' failed"
        log_info "Try: openclaw doctor --fix"
    fi

    VERIFY_OK="$ok"
    [ "$ok" -eq 1 ]
}

show_completion() {
    local node_ver oc_ver
    node_ver=$("$BIN_DIR/node" --version 2>/dev/null || echo "unknown")
    oc_ver=$(openclaw_run 60 --version 2>/dev/null || echo "unknown")

    log_step "Installation Summary"

    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                   ║${NC}"
    if [ "${VERIFY_OK:-0}" -eq 1 ]; then
        echo -e "${GREEN}║      OpenClaw Installation Complete!              ║${NC}"
    else
        echo -e "${RED}║      Installation finished WITH ERRORS            ║${NC}"
    fi
    echo -e "${GREEN}║              No PRoot / No Debian                 ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    if [ "${VERIFY_OK:-0}" -ne 1 ]; then
        echo -e "${YELLOW}Some verification checks failed - read the [ERROR] lines above${NC}"
        echo -e "${YELLOW}before using this installation.${NC}"
        echo ""
    fi
    echo -e "${CYAN}Installed Components:${NC}"
    echo "  - glibc runtime (Termux glibc-runner, no Linux distro)"
    echo "  - Node.js $node_ver (official linux-arm64 via ld.so)"
    echo "  - OpenClaw $oc_ver"
    echo "  - Android compatibility shim + hard-link/gateway patches"
    echo ""
    echo -e "${YELLOW}Next Steps:${NC}"
    echo ""
    echo -e "${YELLOW}Step 1:${NC} Load the environment"
    echo "  source ~/.bashrc"
    echo ""
    echo -e "${YELLOW}Step 2:${NC} First-time setup (one time only)"
    echo "  openclaw onboard"
    echo "    (configures your model provider and sets gateway.mode=local)"
    echo ""
    echo -e "${YELLOW}Step 3:${NC} Start the gateway"
    echo "  start-claw"
    echo ""
    echo -e "${YELLOW}Step 4:${NC} Open a new Termux session (swipe left)"
    echo "  openclaw tui"
    echo "  # or open the dashboard:"
    echo "  openclaw dashboard"
    echo ""
    echo -e "${CYAN}Available Commands:${NC}"
    echo "  openclaw onboard    - First-time setup wizard"
    echo "  start-claw          - Start gateway on loopback"
    echo "  openclaw tui        - Terminal interface"
    echo "  openclaw config     - Manual configuration"
    echo "  openclaw dashboard  - Control UI in browser"
    echo "  update-claw         - Update/reinstall OpenClaw via this installer"
    echo "  claw-status         - Gateway status"
    echo "  claw-logs           - Follow gateway logs"
    echo "  claw-doctor         - Health checks and repairs"
    echo ""
    echo -e "${YELLOW}Notes:${NC}"
    echo "  - No Debian, no proot-distro, no 'proot-distro login' step."
    echo "  - Do not run 'openclaw update'; use 'update-claw' so the"
    echo "    Android patches are re-applied after an update."
    echo "  - If Android kills background processes (signal 9), disable the"
    echo "    Phantom Process Killer and set Termux battery usage to Unrestricted."
    echo "    See: ${REFERENCE_URL}/blob/main/docs/disable-phantom-process-killer.md"
    echo ""
    echo -e "${CYAN}Performance Tips:${NC}"
    echo "  - The installer enabled a wake lock; use 'termux-wake-unlock' to release it"
    echo "  - Android Settings -> Apps -> Termux -> Battery -> Unrestricted"
    echo ""
    echo -e "${CYAN}Issues?${NC}"
    echo "  ${REPO_URL}/issues"
    echo ""
}

# ------------------------------------------------------------------------------
# Modes and argument parsing
# ------------------------------------------------------------------------------
validate_node_major() {
    local major="$NODE_MAJOR"
    if [ -n "$NODE_VERSION" ]; then
        major="${NODE_VERSION%%.*}"
        NODE_MAJOR="$major"
    fi

    case "$major" in
        24|26)
            ;;
        25)
            log_error "Node.js 25 is not supported by OpenClaw (>=24.16 <25 || >=26.1)"
            log_info "Use --node 24 (LTS, default) or --node 26"
            exit 1
            ;;
        22|23)
            log_error "Node.js ${major} is no longer supported by OpenClaw"
            log_info "OpenClaw requires Node.js >=24.16.0 <25, or >=26.1.0"
            exit 1
            ;;
        *)
            log_error "Unsupported Node.js major version: ${major}"
            log_info "Supported values: 24 (LTS, default) or 26"
            exit 1
            ;;
    esac
}

repair_mode() {
    log_step "Repairing OpenClaw Android patches..."

    check_termux
    setup_environment
    install_self_copy
    write_compat_shim
    write_hardlink_patcher

    if [ ! -x "$GLIBC_LDSO" ]; then
        log_error "glibc runtime is missing. Run the full installer."
        exit 1
    fi
    if [ ! -x "$BIN_DIR/node" ] || [ ! -f "$NODE_DIR/bin/node.real" ]; then
        log_error "Node.js is missing. Run the full installer."
        exit 1
    fi

    if ! locate_openclaw; then
        log_error "OpenClaw is not installed. Run the full installer."
        exit 1
    fi

    # Refresh everything generated by this installer, so --repair also applies
    # launcher/wrapper changes from a newer installer version.
    write_node_wrappers
    sync_glibc_resolv
    apply_path_patches
    apply_hardlink_patch
    write_openclaw_shim
    write_systemctl_stub
    configure_openclaw_settings

    local ver
    ver=$(openclaw_run 60 --version 2>/dev/null || true)
    if [ -n "$ver" ]; then
        log_success "Repair complete - OpenClaw $ver"
    else
        log_warn "Repair finished but 'openclaw --version' still fails"
        log_info "Run: openclaw doctor --fix"
    fi
}

MODE="install"
REINSTALL=false
SKIP_UPDATE_CHECK=false
ASSUME_YES=false
SCRIPT_ARGS=("$@")

while [[ $# -gt 0 ]]; do
    case $1 in
        --reinstall)
            REINSTALL=true
            shift
            ;;
        --skip-update-check)
            SKIP_UPDATE_CHECK=true
            shift
            ;;
        --yes|-y)
            ASSUME_YES=true
            shift
            ;;
        --node)
            if [ -z "${2:-}" ]; then
                log_error "--node requires a major version (24 or 26)"
                exit 1
            fi
            NODE_MAJOR="$2"
            shift 2
            ;;
        --openclaw)
            if [ -z "${2:-}" ]; then
                log_error "--openclaw requires a version (for example 2026.10.2) or 'latest'"
                exit 1
            fi
            OPENCLAW_VERSION="$2"
            shift 2
            ;;
        --latest)
            OPENCLAW_VERSION="latest"
            shift
            ;;
        --update)
            MODE="update"
            shift
            ;;
        --repair)
            MODE="repair"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --node <24|26>        Node.js major version (default: 24 LTS)"
            echo "  --openclaw <version>  OpenClaw version to install (default: ${OPENCLAW_VERIFIED_VERSION})"
            echo "  --latest              Install the latest OpenClaw (patches may need updates)"
            echo "  --update              Reinstall OpenClaw and re-apply the Android patches"
            echo "  --repair              Only re-apply the Android patches and launcher"
            echo "  --reinstall           Remove the previous OpenClaw package first"
            echo "  --skip-update-check   Skip checking for installer updates"
            echo "  --yes, -y             Assume yes for all prompts (unattended)"
            echo "  --help, -h            Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ------------------------------------------------------------------------------
# Main flow
# ------------------------------------------------------------------------------
main() {
    show_banner
    validate_node_major

    if [ "$MODE" = "repair" ]; then
        repair_mode
        return 0
    fi

    if [ "$SKIP_UPDATE_CHECK" = "false" ]; then
        check_for_updates
    fi

    check_termux
    check_architecture
    check_android_version
    check_storage
    check_existing_install

    setup_environment
    install_self_copy

    install_termux_packages
    # Retry now that curl is guaranteed to exist (important for curl | bash).
    install_self_copy
    install_glibc

    setup_environment
    write_compat_shim
    write_hardlink_patcher

    resolve_node_download
    install_nodejs

    install_openclaw
    apply_path_patches
    apply_hardlink_patch
    write_openclaw_shim
    write_systemctl_stub

    run_doctor
    configure_openclaw_settings

    configure_bashrc
    create_helper_scripts

    # A failed verification must not hide the summary: report the failure and
    # still print what was installed, then exit non-zero.
    local verify_rc=0
    verify_install || verify_rc=1
    show_completion
    return "$verify_rc"
}

main "$@"
