# 🦞 OpenClaw for Android (Termux)
<img width="540" height="405" alt="image" src="https://github.com/user-attachments/assets/e9a9d875-74d1-410d-a9bf-3e1be55f4cb4" />

[![Version](https://img.shields.io/badge/version-2026.10.21-blue.svg)](https://github.com/anhkind/openclaw-android)
[![Android](https://img.shields.io/badge/Android-12%2B-green.svg)](https://www.android.com/)
[![Termux](https://img.shields.io/badge/Termux-Required-orange.svg)](https://termux.dev/)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)
[![Stars](https://img.shields.io/github/stars/anhkind/openclaw-android.svg)](https://github.com/anhkind/openclaw-android/stargazers)
[![Issues](https://img.shields.io/github/issues/anhkind/openclaw-android.svg)](https://github.com/anhkind/openclaw-android/issues)

> **Automated installers for running the OpenClaw AI agent system on Android devices via Termux.**

This repository provides **two independent installation options**. The Termux-native option is recommended for most users. Choose the one that fits how you want to run OpenClaw, then follow its guide for setup, usage, updating, and troubleshooting.

---

## 🚀 Choose Your Installation

| Option | Best for | Runtime |
| --- | --- | --- |
| **Without PRoot (Termux-native)** ✅ **Recommended** | Most users. A lighter install with no Debian container or `proot-distro`. | OpenClaw runs directly in Termux using `glibc-runner`, the official Node.js `linux-arm64` build, and embedded Android patches. |
| **With PRoot (Debian)** | Debian packages, Homebrew, and the most established compatibility path. | Debian via `proot-distro`, Node.js via NVM, and a dedicated non-root `openclaw` user. |

Both installers are separate. They do not share runtime files or migrate an installation from one mode to the other.

## 📱 Termux Setup

Before running an installer, get Termux onto the device and set up SSH so you can work from a real keyboard on your computer.

### 1. Install Termux

Install Termux from one of these sources — **do not use Google Play**, that build is outdated and unsupported:

- **[F-Droid](https://f-droid.org/en/packages/com.termux/)** (recommended) — install the F-Droid client, then install Termux from it.
- **[Termux GitHub releases](https://github.com/termux/termux-app/releases)** — download the `universal` APK (or the `arm64-v8a` one for most modern phones) and allow installs from your browser when prompted.

Open Termux once after installing so it can finish its first-run setup.

### 2. Install OpenSSH in Termux

In the Termux app:

```bash
pkg update && pkg upgrade -y
pkg install openssh -y
```

Set a password for the SSH login (this is your Termux user password, not your Android lock screen):

```bash
passwd
```

### 3. Start the SSH server

Termux runs its SSH daemon on port **8022** (not 22), because ports below 1024 need root.

```bash
sshd
```

Check that it is listening, and note the username you will log in with:

```bash
whoami
ip addr show wlan0 | grep "inet "
```

Keep Termux in the foreground, or acquire a wake lock from the notification, so Android does not suspend `sshd`. To start it again later, just run `sshd` once more.

### 4. Connect from your computer

On the same Wi-Fi network, from your computer's terminal:

```bash
ssh -p 8022 <username>@<device-ip>
```

For example, `ssh -p 8022 u0_a123@192.168.1.42`. Accept the host key on first connect and enter the password you set with `passwd`.

Optional — copy your public key so you can log in without a password:

```bash
ssh-copy-id -p 8022 <username>@<device-ip>
```

Once you are in, you can run the installer commands below directly from your computer's terminal. The post-install start commands are the exception — see the note in [Quick Start](#-quick-start).

> 💡 **Tip:** If the connection is refused, confirm `sshd` is running in Termux, that both devices are on the same network, and that your router or VPN is not blocking client isolation.

## ⚡ Quick Start

### Option 1: Without PRoot (Termux-native) — Recommended

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh | bash
```

**Next step:** [Read the full No-PRoot setup guide →](termux/no-proot/README.md)

**Problems?** [No-PRoot troubleshooting →](termux/no-proot/TROUBLESHOOTING.md)

### Option 2: With PRoot (Debian)

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh | bash
```

**Next step:** [Read the full With-PRoot setup guide →](termux/with-proot/README.md)

**Problems?** [With-PRoot troubleshooting →](termux/with-proot/TROUBLESHOOTING.md)

**Wait 5-15 minutes** for the automated installation to complete.

> ⚠️ **Use Termux from [F-Droid](https://f-droid.org/en/packages/com.termux/), not Google Play.** The Play Store build is outdated and not supported.

> ⚠️ **Start OpenClaw in the phone's Termux app, not over SSH.** Once the installer finishes, run `bash ~/.bashrc` and then `start-claw` (or `start-claw --lan` to expose it on your local network) directly on the device. OpenClaw cannot run as a service or in the background, so if you start it from an SSH session it will stop as soon as that session closes.

## 📋 Before You Start

- **Termux from F-Droid**
- **64-bit Android device**
- **Android 12+** for no-PRoot (recommended), **Android 7+** for PRoot
- **Storage:** 2GB+ for no-PRoot, 4GB+ for PRoot (6GB recommended)
- **4GB+ RAM** (6GB+ recommended)
- **Stable internet connection**

Each installation guide contains the complete requirements, install options, post-install setup, daily commands, and troubleshooting for that mode.

## 📚 Documentation

- **[Termux setup](#-termux-setup)** — Install Termux and connect over SSH from your computer
- **[No-PRoot setup guide](termux/no-proot/README.md)** — Recommended Termux-native installation
- **[No-PRoot troubleshooting](termux/no-proot/TROUBLESHOOTING.md)** — Common Termux-native issues
- **[With-PRoot setup guide](termux/with-proot/README.md)** — Debian/`proot-distro` installation
- **[With-PRoot troubleshooting](termux/with-proot/TROUBLESHOOTING.md)** — Common Debian/PRoot issues
- **[QUICKREF.md](QUICKREF.md)** — Quick reference card
- **[CHANGELOG.md](CHANGELOG.md)** — Version history
- **[DISCLAIMER.md](DISCLAIMER.md)** — Project scope, attribution, and liability

## ✨ Features

- **Two installation modes** — Lightweight Termux-native (recommended) or Debian/PRoot
- **No Android root required** — Both modes run without root access
- **Android networking fixes** — Compatibility patches for Android/Termux limitations
- **Update helpers** — Installer update checks and mode-specific update commands
- **Flexible setup** — Choose Debian compatibility or a smaller Termux-only runtime

## ⚠️ Important Disclaimer

**This is an independent community installer project, not the OpenClaw framework itself.**

- OpenClaw is created and maintained by its own team: [openclaw/openclaw](https://github.com/openclaw/openclaw)
- This project is not affiliated with or endorsed by the OpenClaw team
- The installers download and configure OpenClaw; they do not claim ownership of it
- The no-PRoot installer may apply local Android compatibility patches to the installed OpenClaw package

📄 **[Read the full disclaimer](DISCLAIMER.md)** for scope, attribution, and liability details.

## 🤝 Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

Ways to contribute:

- Report bugs with detailed logs
- Suggest features or documentation improvements
- Test on different Android devices and versions
- Submit pull requests

## 🙏 Acknowledgments

- **OpenClaw** — The AI agent framework, created and maintained by the OpenClaw team and contributors
- **[@iyeoh88-svg](https://github.com/iyeoh88-svg) and the [upstream openclaw-android project](https://github.com/iyeoh88-svg/openclaw-android)** — Original installer, documentation, and Android/Termux setup work this fork builds on
- **[AidanPark/openclaw-android](https://github.com/AidanPark/openclaw-android)** — Android compatibility patch work used by the no-PRoot installer
- **Termux and F-Droid** — The terminal environment and distribution channel for Android
- **Debian, PRoot, and `proot-distro`** — Runtime foundation for the With-PRoot option
- **Node.js, NVM, and npm** — JavaScript runtime and package tooling
- **`glibc-runner` and Termux package maintainers** — glibc runtime support used by the no-PRoot option
- **Community testers and contributors** — Everyone who reported bugs, tested devices, and improved the guides

## 📝 License

This installer project is licensed under the **MIT License** — see [LICENSE](LICENSE).

OpenClaw has its own license; see the official OpenClaw repository for details.

## 📞 Support & Community

### Before asking for help

1. Open the setup guide for your installation mode:
   - [No-PRoot setup guide](termux/no-proot/README.md) (recommended)
   - [With-PRoot setup guide](termux/with-proot/README.md)
2. Check the matching troubleshooting guide:
   - [No-PRoot troubleshooting](termux/no-proot/TROUBLESHOOTING.md)
   - [With-PRoot troubleshooting](termux/with-proot/TROUBLESHOOTING.md)
3. Include your installation mode, device model, Android version, Termux source, installer command, and relevant error output.

### Where to ask

- **Installer issues and feature requests:** Use the upstream project's [GitHub Issues](https://github.com/iyeoh88-svg/openclaw-android/issues). Issue and discussion tracking is not enabled on this fork.
- **Questions and general help:** Use the upstream [GitHub Discussions](https://github.com/iyeoh88-svg/openclaw-android/discussions).
- **This fork's source code:** [anhkind/openclaw-android](https://github.com/anhkind/openclaw-android).
- **OpenClaw framework issues:** Visit the [official OpenClaw repository](https://github.com/openclaw/openclaw) or the [OpenClaw documentation](https://docs.openclaw.ai).

Please do not report OpenClaw framework bugs through the installer project. OpenClaw features, models, APIs, and runtime behavior are handled by the OpenClaw team.

## 🔗 Quick Links

- **Without PRoot (recommended):** [Installer](https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh) · [Guide](termux/no-proot/README.md) · [Troubleshooting](termux/no-proot/TROUBLESHOOTING.md)
- **With PRoot:** [Installer](https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh) · [Guide](termux/with-proot/README.md) · [Troubleshooting](termux/with-proot/TROUBLESHOOTING.md)
- **Changelog:** [Version history](CHANGELOG.md)
- **Disclaimer:** [Project scope](DISCLAIMER.md)

---

**Made with ❤️ for the Android AI community**

*Bringing AI agents to mobile devices, one install at a time*
