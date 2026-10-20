#!/data/data/com.termux/files/usr/bin/bash
################################################################################
# OpenClaw Android Installer
# Version: 2026.10.21
# Description: Automated installer for OpenClaw on Android via Termux
# Repository: https://github.com/anhkind/openclaw-android
# Upstream reference: https://github.com/iyeoh88-svg/openclaw-android
################################################################################

set -e  # Exit on error

# Script Configuration
SCRIPT_VERSION="2026.10.21"
SCRIPT_URL="https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh"
VERSION_URL="https://raw.githubusercontent.com/anhkind/openclaw-android/main/VERSION"
REPO_URL="https://github.com/anhkind/openclaw-android"
REFERENCE_URL="https://github.com/iyeoh88-svg/openclaw-android"

# Package versions / compatibility floors
# OpenClaw 2026.10.x requires: node >=24.16.0 <25 || >=26.1.0
# Upstream recommends Node 26, but its Linux installer provisions the Node 24
# LTS line, which is what we default to here (Node 26 available via --node 26).
NODE_MAJOR="${OPENCLAW_NODE_MAJOR:-24}"
NVM_VERSION="v0.40.8"
OPENCLAW_PACKAGE="openclaw@latest"
DEBIAN_IMAGE="${OPENCLAW_DEBIAN_IMAGE:-debian:trixie}"
MIN_STORAGE_MB=4096

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "\n${MAGENTA}==>${NC} ${CYAN}$1${NC}\n"
}

# Interactive prompt helper.
# Works when run from a pipe (curl | bash) by reading /dev/tty, and falls back
# to the supplied default when no terminal is attached (CI / unattended runs).
ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response=""

    # Unattended mode: accept without prompting
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

# Ask for a single line of input (used by the Debian menu)
ask_input() {
    local prompt="$1"
    local default="${2:-}"
    local response=""

    echo -n "$prompt"
    if [ -r /dev/tty ]; then
        read -r response < /dev/tty || response=""
    elif [ -t 0 ]; then
        read -r response || response=""
    else
        response=""
    fi
    [ -z "$response" ] && response="$default"
    printf '%s' "$response"
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

# Banner
show_banner() {
    clear 2>/dev/null || printf '\033c'
    echo -e "${CYAN}"
    cat << "EOF"
    ╔═══════════════════════════════════════════════╗
    ║                                               ║
    ║            OpenClaw for Android               ║
    ║                                               ║
    ║      Automated Installation & Setup Tool      ║
    ║                                               ║
    ╚═══════════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    echo -e "  Version: ${GREEN}${SCRIPT_VERSION}${NC}"
    echo -e "  Repository: ${BLUE}${REPO_URL}${NC}"
    echo -e "  Reference:  ${BLUE}${REFERENCE_URL}${NC}"
    echo -e ""
    echo -e "${YELLOW}  ⚠️  DISCLAIMER:${NC} This is a community-created installer."
    echo -e "      OpenClaw framework © its original creators"
    echo -e ""
}

# Check for updates
check_for_updates() {
    log_step "Checking for installer updates..."

    if command -v curl &> /dev/null; then
        # Get latest version, trim whitespace, and only use first line
        LATEST_VERSION=$(curl -fsSL --max-time 15 "$VERSION_URL" 2>/dev/null | head -1 | tr -d '[:space:]')

        # Validate version format (should be like 2026.10.19)
        if ! [[ "$LATEST_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_warn "Unable to check for updates (invalid version format received)"
            LATEST_VERSION="$SCRIPT_VERSION"
        fi

        # If curl failed or returned empty, use current version
        if [ -z "$LATEST_VERSION" ]; then
            LATEST_VERSION="$SCRIPT_VERSION"
        fi

        # Only offer an update when the remote version is actually newer
        if version_gt "$LATEST_VERSION" "$SCRIPT_VERSION"; then
            log_warn "New installer version available: $LATEST_VERSION (current: $SCRIPT_VERSION)"

            if ask_yes_no "Would you like to update the installer?" "n"; then
                log_info "Downloading latest installer..."
                # Use $HOME instead of /tmp to avoid permission issues
                if ! curl -fsSL "$SCRIPT_URL" -o "$HOME/install_new.sh"; then
                    log_error "Failed to download the latest installer"
                    rm -f "$HOME/install_new.sh"
                    log_info "Continuing with current version..."
                else
                    # Only restart when the downloaded copy is really newer. One
                    # VERSION file serves both installers, so it can be ahead of
                    # the published script of this mode; exec'ing it again would
                    # download and exec the same file forever (endless loop with
                    # --yes, which update-claw passes).
                    local downloaded_version
                    downloaded_version=$(sed -n 's/^SCRIPT_VERSION="\([^"]*\)"$/\1/p' \
                        "$HOME/install_new.sh" 2>/dev/null | head -1)

                    if [ "${OPENCLAW_INSTALLER_UPDATED:-0}" = "1" ]; then
                        log_warn "Already restarted once with a downloaded installer - not restarting again"
                        rm -f "$HOME/install_new.sh"
                    elif [ -z "$downloaded_version" ] || \
                            ! version_gt "$downloaded_version" "$SCRIPT_VERSION"; then
                        log_warn "The published installer reports ${downloaded_version:-no version}, not newer than ${SCRIPT_VERSION}"
                        log_info "Continuing with the current installer (the repository VERSION file may be ahead of the published script)."
                        rm -f "$HOME/install_new.sh"
                    else
                        chmod +x "$HOME/install_new.sh"
                        log_success "Installer updated to ${downloaded_version}! Restarting..."
                        export OPENCLAW_INSTALLER_UPDATED=1
                        exec "$HOME/install_new.sh" "${SCRIPT_ARGS[@]}"
                    fi
                fi
            else
                log_info "Continuing with current version..."
            fi
        else
            log_success "Installer is up to date!"
        fi
    else
        log_warn "Unable to check for updates (curl not available)"
    fi
}

# Check if running in Termux
check_termux() {
    if [ ! -d "/data/data/com.termux" ]; then
        log_error "This script must be run in Termux!"
        log_info "Please install Termux from F-Droid: https://f-droid.org/en/packages/com.termux/"
        exit 1
    fi
    log_success "Termux environment detected"
}

# Check device CPU architecture
# Node.js 24+ ships only linux-arm64 / linux-x64 builds: 32-bit ARM (armv7)
# userspaces have no supported runtime, so fail early with a clear message.
check_architecture() {
    log_step "Checking CPU architecture..."

    local arch
    arch="$(uname -m 2>/dev/null || echo unknown)"
    log_info "Architecture: $arch"

    case "$arch" in
        aarch64|arm64|x86_64|amd64)
            log_success "64-bit architecture supported"
            ;;
        armv7l|armv8l|arm|armhf|i686|i386)
            log_error "32-bit architecture detected ($arch)"
            log_error "OpenClaw requires Node.js 24.16+ / 26.1+, which has no 32-bit ARM builds."
            log_info "On a 64-bit device, install 64-bit Termux (arm64 build) and retry."
            log_info "See: https://github.com/termux/termux-app/releases"
            exit 1
            ;;
        *)
            log_warn "Unrecognized architecture ($arch) - continuing, but Node.js may not install"
            ;;
    esac
}

# Check Android version
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

# Check available storage
check_storage() {
    log_step "Checking available storage..."

    # Use df -k (more compatible) and convert to MB
    AVAILABLE_KB=$(df -k "$HOME" 2>/dev/null | tail -1 | awk '{print $4}')

    # Check if we got a valid number
    if [ -z "$AVAILABLE_KB" ] || ! [[ "$AVAILABLE_KB" =~ ^[0-9]+$ ]]; then
        log_warn "Unable to check available storage automatically"
        log_info "Please ensure you have at least 4GB free space (6GB+ recommended)"
        if ! ask_yes_no "Continue anyway?" "n"; then
            log_info "Installation cancelled"
            exit 0
        fi
        return 0
    fi

    # Convert KB to MB
    AVAILABLE_MB=$((AVAILABLE_KB / 1024))
    log_info "Available storage: ${AVAILABLE_MB}MB"

    # OpenClaw 2026.10.x unpacks to ~250MB on its own, plus Debian, Node.js and apt caches
    if [ "$AVAILABLE_MB" -lt "$MIN_STORAGE_MB" ]; then
        log_error "Insufficient storage! At least 4GB required, ${AVAILABLE_MB}MB available"
        log_info "Please free up some space and try again"
        exit 1
    fi

    if [ "$AVAILABLE_MB" -lt 6144 ]; then
        log_warn "6GB+ recommended for a comfortable install (Node.js + OpenClaw + Debian)"
    fi

    log_success "Storage check passed"
}

# Install Termux packages
install_termux_packages() {
    log_step "Installing Termux packages..."

    log_info "Updating package lists..."
    pkg update -y || log_warn "pkg update reported errors, continuing..."

    log_info "Upgrading existing packages..."
    # Set environment to avoid interactive prompts
    export DEBIAN_FRONTEND=noninteractive
    # Use apt options to automatically handle config file changes
    apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" || log_warn "apt-get upgrade reported errors, continuing..."

    log_info "Installing proot-distro (v5.x, OCI image support)..."
    pkg install -y proot-distro curl

    log_success "Termux packages installed"
}

# Returns 0 if the installed proot-distro supports the v5 CLI (--name, OCI images)
proot_distro_is_v5() {
    proot-distro install --help 2>&1 | grep -q -- '--name'
}

# Install the Debian container (v5: Docker image, v4: built-in distro plugin)
install_debian_distro() {
    if proot_distro_is_v5; then
        proot-distro install --name debian "$DEBIAN_IMAGE"
    else
        log_warn "Old proot-distro detected (v4.x). Consider running 'pkg upgrade' for v5."
        proot-distro install debian
    fi
}

# Check whether the Debian container exists (supports v5 and legacy v4 layouts)
debian_rootfs_dir() {
    if [ -d "$PREFIX/var/lib/proot-distro/containers/debian/rootfs" ]; then
        echo "$PREFIX/var/lib/proot-distro/containers/debian/rootfs"
    elif [ -d "$PREFIX/var/lib/proot-distro/installed-rootfs/debian" ]; then
        echo "$PREFIX/var/lib/proot-distro/installed-rootfs/debian"
    else
        echo ""
    fi
}

debian_is_installed() {
    # v5 layout: containers/<name>/rootfs
    # Legacy v4 layout: installed-rootfs/<name>
    if [ -n "$(debian_rootfs_dir)" ]; then
        return 0
    fi

    # Fall back to the CLI (proot-distro v5 lists container names with -q)
    set +e
    proot-distro list -q 2>/dev/null | grep -qx "debian"
    local v5_result=$?
    set -e

    [ $v5_result -eq 0 ]
}

# Install Debian distribution
install_debian() {
    log_step "Checking Debian installation status..."

    if debian_is_installed; then
        log_warn "Debian is already installed"

        if [ "$REINSTALL" = "true" ]; then
            log_info "Reinstalling Debian (--reinstall flag)..."
            proot-distro remove debian 2>/dev/null || true
            install_debian_distro
            return 0
        fi

        echo ""
        echo -e "${YELLOW}═══════════════════════════════════════${NC}"
        echo -e "${YELLOW}   Debian is already installed${NC}"
        echo -e "${YELLOW}═══════════════════════════════════════${NC}"
        echo ""
        echo "What would you like to do?"
        echo ""
        echo "  [1] Keep existing and add/refresh openclaw user"
        echo "  [2] Fresh install (removes existing)"
        echo "  [3] Exit"
        echo ""

        if [ "$ASSUME_YES" = "true" ]; then
            response="1"
            log_info "Unattended mode: keeping existing Debian installation"
        else
            response=$(ask_input "Choice [1-3]: " "1")
        fi

        echo ""

        case "$response" in
            1)
                log_info "Using existing Debian installation"
                return 0
                ;;
            2)
                log_info "Removing existing Debian..."
                proot-distro remove debian
                log_info "Installing fresh Debian..."
                install_debian_distro
                return 0
                ;;
            3)
                log_info "Exiting..."
                exit 0
                ;;
            *)
                log_info "Using existing Debian (default)"
                return 0
                ;;
        esac
    else
        # Debian NOT installed - install it
        log_info "Installing Debian distribution (${DEBIAN_IMAGE})..."
        install_debian_distro
        return 0
    fi
}
# Create setup script for Debian environment
create_debian_setup() {
    log_step "Creating Debian setup script..."

    # Use $HOME instead of /tmp to avoid permission issues
    cat > "$HOME/debian_setup.sh" << 'DEBIAN_SCRIPT'
#!/bin/bash
set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${GREEN}==>${NC} $1"; }

# Versions (injected by the Termux-side installer)
NODE_MAJOR="__NODE_MAJOR__"
NVM_VERSION="__NVM_VERSION__"
OPENCLAW_PACKAGE="__OPENCLAW_PACKAGE__"

echo -e "\n${GREEN}==> Setting up Debian environment...${NC}\n"

# -----------------------------------------------------------------------
# Step 0 – Fix any interrupted dpkg operations (for existing installations)
# -----------------------------------------------------------------------
log_step "Checking for interrupted package operations..."
dpkg --configure -a 2>/dev/null || true
apt-get -f install -y 2>/dev/null || true

# -----------------------------------------------------------------------
# Step 1 – Base packages (runs as root)
# -----------------------------------------------------------------------
log_step "Updating Debian packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"

log_step "Installing build dependencies..."
# xz-utils is required by nvm to extract the official Node.js .tar.xz builds
# passwd provides useradd/usermod, procps provides ps for the status helpers
# libatomic1 is required by the official Node.js ARM64 binaries
# python3 + cmake match the build tools OpenClaw's upstream installer provisions
apt-get install -y \
    curl \
    git \
    build-essential \
    python3 \
    cmake \
    ca-certificates \
    sudo \
    passwd \
    procps \
    xz-utils \
    libatomic1

# -----------------------------------------------------------------------
# Step 2 – Create dedicated non-root user "openclaw"
# -----------------------------------------------------------------------
log_step "Setting up dedicated user 'openclaw'..."

if id "openclaw" &>/dev/null; then
    log_info "User 'openclaw' already exists"
else
    log_info "Creating user 'openclaw'..."
    useradd -m -s /bin/bash openclaw
    log_success "User 'openclaw' created"
fi

# Passwordless sudo via a drop-in file (safer than editing /etc/sudoers)
if [ -d /etc/sudoers.d ]; then
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-openclaw
    chmod 0440 /etc/sudoers.d/90-openclaw
    log_success "Sudo access granted to 'openclaw'"
else
    echo "openclaw ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
    log_success "Sudo access granted to 'openclaw'"
fi

# -----------------------------------------------------------------------
# Step 3 – Everything else runs as the 'openclaw' user
# -----------------------------------------------------------------------
log_step "Setting up environment for user 'openclaw'..."

su - openclaw << 'USER_SCRIPT'

# Colors inside su subshell
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

NODE_MAJOR="__NODE_MAJOR__"
NVM_VERSION="__NVM_VERSION__"
OPENCLAW_PACKAGE="__OPENCLAW_PACKAGE__"

# Install NVM (pinned version)
if [ ! -s "$HOME/.nvm/nvm.sh" ]; then
    log_info "Installing NVM ${NVM_VERSION}..."
    curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
fi

# Source NVM - multiple fallback methods
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if [ -s "$HOME/.bashrc" ]; then
    grep -q 'NVM_DIR' "$HOME/.bashrc" && . "$HOME/.bashrc"
fi

if ! command -v nvm &>/dev/null; then
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"
fi

if ! command -v nvm &>/dev/null; then
    log_error "NVM failed to load"
    exit 1
fi

log_success "NVM $(nvm --version) loaded"

# Install Node.js (OpenClaw requires >=24.16.0; Node 24 LTS recommended)
log_info "Installing Node.js v${NODE_MAJOR} (latest ${NODE_MAJOR}.x)..."
nvm install "$NODE_MAJOR"
nvm use "$NODE_MAJOR"
nvm alias default "$NODE_MAJOR"

NODE_VERSION="$(node -p 'process.versions.node')"
log_success "Node.js v${NODE_VERSION} installed (npm $(npm --version))"

# Verify the runtime satisfies OpenClaw's engine floor
node_is_supported() {
    local current="$1"
    local major="${current%%.*}"
    local rest="${current#*.}"
    local minor="${rest%%.*}"

    if [ "$major" -eq 24 ] && [ "$minor" -ge 16 ]; then
        return 0
    fi
    if [ "$major" -eq 26 ] && [ "$minor" -ge 1 ]; then
        return 0
    fi
    if [ "$major" -gt 26 ]; then
        return 0
    fi

    return 1
}

if ! node_is_supported "$NODE_VERSION"; then
    log_error "Node.js v${NODE_VERSION} is outside OpenClaw's supported range"
    log_error "OpenClaw requires >=24.16.0 <25 || >=26.1.0"
    exit 1
fi

# Create the Android/proot runtime shim in the user's home
log_info "Creating Android runtime compatibility shim..."
cat > "$HOME/openclaw-shim.cjs" << 'EOF'
// Android/proot safety net for OpenClaw.
const os = require('os');
const fs = require('fs');

// --- Android networking fallback -------------------------------------------
// os.networkInterfaces() can throw (or return an empty map) in some
// Termux/proot setups. Only fall back to loopback in that case so real
// interfaces keep working when they are readable.
const originalNetworkInterfaces = os.networkInterfaces.bind(os);

os.networkInterfaces = () => {
  try {
    const interfaces = originalNetworkInterfaces();
    if (interfaces && Object.keys(interfaces).length > 0) {
      return interfaces;
    }
  } catch (_) {
    // fall through to the loopback fallback
  }

  return {
    lo: [{
      address: '127.0.0.1',
      netmask: '255.0.0.0',
      family: 'IPv4',
      mac: '00:00:00:00:00:00',
      internal: true,
      cidr: '127.0.0.1/8'
    }]
  };
};

// Some proot/Android setups report an empty hostname; OpenClaw's ownership
// schema requires a non-empty host.
const realHostname = os.hostname.bind(os);
os.hostname = () => realHostname() || 'localhost';

// --- Stable process identity for OpenClaw's gateway ownership check --------
// OpenClaw records /proc/self/ns/pid, /proc/sys/kernel/random/boot_id and the
// hostname to decide whether the process holding the gateway lock is still
// valid. Under PRoot those /proc entries can be unreadable or unstable, so the
// lock is written with `processNamespace: null`. The next start then treats its
// own lock as belonging to a "different PID namespace" and refuses to run.
// Normalize the values so every process in this container agrees.
const PID_NS_PATH = /^\/proc\/(?:self|\d+)\/ns\/pid$/;
const BOOT_ID_PATH = '/proc/sys/kernel/random/boot_id';
const FALLBACK_BOOT_ID = '123e4567-e89b-42d3-a456-426614174000';
const PID_NS_INO = 4026531836n;
const PID_NS_LINK = 'pid:[4026531836]';

const realStatSync = fs.statSync;

function pidNamespaceStats(target, options) {
  const bigint = Boolean(options && typeof options === 'object' && options.bigint);
  const ino = bigint ? PID_NS_INO : Number(PID_NS_INO);
  try {
    const real = realStatSync.call(fs, target, options);
    try {
      Object.defineProperty(real, 'ino', { value: ino, configurable: true });
      return real;
    } catch (_) {
      // fall through to the minimal Stats-shaped fallback
    }
  } catch (_) {
    // fall through to the minimal Stats-shaped fallback
  }
  return {
    ino,
    isFile: () => false,
    isDirectory: () => false,
    isSymbolicLink: () => true
  };
}

fs.statSync = function (target, options) {
  if (typeof target === 'string' && PID_NS_PATH.test(target)) {
    return pidNamespaceStats(target, options);
  }
  return realStatSync.apply(fs, arguments);
};

const realReadlinkSync = fs.readlinkSync;
fs.readlinkSync = function (target) {
  if (typeof target === 'string' && PID_NS_PATH.test(target)) {
    return PID_NS_LINK;
  }
  return realReadlinkSync.apply(fs, arguments);
};

const BOOT_ID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function fallbackBootId(args) {
  const options = args[1];
  const encoding = typeof options === 'string' ? options : options && options.encoding;
  return encoding ? FALLBACK_BOOT_ID + '\n' : Buffer.from(FALLBACK_BOOT_ID + '\n');
}

function isValidBootId(value) {
  const text = Buffer.isBuffer(value) ? value.toString('utf8') : String(value);
  return BOOT_ID_RE.test(text.trim());
}

const realReadFileSync = fs.readFileSync;
fs.readFileSync = function (target) {
  if (typeof target === 'string' && target === BOOT_ID_PATH) {
    let value;
    try {
      value = realReadFileSync.apply(fs, arguments);
    } catch (_) {
      return fallbackBootId(arguments);
    }
    return isValidBootId(value) ? value : fallbackBootId(arguments);
  }
  return realReadFileSync.apply(fs, arguments);
};

// Worker threads do not inherit NODE_OPTIONS when an explicit `env` is passed.
// OpenClaw starts its state-lease heartbeat worker with `env: {}`, so make sure
// the shim is loaded there too; otherwise the worker sees a different identity
// and stops renewing the gateway owner lease.
const workerThreads = require('worker_threads');
if (typeof workerThreads.Worker === 'function') {
  const OriginalWorker = workerThreads.Worker;
  const shimPath = __filename.replace(/\\/g, '/');

  class OpenClawShimWorker extends OriginalWorker {
    constructor(filename, options = {}) {
      const env = { ...(options.env || {}) };
      const current = env.NODE_OPTIONS ?? process.env.NODE_OPTIONS ?? '';
      env.NODE_OPTIONS = current.includes(shimPath)
        ? current
        : `${current} --require "${shimPath}"`.trim();
      super(filename, { ...options, env });
    }
  }

  workerThreads.Worker = OpenClawShimWorker;
}
EOF
log_success "Runtime shim created at $HOME/openclaw-shim.cjs"

# Install OpenClaw
# npm >=11.16 / >=12 blocks lifecycle scripts unless explicitly allowed, and
# OpenClaw's postinstall (bundled plugins) is required for a working install.
log_info "Installing OpenClaw (${OPENCLAW_PACKAGE})..."
npm config set fund false
npm config set audit false
npm config set update-notifier false

NPM_VERSION="$(npm --version)"
NPM_MAJOR="${NPM_VERSION%%.*}"
NPM_REST="${NPM_VERSION#*.}"
NPM_MINOR="${NPM_REST%%.*}"

NPM_FLAGS="--no-fund --no-audit"
if [ "$NPM_MAJOR" -gt 11 ] || { [ "$NPM_MAJOR" -eq 11 ] && [ "$NPM_MINOR" -ge 16 ]; }; then
    NPM_FLAGS="$NPM_FLAGS --allow-scripts=openclaw"
fi

# shellcheck disable=SC2086
if ! npm install -g "$OPENCLAW_PACKAGE" $NPM_FLAGS; then
    log_error "OpenClaw installation failed"
    log_info "Common causes on Android/Termux:"
    log_info "  • Not enough free storage (OpenClaw unpacks to ~250MB)"
    log_info "  • Network interruption while downloading native packages"
    log_info "  • Node.js version outside OpenClaw's supported range"
    log_info "Try: npm cache clean --force && npm install -g $OPENCLAW_PACKAGE $NPM_FLAGS"
    exit 1
fi

# npm 11.16+ / npm 12 can exit successfully while skipping lifecycle scripts.
# OpenClaw's postinstall installs its bundled plugins, so a leftover marker
# means the package is not actually usable.
NPM_ROOT="$(npm root -g 2>/dev/null | awk 'NF { value = $0 } END { print value }')"
if [ -n "$NPM_ROOT" ] && { [ -e "$NPM_ROOT/openclaw/.openclaw-lifecycle-pending" ] || [ -e "$NPM_ROOT/openclaw/dist/openclaw-install-guard" ]; }; then
    log_error "OpenClaw lifecycle scripts did not complete"
    log_info "The postinstall step (bundled plugins) was skipped or failed."
    log_info "Retry with:"
    log_info "  npm cache clean --force"
    log_info "  npm install -g $OPENCLAW_PACKAGE --allow-scripts=openclaw"
    exit 1
fi

if ! command -v openclaw &>/dev/null; then
    log_error "OpenClaw installation failed (openclaw binary not found)"
    exit 1
fi

# Apply the Android networking fallback to the verification commands as well
export NODE_OPTIONS="--require $HOME/openclaw-shim.cjs"

OPENCLAW_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
if [ "$OPENCLAW_VERSION" = "unknown" ]; then
    log_warn "OpenClaw is installed but 'openclaw --version' failed"
    log_info "Run 'openclaw doctor --fix' inside Debian to diagnose"
else
    log_success "OpenClaw ${OPENCLAW_VERSION} installed"
fi

# Upstream's installer runs doctor after install/upgrades to apply migrations.
log_info "Running OpenClaw doctor (migrations)..."
openclaw doctor --fix --non-interactive || log_warn "openclaw doctor reported issues (non-fatal)"

# Write .bashrc config for the openclaw user (idempotent: replaces old block)
BASHRC="$HOME/.bashrc"
touch "$BASHRC"
sed -i '/# >>> openclaw-android >>>/,/# <<< openclaw-android <<</d' "$BASHRC" 2>/dev/null || true

cat >> "$BASHRC" << 'BASHRC'

# >>> openclaw-android >>>
# Android networking fallback - applied to ALL openclaw commands
export NODE_OPTIONS="--require $HOME/openclaw-shim.cjs"

# OpenClaw aliases
alias start-claw='openclaw gateway --bind loopback'
alias update-openclaw='openclaw update'
alias claw-status='openclaw gateway status'
alias claw-logs='openclaw logs --follow'
alias claw-doctor='openclaw doctor'
alias claw-dashboard='openclaw dashboard'
alias claw-ps='ps aux | grep -i openclaw | grep -v grep'

# Welcome message
echo ""
echo -e "\033[0;36m╔═══════════════════════════════════════╗\033[0m"
echo -e "\033[0;36m║   OpenClaw Environment Ready          ║\033[0m"
echo -e "\033[0;36m╚═══════════════════════════════════════╝\033[0m"
echo ""
echo -e "\033[0;32mUser: openclaw (non-root) | Node: $(node --version 2>/dev/null)\033[0m"
echo ""
echo -e "\033[0;32mQuick Commands:\033[0m"
echo "  openclaw onboard   - First-time setup (run this first)"
echo "  start-claw         - Start OpenClaw gateway"
echo "  openclaw tui       - Open terminal interface"
echo "  openclaw config    - Manual configuration menu"
echo "  openclaw dashboard - Open the Control UI"
echo "  update-openclaw    - Update to latest version"
echo ""
# <<< openclaw-android <<<
BASHRC

log_success "Bashrc configured"

USER_SCRIPT

log_success "User setup complete!"

# Free some space taken by downloaded package archives
apt-get clean

# -----------------------------------------------------------------------
# Final summary
# -----------------------------------------------------------------------
echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}║          Installation Complete!                   ║${NC}"
echo -e "${GREEN}║                                                   ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "1. Open a NEW Termux session (swipe left)"
echo "2. Run: proot-distro login debian --user openclaw"
echo "3. First-time setup: openclaw onboard"
echo "   (configures your provider and sets gateway.mode=local)"
echo "4. Start the gateway: start-claw"
echo "5. In a second session: proot-distro login debian --user openclaw"
echo "   then: openclaw tui   (or: openclaw dashboard)"
echo ""
echo -e "${YELLOW}⚠️  Note: Use '--user openclaw' when logging into Debian${NC}"
echo "   This ensures you run as a dedicated non-root user."
echo ""
DEBIAN_SCRIPT

    # Inject the build-time versions into the generated script
    sed \
        -e "s|__NODE_MAJOR__|${NODE_MAJOR}|g" \
        -e "s|__NVM_VERSION__|${NVM_VERSION}|g" \
        -e "s|__OPENCLAW_PACKAGE__|${OPENCLAW_PACKAGE}|g" \
        "$HOME/debian_setup.sh" > "$HOME/debian_setup.sh.tmp"
    mv "$HOME/debian_setup.sh.tmp" "$HOME/debian_setup.sh"

    chmod +x "$HOME/debian_setup.sh"
    log_success "Setup script created"
}

# Execute Debian setup
execute_debian_setup() {
    log_step "Executing Debian environment setup..."

    log_info "This will take 5-15 minutes depending on your device..."
    log_info "Please be patient and do not close Termux"

    local rootfs
    rootfs="$(debian_rootfs_dir)"

    local setup_ok=1

    if [ -n "$rootfs" ] && [ -d "$rootfs/root" ]; then
        # Preferred path: place the script inside the container so it does not
        # depend on Termux $HOME being bind-mounted into the guest.
        if cp "$HOME/debian_setup.sh" "$rootfs/root/debian_setup.sh"; then
            chmod 0755 "$rootfs/root/debian_setup.sh"
            proot-distro login debian -- /bin/bash /root/debian_setup.sh && setup_ok=0
            # proot-distro v5 may migrate a legacy installed-rootfs/ layout to
            # containers/<name>/rootfs during login, so clean up both locations.
            rm -f "$rootfs/root/debian_setup.sh"
            rootfs="$(debian_rootfs_dir)"
            [ -n "$rootfs" ] && rm -f "$rootfs/root/debian_setup.sh"
        fi
    fi

    if [ $setup_ok -ne 0 ]; then
        log_warn "Running setup via stdin instead..."
        if proot-distro login debian -- /bin/bash -s < "$HOME/debian_setup.sh"; then
            setup_ok=0
        fi
    fi

    if [ $setup_ok -eq 0 ]; then
        log_success "Debian setup completed successfully"
        # Clean up the setup script
        rm -f "$HOME/debian_setup.sh"
    else
        log_error "Debian setup failed"
        log_info "Setup script saved at: $HOME/debian_setup.sh"
        log_info "You can try running it manually:"
        log_info "  proot-distro login debian"
        log_info "  bash ~/debian_setup.sh"
        exit 1
    fi
}

# Create helper scripts
create_helper_scripts() {
    log_step "Creating helper scripts..."

    # Create launcher script - uses dedicated non-root user
    cat > "$HOME/start-openclaw.sh" << 'LAUNCHER'
#!/data/data/com.termux/files/usr/bin/bash
echo "Starting OpenClaw..."
echo ""
echo "Opening Debian environment as user 'openclaw'..."
exec proot-distro login debian --user openclaw "$@"
LAUNCHER
    chmod +x "$HOME/start-openclaw.sh"

    log_success "Helper scripts created in: $HOME"
}

# Show completion message
show_completion() {
    log_step "Installation Summary"

    echo -e "${GREEN}╔═══════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                   ║${NC}"
    echo -e "${GREEN}║      OpenClaw Installation Complete!              ║${NC}"
    echo -e "${GREEN}║                                                   ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}⚠️  Note: This installer is a community tool.${NC}"
    echo -e "   OpenClaw framework © its original creators"
    echo ""
    echo -e "${CYAN}📦 Installed Components:${NC}"
    echo "  • Debian (${DEBIAN_IMAGE}) via proot-distro"
    echo "  • Node.js ${NODE_MAJOR}.x (OpenClaw requires >= 24.16)"
    echo "  • NVM ${NVM_VERSION}"
    echo "  • OpenClaw (latest from npm)"
    echo ""
    echo -e "${CYAN}📝 Quick Start Guide:${NC}"
    echo ""
    echo -e "${YELLOW}Step 1:${NC} First-time setup (one time only)"
    echo "  $ proot-distro login debian --user openclaw"
    echo "  $ openclaw onboard"
    echo "    (configures your model provider and sets gateway.mode=local)"
    echo ""
    echo -e "${YELLOW}Step 2:${NC} Start the OpenClaw Gateway"
    echo "  $ start-claw"
    echo ""
    echo -e "${YELLOW}Step 3:${NC} Open new Termux session (swipe left)"
    echo "  $ proot-distro login debian --user openclaw"
    echo "  $ openclaw tui"
    echo ""
    echo -e "${CYAN}📚 Available Commands:${NC}"
    echo "  openclaw onboard  - First-time setup wizard"
    echo "  start-claw        - Launch gateway (loopback)"
    echo "  openclaw tui      - Terminal interface"
    echo "  openclaw config   - Manual configuration"
    echo "  openclaw dashboard - Control UI in browser"
    echo "  update-openclaw   - Update OpenClaw"
    echo "  claw-status       - Gateway status"
    echo "  claw-logs         - Follow gateway logs"
    echo "  claw-doctor       - Health checks and repairs"
    echo ""
    echo -e "${YELLOW}⚠️  Always login with:${NC} proot-distro login debian --user openclaw"
    echo "   (This runs as a dedicated non-root user)"
    echo ""
    echo -e "${CYAN}⚡ Performance Tips:${NC}"
    echo "  • Run 'termux-wake-lock' in Termux to prevent CPU throttling"
    echo "  • Set Termux battery usage to Unrestricted (Android Settings → Apps →"
    echo "    Termux → Battery) so OxygenOS/ColorOS does not kill the gateway"
    echo ""
    echo -e "${CYAN}🐛 Issues?${NC}"
    echo "  Visit: ${REPO_URL}/issues"
    echo ""
}

# Validate the requested Node.js major version against OpenClaw's engine range
validate_node_major() {
    case "$NODE_MAJOR" in
        24|26)
            ;;
        25)
            log_error "Node.js 25 is not supported by OpenClaw (>=24.16 <25 || >=26.1)"
            log_info "Use --node 24 (LTS, default) or --node 26"
            exit 1
            ;;
        22|23)
            log_error "Node.js ${NODE_MAJOR} is no longer supported by OpenClaw"
            log_info "OpenClaw now requires Node.js >=24.16.0 <25, or >=26.1.0"
            exit 1
            ;;
        *)
            log_error "Unsupported Node.js major version: ${NODE_MAJOR}"
            log_info "Supported values: 24 (LTS, default) or 26 (upstream recommended)"
            exit 1
            ;;
    esac
}

# Parse command line arguments
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
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --reinstall           Force reinstallation"
            echo "  --skip-update-check   Skip checking for updates"
            echo "  --node <24|26>        Node.js major version (default: 24 LTS)"
            echo "  --yes, -y             Assume yes for all prompts (unattended)"
            echo "  --help                Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main installation flow
main() {
    show_banner
    validate_node_major

    if [ "$SKIP_UPDATE_CHECK" = "false" ]; then
        check_for_updates
    fi

    check_termux
    check_architecture
    check_android_version
    check_storage

    install_termux_packages
    install_debian
    create_debian_setup
    execute_debian_setup
    create_helper_scripts

    show_completion
}

# Run main installation
main "$@"
