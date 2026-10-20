# Changelog

All notable changes to the OpenClaw Android Installer will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- 🧩 **Termux-native installer without PRoot** (`termux/no-proot/install.sh`)
  - Runs OpenClaw directly in Termux with `glibc-runner` and the official Node.js `linux-arm64` tarball
  - Verifies the Node.js download against `SHASUMS256.txt`
  - Embeds Android compatibility and gateway-lock patches, verified against OpenClaw `2026.10.5`
  - Supports `--node 24`, `--node 26`, `--openclaw <version>`, `--latest`, `--update`, `--repair`, `--reinstall`, `--yes`, and `--skip-update-check`
  - Generates `update-claw`, `start-claw`, and `systemctl` helpers under `~/.openclaw-android`
  - Keeps installer and runtime files in `~/.openclaw-android`; OpenClaw data remains in `~/.openclaw`
- 🌐 **Optional LAN binding for the gateway** (`termux/no-proot/install.sh`)
  - `start-claw --lan` binds `0.0.0.0`, prints a warning, and shows the best-effort phone LAN URL with the correct port
  - `start-claw` and `start-openclaw.sh` honor `OPENCLAW_GATEWAY_BIND` (default: `loopback`); an explicit `--bind <address>` wins over `--lan`
  - The default stays loopback, and the gateway token still protects access when it is exposed
- 🔑 **`claw-token` shell function** (`termux/no-proot/install.sh`)
  - Prints the gateway token from `~/.bashrc`, and configures one with `openclaw doctor --generate-gateway-token` when none exists yet (then tells you to restart the gateway)
  - Explains `password`, `trusted-proxy`, and `none` auth modes instead of pretending a token exists
  - Token-based by design: it refuses piped or redirected output, matching OpenClaw's own reveal, so it can never silently land in a log
  - `--repair` now refreshes the generated `.bashrc` block, so existing installs pick up new aliases and functions

### Changed
- 📦 Moved the Debian/PRoot installer from `install.sh` to `termux/with-proot/install.sh`
- 📚 Split documentation by installation mode:
  - `termux/with-proot/README.md` and `termux/with-proot/TROUBLESHOOTING.md`
  - `termux/no-proot/README.md` and `termux/no-proot/TROUBLESHOOTING.md`
- 🏠 Simplified the root `README.md` into a landing page linking to each mode's guide
- ⚠️ Updated `DISCLAIMER.md` to cover both independent installers
- 🔗 Updated contribution and bug-report documentation for the two installation paths
- ℹ️ The PRoot and no-PRoot modes are independent; no automatic migration is provided
- 🔢 Installer versions synchronized at `2026.10.20` across `VERSION`, `termux/no-proot/install.sh`, and `termux/with-proot/install.sh`
  - One `VERSION` file drives the self-update prompt of both installers, so the three values have to move together
- 🎯 **OpenClaw pin moved to `2026.10.5`** (`termux/no-proot/install.sh`)
  - Carries the model-provider fixes that motivated the move
  - The embedded patches were re-verified against `openclaw@2026.10.5` with `@openclaw/fs-safe@0.25.0`: all 21 targets apply with `problems=0`, a second run reports everything as already patched, and every patched bundle still parses
  - The Node.js floor is unchanged (`>=24.16.0 <25 || >=26.1.0`), so the default Node 24 LTS install still satisfies it
  - Existing installs move forward with `update-claw`; OpenClaw migrates the state database forward, and `doctor` now has time to finish
- 🔢 Installer versions bumped to `2026.10.21` (`VERSION` and both `SCRIPT_VERSION`s) so running installs are offered the update
- 🪶 **No Termux toolchain by default** (`termux/no-proot/install.sh`)
  - Installs only `curl`, `tar`, `xz-utils`, `coreutils`, `pacman` (+ optional `resolv-conf`); `git`, `python`, `make`, `cmake`, `clang`, and `binutils` are gone
  - Nothing is compiled (npm runs with `--ignore-scripts`), so that toolchain was several hundred MB of unused packages
- 🧾 **pacman install upgraded from `-Sy` to `-Syu --needed`** (`termux/no-proot/install.sh`) to avoid the classic partial-upgrade breakage
- 🔗 `termux/with-proot/install.sh` repository links now point at `anhkind/openclaw-android` (the repo that hosts the scripts); the previous upstream stays listed as a reference in the banner
- 🧹 Dropped environment variables OpenClaw does not read (`OA_GLIBC`, `CONTAINER`, `CLAWDHUB_WORKDIR`, `CPATH`) from the installer, `.bashrc` block, launcher, and gateway helper

### Removed
- 🗑️ Removed the root `install.sh`, `GUIDE.md`, and `TROUBLESHOOTING.md` after moving their content under `termux/with-proot/`

### Fixed
- 🩹 **Re-sourcing `.bashrc` no longer breaks on the old `start-claw` alias** (`termux/no-proot/install.sh`)
  - An alias still active in the current shell was expanded while parsing `start-claw() {`, producing `syntax error near unexpected token '('`; the generated block now clears it first
- 🔁 **Installer self-update can no longer loop** (`termux/no-proot/install.sh`, `termux/with-proot/install.sh`)
  - A downloaded installer is re-executed only when its `SCRIPT_VERSION` is actually newer, and at most once per run
  - Previously, a `VERSION` file ahead of the published script re-downloaded and re-executed forever, a loop `update-claw` (`--yes`) could not interrupt
- 🌐 **glibc now has a resolver configuration** (`termux/no-proot/install.sh`)
  - `$PREFIX/glibc/etc/resolv.conf` is created from `$PREFIX/etc/resolv.conf`, falls back to Android's `net.dns*` properties and then public resolvers, and is refreshed by `--repair`
  - The compatibility shim reads the glibc copy first and ignores unusable entries such as zone-scoped IPv6 addresses
- 🧰 **The `systemctl` stub no longer shadows the global command** (`termux/no-proot/install.sh`)
  - Kept in `~/.openclaw-android/bin` only; the `$PREFIX/bin/systemctl` symlink older versions created is removed on install and repair
  - Only `restart` is emulated; other invocations answer like systemd does without systemd, so OpenClaw takes its normal non-systemd path instead of believing a service manager exists
- 🏠 `--repair` now also regenerates the Node.js wrappers (`termux/no-proot/install.sh`), so wrapper changes from a newer installer apply
- 📝 A damaged `~/.bashrc` block no longer truncates the file (`termux/no-proot/install.sh`): the old block is removed only when both markers are present
- ✅ Failed verification no longer hides the completion summary (`termux/no-proot/install.sh`): the banner reports the failure and the script still exits non-zero
- 🧬 **`exec()`/`execSync()` now get the same Android wrapping as `spawn`** (`termux/no-proot/install.sh`)
  - Node builds the shell command for `exec`/`execSync` in an internal spawn that cannot be intercepted, so a native glibc binary run through a shell command string previously failed with `ENOENT`
  - Simple commands are now resolved and re-routed through the file-based APIs, so the glibc-loader and shebang fixes apply; pipelines and redirects still use the shell, and an explicitly requested shell is left alone
- 📛 Path patching survives awkward file names (`termux/no-proot/install.sh`): the `for f in $files` word-splitting loops are now line-by-line reads
- 🛡️ An existing Debian/PRoot installation is detected and called out (`termux/no-proot/install.sh`) instead of being silently left to share `~/.openclaw`
- ⌨️ Prompts no longer print a `/dev/tty` redirection error when there is no controlling terminal (both installers); the documented default is used instead
- 🚪 **`start-claw` is no longer blocked by the installer's own config write** (`termux/no-proot/install.sh`)
  - Writing `update.checkOnStart` created a config file without `gateway.mode`, which OpenClaw treats as clobbered configuration and refuses to start from
  - `gateway.mode=local` is now set (only when unset, so a client/remote setup keeps its value) before any other key
- ⏱️ **`openclaw doctor --fix` gets enough time to migrate the state database** (`termux/no-proot/install.sh`)
  - The 300-second cap could kill the first migration mid-way and leave a state database the gateway then refuses to open; it is now 900 seconds
  - A failure shows the tail of doctor's output instead of a single "non-fatal" line that is easy to miss before a gateway that will not start

### Security
- 🔐 **pacman package signatures are now actually verified** (`termux/no-proot/install.sh`)
  - Termux ships `SigLevel = DatabaseRequired PackageOptional`, so the previous rewrite reproduced the default and left packages unverified
  - The glibc-runner install now runs with `SigLevel = PackageRequired DatabaseRequired` and warns when the configuration has no `SigLevel` line at all

## [2026.10.19] - 2026-10-19

### Changed
- 🚀 **Updated for OpenClaw 2026.10.5** (`openclaw@latest`)
  - OpenClaw now requires **Node.js >= 24.16.0 < 25 || >= 26.1.0** — Node 22 is no longer supported
  - Installs **Node.js 24 LTS** by default (the line used by OpenClaw's Linux installer); use `--node 26` for the upstream-recommended Node 26
  - Uses the npm lifecycle allow-list: `npm install -g openclaw@latest --allow-scripts=openclaw` on npm 11.16+/12
  - Verifies OpenClaw's postinstall marker so a silently skipped lifecycle script is not reported as success
  - Runs `openclaw doctor --fix --non-interactive` after installation, matching the upstream installer
- ⬆️ **NVM v0.40.8** (was v0.40.1)
- ⬆️ **Debian 13 "trixie"** via proot-distro OCI images (`debian:trixie`)
- ⬆️ **proot-distro v5.10.0** compatibility
  - Container detection via `proot-distro list -q` (the old `--installed-only` flag is gone)
  - Installs with `install --name debian <image>` and falls back to the v4 CLI automatically
  - Supports both `containers/<name>/rootfs` and legacy `installed-rootfs/<name>` layouts

### Added
- 🆕 64-bit architecture check (Node.js 24/26 have no 32-bit ARM builds)
- 🆕 `--yes` / `-y` unattended mode and `--node <24|26>` option
- 🆕 `claw-doctor` and `claw-dashboard` aliases; `claw-logs` now uses `openclaw logs --follow`
- 🆕 `libatomic1` base package for the official Node.js ARM64 binaries
- 🆕 Onboarding-first instructions (`openclaw onboard` writes `gateway.mode=local`)

### Fixed
- 🐛 Installer self-update no longer offers a downgrade when the local version is newer
- 🐛 Setup no longer aborts when `.bashrc` has no NVM lines
- 🐛 `.bashrc` block is replaced idempotently instead of appended on every run
- 🐛 Sudo access uses `/etc/sudoers.d/90-openclaw` with `0440` permissions
- 🐛 Setup script runs from inside the container rootfs (no reliance on Termux `$HOME` bind mounts)
- 🐛 Android networking shim now only falls back to loopback when interfaces are unreadable
- 🐛 Storage requirement raised to 4GB (OpenClaw unpacks to ~250MB, plus Node.js and Debian)

### Why
OpenClaw's 2026.10.x line dropped Node 22 and moved to npm's lifecycle-script
allow-list. The previous installer pinned Node 22 and used the proot-distro v4
CLI, so it could no longer produce a working OpenClaw installation.

## [2026.2.15] - 2026-02-13

### Fixed
- 🐛 **CRITICAL**: Fixed installer stopping when Debian already installed
  - Root cause: Installer would error out when detecting existing Debian instead of handling it gracefully
  - Now offers 3 clear options: upgrade existing, fresh install, or skip
  - Properly upgrades old installations (pre-v2026.2.14) to new non-root architecture
  - Checks if openclaw user exists before creating

### Changed
- Improved prompts when existing Debian detected
- Better handling of existing openclaw user
- Clearer options for users upgrading from older versions

### Context
When Debian was already installed (from previous runs or older versions), the installer would stop with an error. Now it gracefully handles existing installations and can upgrade them to the new v2026.2.14+ non-root architecture.

## [2026.2.14] - 2026-02-13

### Added
- 🆕 Dedicated non-root user `openclaw` is now created inside Debian
- 🆕 NVM, Node.js, OpenClaw, and all configs are installed under the `openclaw` user
- 🆕 Passwordless sudo granted to `openclaw` user for package installs (e.g. Homebrew)
- 🆕 Networking shim stored at `/home/openclaw/openclaw-shim.cjs`

### Changed
- **BREAKING**: Login command updated to `proot-distro login debian --user openclaw`
- All documentation updated to use new login command
- Completion message updated with correct login instructions

### Fixed
- 🐛 Homebrew and other tools that refuse to run as root now work correctly
- 🐛 `useradd` and `sudo` installed as part of base packages

### Context
Previously everything ran as `root` inside Debian. Tools like Homebrew explicitly block root usage. Now OpenClaw runs in a proper non-root user environment while still having sudo access for any package installations needed.

## [2026.2.13] - 2026-02-13

### Fixed
- 🐛 **CRITICAL**: Fixed Error 13 appearing during `openclaw onboard`, `openclaw config`, `openclaw tui` and all other openclaw commands
  - Root cause: The Android networking shim was only applied to `start-claw` alias
  - Fix: Moved `NODE_OPTIONS` to a global export in `.bashrc` so ALL openclaw commands automatically use the shim
  - `start-claw` alias simplified (no longer needs NODE_OPTIONS inline)

### Changed
- `NODE_OPTIONS="--require /root/openclaw-shim.cjs"` is now set globally in `.bashrc`
- All openclaw commands (`onboard`, `config`, `tui`, `gateway`, etc.) now work without Error 13
- Added `openclaw config` to the welcome message quick commands

### Context
Previously the networking shim was only injected when running `start-claw`. Any other openclaw command run directly would trigger the Android Error 13. Now the shim applies globally to the entire Debian session.

## [2026.2.11] - 2026-02-13

### Fixed
- 🐛 **CRITICAL**: Fixed "nvm: command not found" error during Node.js installation
  - Added multiple fallback methods to load NVM
  - Improved NVM sourcing with better error detection
  - Added verification steps before attempting to use nvm
  - Now tries: direct source, bashrc source, and manual load

### Changed
- Enhanced NVM loading with 3-tier fallback system
- Better error messages when NVM fails to load
- Added explicit verification that nvm command is available

### Context
After NVM installation, the script needs to explicitly source it before use. Some environments don't automatically load it, causing "command not found" errors.

## [2026.2.10] - 2026-02-13

### Fixed
- 🐛 **CRITICAL**: Fixed `pkg upgrade` hanging on interactive prompts (dpkg config file conflicts)
  - Now uses `apt-get upgrade` with `--force-confold` to avoid prompts
  - Sets `DEBIAN_FRONTEND=noninteractive` to prevent any interactive dialogs
- 🐛 Fixed `df: Unknown option 'm'` error on some Termux versions
  - Changed from `df -m` to `df -k` (more universally supported)
  - Added proper validation and error handling for storage check
- 🐛 Fixed version comparison validation
  - Added regex validation to ensure version format is correct (e.g., 2026.2.10)
  - Only uses first line from VERSION file to prevent concatenation
  - Better handling of malformed version responses
- 🐛 Fixed "integer expression expected" error when storage check fails
  - Added proper null/empty checks before numeric comparisons
  - Fallback to user confirmation if storage can't be determined

### Changed
- Improved error messages for storage check failures
- Added user prompt to continue if storage check fails (rather than hard exit)
- Better validation of curl responses in version checking

### Context
These fixes address issues reported by users running F-Droid Termux on Android 16. The interactive dpkg prompt was the most critical issue preventing unattended installation.

## [2026.2.9] - 2026-02-13

### Added
- 📄 **DISCLAIMER.md** - Comprehensive disclaimer clarifying project scope
- ⚠️ Attribution notices in README and installer banner
- 🙏 Proper credit to OpenClaw's original creators throughout documentation
- 📝 Updated marketing materials with attribution guidelines

### Changed
- Clarified in all documentation that this is an installer tool, not OpenClaw itself
- Updated CONTRIBUTING.md to specify contribution scope
- Added disclaimer notices to completion messages
- Updated README badges to show correct version (2026.2.9)

### Context
This update ensures proper attribution to OpenClaw's creators and clarifies that this project is a community-created installation tool, not the OpenClaw framework itself.

## [2026.2.8] - 2026-02-13

### Fixed
- 🐛 Fixed version comparison showing incorrect concatenated versions
- 🐛 Fixed "No command y found" error when responding to prompts
- 🐛 Fixed auto-update download using /tmp (permission denied)
- 🔧 All user input prompts now use `/dev/tty` for proper input handling in Termux

### Changed
- Improved version checking with whitespace trimming
- Auto-update now downloads to `$HOME` instead of `/tmp`
- Better error handling for empty version responses

## [2026.2.7] - 2026-02-13

### Fixed
- 🐛 Fixed "Permission denied" error when creating Debian setup script
- Changed temporary script location from `/tmp` to `$HOME` to avoid Termux permission issues
- Added automatic cleanup of setup script after successful installation

### Changed
- Improved error messages for failed Debian setup with manual recovery instructions

## [2026.2.6] - 2026-02-12

### Added
- 🎉 Initial public release
- ✅ Fully automated installation script with progress indicators
- 🔄 Auto-update system that checks for new installer versions
- 🛠️ Comprehensive error handling and recovery
- 📝 Detailed documentation (README, guides, troubleshooting)
- 🎨 Colorful CLI output with status indicators
- ⚙️ Automatic creation of convenience aliases
- 🔧 Android Error 13 networking fix (shim system)
- 📊 Storage and system compatibility checks
- 🎯 Command-line flags (--reinstall, --skip-update-check)

### Features
- Automatic Termux package updates
- PRoot Debian installation and configuration
- NVM and Node.js 22 installation
- OpenClaw global package installation
- Helper scripts for easy launching
- Complete environment setup automation
- Version compatibility checks
- Progress tracking and ETA estimates

### Documentation
- README.md with quick start guide
- termux/with-proot/README.md with detailed instructions
- termux/with-proot/TROUBLESHOOTING.md with solutions to common issues
- Inline script documentation
- Usage examples and best practices

## Future Plans

### Planned
- 🎥 Video tutorial
- 🔌 Termux:Widget integration for home screen shortcuts
- 📱 Android 11 compatibility testing
- 🌐 Multi-language support
- 🎨 Custom themes for TUI
- 📊 Performance benchmarking tools
- 🔔 Desktop notifications integration
- 💾 Backup and restore functionality
- 🔄 One-command update for OpenClaw and all dependencies
- 🐳 Alternative installation via Docker (if possible on Android)

### Under Consideration
- GUI installer (Termux:API integration)
- Automatic log rotation
- Performance profiling mode
- Cloud sync for configurations
- Plugin system for extensions

## Version History

### Pre-release Development

**2026-02-10**: Alpha testing phase
- Internal testing with select users
- Bug fixes and optimization
- Documentation refinement

**2026-02-05**: Initial development
- Proof of concept
- Basic installation workflow
- Error 13 fix implementation

---

## Release Notes

### v2026.2.6 - "First Light" 🚀

This is the first public release of the OpenClaw Android installer. After extensive testing, we're excited to bring OpenClaw to Android devices via Termux.

**Highlights:**
- One-command installation
- Automatic problem detection and fixing
- Comprehensive documentation
- Active community support

**Known Issues:**
- Performance may vary on devices with less than 4GB RAM
- Android 11 support is experimental
- Some Android skins may require additional battery optimization tweaks

**Upgrading:**
If you were using a pre-release version, please run:
```bash
./install.sh --reinstall
```

**Contributors:**
Thank you to our alpha testers and the Termux community for making this possible!

---

## Deprecation Notices

None currently.

## Security Updates

None currently. We will document any security-related updates here.

---

**How to Update:**

The installer automatically checks for updates. To manually update, use the command for your installation mode:
```bash
# With PRoot (Debian)
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh | bash

# Without PRoot (Termux-native)
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh | bash
```

**Reporting Issues:**

Found a bug? Please report it:
- GitHub Issues: https://github.com/iyeoh88-svg/openclaw-android/issues
- Include: installation mode (with PRoot or no-PRoot), Android version, Termux version, error message, and steps to reproduce

---

[2026.2.6]: https://github.com/iyeoh88-svg/openclaw-android/releases/tag/v2026.2.6
