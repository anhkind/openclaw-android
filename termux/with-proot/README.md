# OpenClaw for Termux with PRoot

Install OpenClaw on Android using a Debian environment managed by `proot-distro`. This is the compatibility-focused option: OpenClaw runs as a dedicated non-root `openclaw` user inside Debian and can use Debian packages, Homebrew, and other Linux tooling.

The installer is at [`install.sh`](install.sh). For common problems, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

## Table of Contents

- [Requirements](#requirements)
- [Installation model](#installation-model)
- [Automated installation](#automated-installation)
- [Manual installation (advanced)](#manual-installation-advanced)
- [Post-installation setup](#post-installation-setup)
- [Daily usage](#daily-usage)
- [Updating](#updating)
- [Upgrading from older versions](#upgrading-from-older-versions)
- [Troubleshooting](#troubleshooting)
- [Performance optimization](#performance-optimization)
- [Advanced usage](#advanced-usage)
- [Security notes](#security-notes)
- [Additional resources](#additional-resources)
- [Alternative: no PRoot](#alternative-no-proot)

## Requirements

### Required software

1. **Termux from F-Droid**
   - Download: <https://f-droid.org/en/packages/com.termux/>
   - Do **not** use the Google Play Store version. It is outdated and incompatible.
   - The F-Droid version is actively maintained and recommended.

2. **System requirements**
   - **Android 7+**, with Android 12+ recommended.
   - Android 11 may work but is less tested.
   - **4 GB free storage minimum**, 6 GB recommended.
   - **4 GB RAM minimum**, 6 GB+ recommended.
   - **64-bit architecture** (`arm64` or `x86_64`).
   - **Stable internet connection** for the initial setup.

### Optional but recommended

- **Termux:Widget** for home-screen shortcuts.
- **External keyboard** for easier terminal use.
- **Power adapter** because installation can take 10-15 minutes.
- **Wake lock** to prevent CPU throttling during installation.

### Before you start

1. Close other apps to free up RAM.
2. Connect to stable Wi-Fi. Mobile data works, but Wi-Fi is faster.
3. Make sure the phone is charged or connected to power.
4. Do not close Termux during installation.

## Installation model

This installer creates:

- A Debian container managed by `proot-distro`.
- A dedicated non-root `openclaw` user with passwordless sudo.
- NVM and Node.js 24 LTS, or Node.js 26 with `--node 26`.
- OpenClaw from npm.
- The Android/proot runtime shim used for networking and gateway-lock compatibility.
- Shell aliases and helper scripts.

Always log in with `proot-distro login debian --user openclaw`. Running OpenClaw as root is not supported.

## Automated installation

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh | bash
```

The installer asks before making changes unless you pass `--yes`.

Wait 5-15 minutes. The installer updates Termux packages, installs Debian, creates the `openclaw` user, installs Node.js and OpenClaw, applies the Android shim, and configures the shell.

### Review first

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
less install.sh
chmod +x install.sh
./install.sh
```

If you cloned the repository, run it from the repository root:

```bash
bash termux/with-proot/install.sh
```

### Installation options

| Option | Description |
| --- | --- |
| `--node 24` | Use Node.js 24 LTS. This is the default. |
| `--node 26` | Use Node.js 26. |
| `--reinstall` | Remove the existing Debian container before installing. |
| `--skip-update-check` | Skip the installer self-update check. |
| `--yes`, `-y` | Accept all prompts. Intended for unattended installs. |
| `--help` | Show help. |

Examples:

```bash
# Use Node.js 26
bash termux/with-proot/install.sh --node 26

# Force a clean Debian reinstall
bash termux/with-proot/install.sh --reinstall

# Unattended install
bash termux/with-proot/install.sh --yes
```

### What the installer does

1. Checks the Android version, architecture, storage, and Termux environment.
2. Updates Termux packages.
3. Installs and configures `proot-distro`.
4. Installs Debian (`debian:trixie` by default).
5. Creates the dedicated `openclaw` user with passwordless sudo.
6. Installs NVM and Node.js.
7. Creates the Android/proot compatibility shim.
8. Installs OpenClaw globally from npm.
9. Runs `openclaw doctor --fix` to apply migrations.
10. Configures shell aliases and helper scripts.

## Manual installation (advanced)

> The automated installer is the supported path. It includes the full compatibility shim and current OpenClaw patches. Manual installation is useful for debugging an installer failure, but it may not include every patch.

### Step 1: Prepare Termux

```bash
pkg update
pkg upgrade -y
pkg install -y proot-distro curl
```

### Step 2: Install Debian

```bash
# proot-distro v5
proot-distro install --name debian debian:trixie

# Older proot-distro v4
# proot-distro install debian

# Enter Debian as root for initial setup
proot-distro login debian
```

### Step 3: Create the dedicated user

Inside Debian as root:

```bash
apt update
apt install -y sudo
useradd -m -s /bin/bash openclaw
echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-openclaw
chmod 0440 /etc/sudoers.d/90-openclaw
exit
```

### Step 4: Log in as the OpenClaw user

Back in Termux:

```bash
proot-distro login debian --user openclaw
```

### Step 5: Install Debian build dependencies

Inside Debian as `openclaw`:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl git build-essential python3 cmake ca-certificates \
    sudo passwd procps xz-utils libatomic1
```

### Step 6: Install Node.js with NVM

```bash
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.8/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"

# Node.js 24 LTS
nvm install 24
nvm use 24
nvm alias default 24

# Or use Node.js 26
# nvm install 26
# nvm use 26
# nvm alias default 26

node --version
npm --version
```

### Step 7: Install OpenClaw

```bash
# npm 11.16+ / 12 requires the lifecycle allow-list
npm install -g openclaw@latest --allow-scripts=openclaw

# npm 11.15 and earlier
# npm install -g openclaw@latest

openclaw --version
```

### Step 8: Install the compatibility shim and shell configuration

The current installer writes the full `$HOME/openclaw-shim.cjs` and `.bashrc` block. For a manual setup, the safest option is to rerun the automated installer after Debian is ready so the current shim and patches are applied:

```bash
# Back in Termux
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh
```

The generated shim handles Android networking fallbacks and the gateway ownership lock under PRoot. Older simplified versions of the shim are not sufficient for current OpenClaw releases.

## Post-installation setup

### Initial configuration

Log in as the OpenClaw user:

```bash
proot-distro login debian --user openclaw
```

**Option 1: Automated onboarding (recommended)**

```bash
openclaw onboard
```

Follow the prompts to choose a provider, enter an API key, configure preferences, and optionally set up channels.

**Option 2: Interactive configuration**

```bash
openclaw config
```

Use this if onboarding skips steps. It lets you configure the model, skills, channels, and workspace.

**Option 3: Command-line configuration**

```bash
# Set an Anthropic API key
openclaw config set providers.anthropic.apiKey "sk-ant-your-key-here"

# Set the default provider and model
openclaw config set defaultProvider anthropic
openclaw config set defaultModel "claude-sonnet-4-20250514"

# View the current configuration
openclaw config list
```

### Test the installation

Start the gateway in one Termux session:

```bash
proot-distro login debian --user openclaw
start-claw
```

In a second Termux session:

```bash
proot-distro login debian --user openclaw
openclaw tui
```

If both work, the installation is successful.

## Daily usage

### Starting OpenClaw

OpenClaw normally uses two sessions.

**Session 1: Gateway**

```bash
proot-distro login debian --user openclaw
start-claw
```

This starts the OpenClaw gateway that processes commands and talks to the configured model provider.

**Session 2: TUI**

```bash
# Swipe left in Termux to open a new session
proot-distro login debian --user openclaw
openclaw tui
```

The dashboard is available with `openclaw dashboard`.

### Quick reference

Inside Debian as the `openclaw` user:

| Command | Purpose |
| --- | --- |
| `start-claw` | Start the OpenClaw gateway on loopback. |
| `openclaw tui` | Open the terminal interface. |
| `openclaw onboard` | First-time setup wizard. |
| `openclaw config` | Manual configuration menu. |
| `openclaw dashboard` | Open the browser control UI. |
| `openclaw doctor` | Run health checks and repairs. |
| `update-openclaw` | Update OpenClaw. |
| `claw-status` | Show gateway status. |
| `claw-logs` | Follow gateway logs. |
| `claw-doctor` | Run the doctor command. |
| `exit` | Leave Debian and return to Termux. |

In Termux:

| Command | Purpose |
| --- | --- |
| `proot-distro login debian --user openclaw` | Enter Debian as the OpenClaw user. |
| `termux-wake-lock` | Prevent Android from throttling Termux. |
| `termux-wake-unlock` | Release the wake lock. |
| `pkg update` | Update Termux packages. |

### Stopping OpenClaw

1. Exit the TUI with `Ctrl+C` or `exit`.
2. Press `Ctrl+C` in the gateway session.
3. Type `exit` to leave Debian.

## Updating

### Update OpenClaw

Inside Debian:

```bash
proot-distro login debian --user openclaw
update-openclaw
```

### Update the installer

The installer checks for updates automatically. To update it manually:

```bash
# In Termux, not inside Debian
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh
```

### Update Debian packages

```bash
# Inside Debian
sudo apt update && sudo apt upgrade -y
```

### Update Node.js

```bash
# Inside Debian
nvm install 24 --latest-npm
nvm use 24
nvm alias default 24
```

## Upgrading from older versions

This guide targets the non-root architecture introduced in v2026.2.14.

### Fresh install (recommended)

Back up anything you need from the old container, then reinstall:

```bash
# In Termux
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh --reinstall
```

Always log in afterward with:

```bash
proot-distro login debian --user openclaw
```

### Manual upgrade while preserving data

If you need to keep the existing OpenClaw configuration:

1. Back up `~/.openclaw` from the old environment.
2. Create the `openclaw` user and sudo drop-in inside Debian.
3. Copy the old configuration to `/home/openclaw/.openclaw`.
4. Fix ownership:

```bash
chown -R openclaw:openclaw /home/openclaw/.openclaw
```

5. Log in as `openclaw` and reinstall NVM, Node.js, and OpenClaw.
6. Rerun this installer so the current compatibility shim and shell configuration are applied.

Do not use `--reinstall` if you are trying to preserve the existing Debian container and its data.

## Troubleshooting

### Installation issues

**Installation hangs during package upgrade**

Use the latest installer. Older versions had interactive package prompts.

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh
```

**`nvm: command not found`**

Log in as the `openclaw` user and reload the shell:

```bash
proot-distro login debian --user openclaw
source ~/.bashrc
```

**Error 13 during `openclaw onboard` or `openclaw config`**

The installer includes the Android networking shim. Verify that `.bashrc` contains:

```bash
export NODE_OPTIONS="--require $HOME/openclaw-shim.cjs"
```

Then reload:

```bash
source ~/.bashrc
```

If the shim is missing, rerun the installer.

**"Don't run this as root!"**

Log in with the dedicated user:

```bash
proot-distro login debian --user openclaw
```

**Permission denied errors**

Grant Termux storage access:

```bash
termux-setup-storage
```

Accept the Android permission prompt.

### Runtime issues

**Gateway will not start**

```bash
# Inside Debian
openclaw gateway status
claw-logs
```

If another gateway process is already running, stop it before starting a new one. Check the logs for the reason the process exited.

**Cannot connect to the TUI**

1. Make sure the gateway is running in the first session.
2. Make sure both sessions are logged in as `openclaw`.
3. Restart the gateway and try again.

**Slow performance**

```bash
# In Termux
termux-wake-lock

# Check memory
free -h
```

Close other Android apps to free memory.

**`Cannot find module` errors**

```bash
# Inside Debian
npm cache clean --force
npm install -g openclaw@latest --allow-scripts=openclaw
```

**Out of storage**

```bash
# Inside Debian
npm cache clean --force
sudo apt clean
sudo apt autoremove -y

# In Termux
pkg clean
```

**Android kills the gateway (signal 9)**

- Set Termux battery usage to **Unrestricted**.
- Disable the Phantom Process Killer. See the [reference guide](https://github.com/AidanPark/openclaw-android/blob/main/docs/disable-phantom-process-killer.md).
- Keep `termux-wake-lock` active while the gateway is running.

### Advanced troubleshooting

**Reset OpenClaw configuration**

> This removes OpenClaw's local configuration and sessions. Back it up first if you need it.

```bash
# Inside Debian
rm -rf ~/.openclaw
openclaw onboard
```

**Complete reinstall**

> This removes the Debian container and all data inside it.

```bash
# In Termux
proot-distro remove debian
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh --reinstall
```

**Check logs**

```bash
# Inside Debian
openclaw logs --follow

# Raw log files, if present
ls -la /tmp/openclaw/
```

### Getting help

1. Read [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
2. Search [existing issues](https://github.com/iyeoh88-svg/openclaw-android/issues).
3. Open a [new issue](https://github.com/iyeoh88-svg/openclaw-android/issues/new) with:
   - Android version
   - Termux version and source (F-Droid or Play Store)
   - Installer version
   - Error messages
   - Steps to reproduce

## Performance optimization

### Battery and CPU

- Set Termux battery usage to **Unrestricted** in Android settings.
- Run `termux-wake-lock` while the gateway is running.
- Release it with `termux-wake-unlock` when finished.

### Memory

If OpenClaw needs more Node.js heap space, preserve the shim and add the memory flag:

```bash
# Inside Debian, add to ~/.bashrc
export NODE_OPTIONS="--max-old-space-size=2048 --require $HOME/openclaw-shim.cjs"
```

Do not replace `NODE_OPTIONS` with only `--max-old-space-size`; that would remove the required compatibility shim.

### Storage

```bash
# Inside Debian
npm cache clean --force
sudo apt clean
sudo apt autoremove -y

# In Termux
pkg clean
```

### Check resource usage

```bash
# Inside Debian
free -h
df -h
top
```

## Advanced usage

### Homebrew

Homebrew works because OpenClaw runs as a non-root user:

```bash
# Inside Debian as openclaw
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Follow Homebrew's PATH instructions, then reload
source ~/.bashrc

brew install cowsay
cowsay "Hello from OpenClaw on Android!"
```

### Custom aliases

Add your own shortcuts to `~/.bashrc`:

```bash
# Quick status check
alias claw-check='openclaw --version && claw-status'

# Restart helper
alias claw-restart='killall openclaw; start-claw'
```

### Environment variables

Customize OpenClaw behavior in `~/.bashrc`:

```bash
export OPENCLAW_LOG_LEVEL=debug
```

Keep the shim in `NODE_OPTIONS` if you add any Node.js options.

## Security notes

- Never commit API keys to git.
- Do not share your `~/.openclaw` configuration directory.
- Rotate keys if they are exposed.
- The `openclaw` user has passwordless sudo inside Debian. Only run trusted commands with `sudo`.
- The PRoot environment is isolated from the main Android system, but it is not a security boundary against malicious code you choose to run.

## Additional resources

- [Main README](../../README.md) - Project overview and both installation modes
- [No-PRoot guide](../no-proot/README.md) - Termux-native installation without Debian
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues and solutions
- [QUICKREF.md](../../QUICKREF.md) - Quick reference card
- [CHANGELOG.md](../../CHANGELOG.md) - Version history
- [OpenClaw documentation](https://docs.openclaw.ai)
- [Termux wiki](https://wiki.termux.com)
- [GitHub Discussions](https://github.com/iyeoh88-svg/openclaw-android/discussions)

## Alternative: no PRoot

If you do not need Debian packages or Homebrew, the [Termux-native installer](../no-proot/README.md) runs OpenClaw directly in Termux without `proot-distro`. It uses less storage and avoids the Debian layer, but it relies on prebuilt Android compatibility patches.
