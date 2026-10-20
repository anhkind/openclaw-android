# OpenClaw for Termux (no proot)

Install OpenClaw directly inside Termux on Android, without Debian, `proot-distro`, or a Linux container. This is the installer for the OnePlus 11 (`arm64`) and other 64-bit Android devices running Termux from F-Droid.

The installer uses:

- Termux `pacman` and `glibc-runner` for the glibc loader
- The official Node.js `linux-arm64` tarball, verified against its `SHASUMS256.txt`
- The Android compatibility patches from [AidanPark/openclaw-android](https://github.com/AidanPark/openclaw-android)
- OpenClaw pinned to `2026.10.2` by default, because that is the version the embedded patches were verified against

## Requirements

- **Termux from [F-Droid](https://f-droid.org/en/packages/com.termux/)**. Do not use the Google Play version.
- **64-bit ARM (`arm64`)**. The OnePlus 11 is supported.
- **Android 12+** recommended.
- **2 GB free storage minimum**, 4 GB recommended.
- **A stable internet connection**.
- Android battery optimization disabled for Termux, and the Phantom Process Killer disabled if Android kills the gateway.

> OpenClaw and Node.js both run as your normal Termux user. No root access is required.

## Install

### One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh | bash
```

### Review first

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh -o install.sh
less install.sh
bash install.sh
```

The installer asks before making changes unless you pass `--yes`.

## Setup after installation

Open a new Termux session, or reload your shell:

```bash
source ~/.bashrc
```

Then run the first-time setup and start the gateway:

```bash
# Configure your model provider and gateway once
openclaw onboard

# Start the gateway on loopback
start-claw

# In another Termux session, open the terminal UI
openclaw tui
```

The dashboard is available with `openclaw dashboard`.

### Manual configuration

If onboarding skips steps, use the configuration menu:

```bash
openclaw config
```

Or configure from the command line:

```bash
openclaw config set providers.anthropic.apiKey "your-api-key-here"
openclaw config set defaultProvider anthropic
openclaw config set defaultModel "claude-sonnet-4-20250514"
openclaw config list
```

## Options

| Option | Description |
| --- | --- |
| `--node 24` | Use Node.js 24 LTS. This is the default. |
| `--node 26` | Use Node.js 26. |
| `--openclaw <version>` | Install a specific OpenClaw version. |
| `--latest` | Install the latest OpenClaw release. The Android patches may need updating for a newer release. |
| `--update` | Reinstall OpenClaw and re-apply the Android patches. |
| `--repair` | Re-apply the compatibility patches and launcher without reinstalling Node.js or OpenClaw. |
| `--reinstall` | Remove the existing OpenClaw package before installing. |
| `--skip-update-check` | Skip the installer self-update check. |
| `--yes`, `-y` | Accept all prompts. Intended for unattended installs. |
| `--help`, `-h` | Show help. |

Examples:

```bash
# Use Node.js 26
bash install.sh --node 26

# Install a specific OpenClaw version
bash install.sh --openclaw 2026.10.2

# Unattended install
bash install.sh --yes
```

## Updating OpenClaw

Use the generated helper:

```bash
update-claw
```

`update-claw` reruns the saved installer with `--update --yes`, so the Android patches are re-applied after OpenClaw is updated. Extra options are forwarded:

```bash
update-claw --latest
update-claw --node 26
update-claw --openclaw 2026.10.2
update-claw --reinstall
```

Do not run `openclaw update` directly. The launcher blocks it on purpose because a normal OpenClaw update would replace the patched files and break the Termux compatibility layer.

To repair only the patches and launcher:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

## Generated files

All generated scripts live under `~/.openclaw-android`. OpenClaw's own data and configuration remain in `~/.openclaw` and are not used for installer files.

| Path | Purpose |
| --- | --- |
| `~/.openclaw-android/` | Node.js runtime, npm globals, glibc compatibility shim, and patches. |
| `~/.openclaw-android/bin/openclaw` | Generated OpenClaw launcher. |
| `~/.openclaw-android/bin/systemctl` | Termux `systemctl` compatibility stub. |
| `~/.openclaw-android/update-claw.sh` | Update helper used by the `update-claw` command. |
| `~/.openclaw-android/start-openclaw.sh` | Standalone gateway launcher. |
| `~/.openclaw-android/installer/install.sh` | Saved copy of this installer, used by `update-claw`. |
| `~/.openclaw-android/install.sh.new` | Temporary download used by the installer self-update. |
| `$PREFIX/bin/openclaw` | Symlink to the generated launcher. |
| `$PREFIX/bin/systemctl` | Symlink to the generated compatibility stub. |
| `~/.bashrc` | PATH, environment variables, and aliases. |

No installer scripts or downloads are stored in `~/.openclaw`; that directory belongs to OpenClaw and is left for OpenClaw to create and manage.

## Commands

| Command | Description |
| --- | --- |
| `start-claw` | Start the OpenClaw gateway on loopback. |
| `openclaw onboard` | First-time setup wizard. |
| `openclaw config` | Manual configuration menu. |
| `openclaw tui` | Terminal interface. |
| `openclaw dashboard` | Open the browser control UI. |
| `openclaw doctor` | Run health checks and repairs. |
| `update-claw` | Update/reinstall OpenClaw through this installer. |
| `claw-status` | Show gateway status. |
| `claw-logs` | Follow gateway logs. |
| `claw-doctor` | Run the doctor command. |
| `claw-dashboard` | Open the dashboard. |
| `claw-ps` | List OpenClaw processes. |

## Troubleshooting

For the full guide, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

### `openclaw: command not found`

Reload the shell configuration:

```bash
source ~/.bashrc
```

The launcher is also available directly at `$PREFIX/bin/openclaw`.

### Android kills the gateway (signal 9)

- Set Termux battery usage to **Unrestricted** in Android settings.
- Disable the Phantom Process Killer. See the [reference guide](https://github.com/AidanPark/openclaw-android/blob/main/docs/disable-phantom-process-killer.md).
- The installer enables a wake lock. Keep it active while the gateway is running, or use `termux-wake-unlock` to release it.

### Patch warnings during install or update

The embedded patches are verified against OpenClaw `2026.10.2`. Installing a newer version with `--latest` may produce `NOMATCH` or `WRITEFAIL` warnings. Reinstall the verified version, or update the patches before using a newer release:

```bash
update-claw --openclaw 2026.10.2
```

If `openclaw doctor --fix` reports `EACCES`, run the repair mode:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

## Alternative: with PRoot

If you need Debian packages, Homebrew, or the more established compatibility path, use the [With-PRoot installer](../with-proot/README.md).

## Notes

- There is no `proot-distro login` step.
- `openclaw update` is intentionally blocked. Use `update-claw`.
- The installer checks for its own updates through the repository `VERSION` file.
- OpenClaw is a separate project. This repository only provides the Android/Termux installer and compatibility patches.
