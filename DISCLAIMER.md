# Disclaimer

## About This Project

This repository (`openclaw-android`) contains **automated installation tooling and documentation** for running OpenClaw on Android devices via Termux.

The repository provides **two separate installers**, both named `install.sh`:

- [`termux/with-proot/install.sh`](termux/with-proot/install.sh) — Debian/PRoot installation.
- [`termux/no-proot/install.sh`](termux/no-proot/install.sh) — Termux-native installation without Debian or `proot-distro`.

The two installers are independent. They target different runtime layouts, do not share installer state, and do not migrate an installation from one mode to the other.

### What This Project Is

- ✅ **Installer and automation scripts** that simplify installation on Android/Termux
- ✅ **Documentation** for both installation modes
- ✅ **Android/Termux compatibility fixes** and workarounds
- ✅ **A community contribution** that makes OpenClaw easier to run on mobile devices

### What This Project Is NOT

- ❌ **Not the OpenClaw framework itself**
- ❌ **Not affiliated with or endorsed by** the official OpenClaw team
- ❌ **Not a fork or redistribution** of OpenClaw
- ❌ **Not responsible for** OpenClaw features, bugs, or functionality

> The no-PRoot installer may apply **local compatibility patches** to the installed OpenClaw npm package. It does not publish or distribute a modified OpenClaw package.

## Installer Scripts

| Installer | Mode | Runtime approach |
| --- | --- | --- |
| [`termux/with-proot/install.sh`](termux/with-proot/install.sh) | With PRoot | Creates a Debian container with `proot-distro`, installs Node.js through NVM, installs OpenClaw from npm, and applies a runtime shim for Android networking and gateway-lock compatibility. |
| [`termux/no-proot/install.sh`](termux/no-proot/install.sh) | Without PRoot | Runs OpenClaw directly in Termux using Termux packages, `glibc-runner`, the official Node.js `linux-arm64` tarball verified against `SHASUMS256.txt`, and embedded Android compatibility patches. |

### With PRoot

The With-PRoot installer is located at [`termux/with-proot/install.sh`](termux/with-proot/install.sh). It creates a Debian environment managed by `proot-distro`, creates a dedicated non-root `openclaw` user, installs Node.js through NVM, installs OpenClaw from npm, and writes the PRoot compatibility shim.

See the [With-PRoot guide](termux/with-proot/README.md) and [With-PRoot troubleshooting](termux/with-proot/TROUBLESHOOTING.md).

### Without PRoot

The no-PRoot installer is located at [`termux/no-proot/install.sh`](termux/no-proot/install.sh). It runs OpenClaw directly in Termux, without Debian or `proot-distro`. It uses Termux packages, `glibc-runner`, the official Node.js `linux-arm64` tarball verified against `SHASUMS256.txt`, and local compatibility patches for Android/Termux limitations.

Generated scripts and runtime files are kept under `~/.openclaw-android`; `~/.openclaw` is reserved for OpenClaw's own configuration and data.

See the [No-PRoot guide](termux/no-proot/README.md) and [No-PRoot troubleshooting](termux/no-proot/TROUBLESHOOTING.md).

## OpenClaw Framework

**OpenClaw** is an AI agent framework created and maintained by its own development team.

- **Official Repository**: [openclaw/openclaw](https://github.com/openclaw/openclaw)
- **Documentation**: [OpenClaw Official Docs](https://docs.openclaw.ai)
- **License**: See OpenClaw's repository for its license terms
- **Copyright**: OpenClaw © its original creators and contributors

### For OpenClaw-Specific Issues

If you have questions, feature requests, or issues about:

- OpenClaw's AI agent functionality
- OpenClaw API or features
- OpenClaw bugs or behavior
- OpenClaw documentation

**Please visit the official OpenClaw repository**, not this installer project.

## This Installer Project

- **Creator**: [@iyeoh88-svg](https://github.com/iyeoh88-svg)
- **Purpose**: Automate OpenClaw installation on Android with two separate Termux installers
- **License**: MIT (for the installer scripts and documentation only)
- **Repository**: <https://github.com/iyeoh88-svg/openclaw-android>

### What We Support

This project supports:

- ✅ Installation on Android/Termux with either PRoot or no-PRoot
- ✅ Android-specific compatibility issues
- ✅ Termux environment setup
- ✅ Installer script bugs or errors in either installer
- ✅ Documentation for both installation modes

### What We Don't Support

This project does NOT support:

- ❌ OpenClaw framework features or bugs
- ❌ OpenClaw API changes or updates
- ❌ AI model selection or configuration (beyond basic setup)
- ❌ OpenClaw usage or best practices (see official docs)

## Relationship with OpenClaw

**Independent Community Project**

This project is:

- Created independently by a community member
- Not commissioned or endorsed by the OpenClaw team
- Not reviewed or approved by OpenClaw maintainers
- A convenience tool, not part of the official OpenClaw distribution

**What the installers do**

When you run either installer from this repository, it may:

- Download OpenClaw from npm or official sources
- Install an official OpenClaw release
- Apply local compatibility patches to the installed OpenClaw files where Android/Termux requires it
- Create helper scripts, symlinks, and shell configuration
- Install supporting packages such as Node.js, glibc runtime components, and, for the With-PRoot installer only, Debian

Neither installer claims ownership of OpenClaw or replaces the official OpenClaw project.

## Attribution

### OpenClaw Framework

All credit for the OpenClaw AI agent system goes to:

- The original creators of OpenClaw
- OpenClaw maintainers and contributors
- The OpenClaw community

### Android Compatibility Work

The no-PRoot compatibility patches are based on the work in [AidanPark/openclaw-android](https://github.com/AidanPark/openclaw-android). See that repository for its license and attribution details.

### This Installer

Credit for the installation automation and documentation goes to:

- [@iyeoh88-svg](https://github.com/iyeoh88-svg) (primary author)
- Contributors to this repository
- Testers who reported bugs and tested Android devices

## Trademarks

**"OpenClaw"** and any related trademarks or service marks belong to their respective owners. This project uses the name "OpenClaw" only to describe what it installs, not to claim any association or endorsement.

## Liability

### No Warranty

These installers are provided "as is" without warranty of any kind. See the [MIT License](LICENSE) for full terms.

### Use at Your Own Risk

- Each installer modifies your Termux environment in a different way
- The With-PRoot installer creates and configures a Debian container
- The no-PRoot installer writes a runtime under `~/.openclaw-android` and creates commands under `$PREFIX/bin`
- The installers install third-party software, including OpenClaw, Node.js, and supporting runtime packages
- The no-PRoot installer may patch installed OpenClaw files for Android/Termux compatibility
- The two installers are independent; choose the one that matches your intended setup
- We are not responsible for any issues, data loss, or damage
- Always back up important data, including `~/.openclaw`, before reinstalling or resetting

### OpenClaw Functionality

- We make no guarantees about OpenClaw's functionality
- OpenClaw's behavior is governed by its own license and terms
- Issues with OpenClaw itself should be reported to OpenClaw's maintainers

## Questions?

### About the Installers

- Open an issue: <https://github.com/iyeoh88-svg/openclaw-android/issues>
- Start a discussion: <https://github.com/iyeoh88-svg/openclaw-android/discussions>

### About OpenClaw

- Visit OpenClaw's official repository
- Check OpenClaw's documentation
- Contact OpenClaw's maintainers directly

## Updates to This Disclaimer

This disclaimer may be updated from time to time. Check the repository for the most current version.

---

- **Last Updated**: October 2026
- **Repository**: <https://github.com/iyeoh88-svg/openclaw-android>
- **License**: MIT (installer scripts and documentation only) | OpenClaw has its own license
