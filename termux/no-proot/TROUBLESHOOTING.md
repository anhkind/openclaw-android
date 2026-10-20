# Troubleshooting: OpenClaw on Termux (no PRoot)

This guide covers the Termux-native installer in [`install.sh`](install.sh). It does not use Debian, `proot-distro`, or a Linux container. For the PRoot installation, use [With-PRoot troubleshooting](../with-proot/TROUBLESHOOTING.md).

The no-PRoot installer currently:

- Targets 64-bit ARM (`arm64`) Termux, including the OnePlus 11.
- Uses Termux `pacman` and `glibc-runner` to provide the glibc loader.
- Installs the official Node.js `linux-arm64` tarball and verifies it against `SHASUMS256.txt`.
- Installs OpenClaw pinned to `2026.10.2` by default.
- Applies the Android compatibility patches from [AidanPark/openclaw-android](https://github.com/AidanPark/openclaw-android).

Run these first:

```bash
termux-info
uname -m
node --version
openclaw --version
openclaw doctor
openclaw logs --follow
```

If you are using an older installer, update it first:

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh -o install.sh
bash install.sh
```

## Table of Contents

- [Installation issues](#installation-issues)
- [Runtime errors](#runtime-errors)
- [Gateway and process issues](#gateway-and-process-issues)
- [Performance problems](#performance-problems)
- [Storage issues](#storage-issues)
- [Network issues](#network-issues)
- [API configuration](#api-configuration)
- [Updating and repairing](#updating-and-repairing)
- [Advanced debugging](#advanced-debugging)
- [Reset procedures](#reset-procedures)
- [Getting help](#getting-help)

## Installation issues

### Termux is from the Play Store or is too old

Use **Termux from F-Droid**:

<https://f-droid.org/en/packages/com.termux/>

The Play Store build is outdated. Uninstall it, install the F-Droid build, and run the installer again. Do not install both over the same data directory.

### `Unsupported architecture`

The no-PRoot flow supports **64-bit ARM (`arm64`)**. Check:

```bash
uname -m
```

The expected result is `aarch64`. The installer does not support 32-bit ARM or x86_64 in this mode. Use the [With-PRoot installer](../with-proot/README.md) on other architectures.

### `pkg: command not found`

You are not in Termux, or the shell is not Termux's shell.

```bash
# If you are in another environment, exit first
exit

# Then use Termux
pkg update
```

### `curl: command not found`

```bash
pkg install curl -y
```

### `pacman: command not found` or pacman keyring errors

The installer uses Termux `pacman` to provide `glibc-runner`. Refresh Termux packages and retry:

```bash
pkg update
pkg upgrade -y
pkg install pacman -y
```

If pacman reports keyring or signature errors, update the Termux packages and rerun the installer. If the problem persists, collect the full pacman output for a bug report.

### `glibc-runner` installation failed

```bash
pkg update
pkg install glibc-runner -y
```

Then rerun the installer. The glibc loader is expected at:

```bash
ls -la "$PREFIX/glibc/lib/ld-linux-aarch64.so.1"
```

If the file is missing, the glibc runtime was not installed correctly.

### Node.js download or checksum verification failed

The installer downloads the official Node.js `linux-arm64` tarball and verifies it against `SHASUMS256.txt`.

```bash
# Check basic connectivity
curl -I https://nodejs.org

# Check storage
df -h "$HOME"
```

If the download was interrupted, rerun the installer. If the checksum fails repeatedly, do not disable verification; report the exact Node.js version and checksum error.

### `npm install` fails while installing OpenClaw

Check free storage first:

```bash
df -h "$HOME"
```

Then try the repair/update path:

```bash
update-claw --reinstall
```

If npm reports a lifecycle-script or postinstall error, the installer may be using an npm version with stricter script policies. Use the installer's saved copy so its npm wrapper and flags are applied:

```bash
bash ~/.openclaw-android/installer/install.sh --update --yes
```

### Patch warnings: `NOMATCH`, `WRITEFAIL`, or `NOTARGET`

The embedded patches are verified against OpenClaw **2026.10.2**. A newer OpenClaw release may change the files the patches expect.

Reinstall the verified version:

```bash
update-claw --openclaw 2026.10.2
```

Or repair the current installation:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

`NOMATCH` means a patch could not find the expected code. `WRITEFAIL` means the patch matched but could not write the file. Do not ignore these warnings if OpenClaw fails to start; use the verified version or update the patches.

### `openclaw doctor --fix` reports `EACCES`

Run repair mode so the installer re-applies its permissions and compatibility fixes:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

### Installation hangs or stops

1. Check the network.
2. Close other apps to free memory.
3. Check storage with `df -h "$HOME"`.
4. Rerun the installer.

If it stopped after installing packages but before OpenClaw, use:

```bash
bash ~/.openclaw-android/installer/install.sh --update --yes
```

## Runtime errors

### `openclaw: command not found`

Reload the shell configuration:

```bash
source ~/.bashrc
```

If that does not work, call the launcher directly:

```bash
"$PREFIX/bin/openclaw" --version
```

Check the symlinks:

```bash
ls -la "$PREFIX/bin/openclaw"
ls -la "$PREFIX/bin/systemctl"
```

The launcher is generated at `~/.openclaw-android/bin/openclaw`. If the symlink is missing, run repair mode:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

### `node: cannot execute` or glibc loader errors

The Node.js binary is loaded through Termux's glibc runtime. Check:

```bash
"$PREFIX/glibc/lib/ld-linux-aarch64.so.1" --version
~/.openclaw-android/bin/node --version
```

If the loader or wrapper is missing, reinstall the runtime:

```bash
pkg install glibc-runner -y
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

Do not replace the generated Node wrapper with a plain `node` binary. The wrapper supplies the glibc loader and compatibility module.

### `openclaw update` is blocked

This is intentional. A normal OpenClaw update would replace the patched files and break the Android compatibility layer.

Use:

```bash
update-claw
```

`update-claw` reruns the saved installer with `--update --yes` and re-applies the patches. Options are forwarded:

```bash
update-claw --latest
update-claw --node 26
update-claw --openclaw 2026.10.2
update-claw --reinstall
```

### Error 13 or network-interface errors

The no-PRoot installer uses a glibc compatibility module that replaces the unsupported network-interface calls.

Try repair mode first:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

Then check:

```bash
~/.openclaw-android/bin/node -e "console.log(require('os').networkInterfaces())"
```

If the command fails, the compatibility module or Node wrapper is missing. Rerun the installer rather than editing the generated files by hand.

### `systemctl` does not behave like systemd

The installer creates a `systemctl` compatibility stub at `$PREFIX/bin/systemctl` because some OpenClaw flows expect a `systemctl` command. It is not a real service manager.

Use the OpenClaw commands instead:

```bash
start-claw
claw-status
claw-logs
```

### `Cannot find module` errors

```bash
npm cache clean --force
update-claw --reinstall
```

If the error returns, run:

```bash
openclaw doctor --fix
```

### OpenClaw starts but immediately exits

Check the logs and the Node wrapper:

```bash
claw-logs
openclaw doctor
~/.openclaw-android/bin/node --version
```

Then repair the installation:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

## Gateway and process issues

### Gateway will not start

```bash
claw-status
claw-logs
claw-ps
```

If an old gateway is still running, stop it by PID:

```bash
kill <PID>
start-claw
```

Then start a fresh gateway:

```bash
start-claw
```

### TUI shows “connection refused”

1. Make sure the gateway is running in another Termux session.
2. Make sure both sessions use the same Termux user.
3. Check the gateway output for the selected port.
4. If you changed the port, pass it to the TUI:

```bash
openclaw tui --port 18790
```

### Android kills the gateway (signal 9)

- Set Termux battery usage to **Unrestricted** in Android settings.
- Disable the Phantom Process Killer. See the [reference guide](https://github.com/AidanPark/openclaw-android/blob/main/docs/disable-phantom-process-killer.md).
- Keep the wake lock active while the gateway runs:

```bash
termux-wake-lock
```

Release it when finished:

```bash
termux-wake-unlock
```

### “Address already in use”

Find the old process:

```bash
claw-ps
```

Stop it by PID:

```bash
kill <PID>
```

If it does not exit, use `kill -9 <PID>` as a last resort, then restart the gateway.

## Performance problems

### OpenClaw is slow

1. Enable the wake lock:

```bash
termux-wake-lock
```

2. Set Termux battery usage to **Unrestricted**.
3. Close other Android apps to free RAM.
4. Check memory:

```bash
free -h
```

5. Add a Node.js heap limit if needed. The launcher already applies the compatibility module; do not remove it:

```bash
# In ~/.bashrc
export NODE_OPTIONS="--max-old-space-size=2048"
```

The no-PRoot Node wrapper adds the glibc compatibility module separately. If you override `NODE_OPTIONS`, verify that OpenClaw still starts; otherwise remove the custom value.

### Gateway uses too much CPU

Check for duplicate gateway processes:

```bash
claw-ps
```

Stop stale processes and restart:

```bash
kill <PID>
start-claw
```

You can also lower the heap limit:

```bash
NODE_OPTIONS="--max-old-space-size=1024" start-claw
```

### Termux becomes unresponsive

1. Stop the gateway with `Ctrl+C`.
2. Close other apps.
3. Clear caches:

```bash
pkg clean
npm cache clean --force
```

4. Restart Termux if memory is still exhausted.

## Storage issues

### `ENOSPC: no space left on device`

The installer keeps Node.js, npm globals, patches, and generated scripts under `~/.openclaw-android`.

```bash
df -h "$HOME"
du -sh ~/.openclaw-android
du -sh ~/.openclaw 2>/dev/null
```

Clean caches:

```bash
npm cache clean --force
pkg clean
```

Remove old Node.js tarballs or temporary files under `~/.openclaw-android` only if you know they are not part of the active runtime. Then run:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

### npm install fails because of storage

```bash
npm cache clean --force
update-claw --reinstall
```

Free storage before retrying. Do not use `--force` repeatedly on a full device.

## Network issues

### `ENOTFOUND` or DNS errors

Test connectivity:

```bash
ping -c 3 8.8.8.8
curl -I https://api.openai.com
```

Try switching between Wi-Fi and mobile data. If DNS works in other Android apps but not Termux, check Termux's network permissions and restart Termux.

### API requests time out

1. Check the provider's status page.
2. Test general connectivity with `curl`.
3. Try another network.
4. Restart the gateway after changing networks.

### “Cannot reach gateway”

The gateway binds to loopback by default. Confirm it is running:

```bash
claw-status
```

If you intentionally expose it on the local network, understand the risk and use:

```bash
openclaw gateway --bind 0.0.0.0
```

Do not expose the gateway to the public internet without authentication and a firewall.

## API configuration

### “Invalid API key”

```bash
openclaw onboard
```

Or configure directly:

```bash
openclaw config set providers.anthropic.apiKey "your-api-key-here"
openclaw config set defaultProvider anthropic
openclaw config set defaultModel "claude-sonnet-4-20250514"
openclaw config list
```

Check that the key is active and has access to the selected model.

### “Rate limit exceeded”

1. Wait for the provider's quota window to reset.
2. Check the provider's usage dashboard.
3. Switch providers or models temporarily:

```bash
openclaw onboard
```

### “API endpoint not responding”

1. Check the provider's status page.
2. Test connectivity from Termux.
3. Verify the API base URL and key in `openclaw config list`.
4. Try another provider to determine whether the problem is provider-specific.

## Updating and repairing

### Update OpenClaw

```bash
update-claw
```

### Install a specific or latest version

```bash
# Verified version
update-claw --openclaw 2026.10.2

# Latest release; patches may need updating
update-claw --latest
```

### Switch Node.js major version

```bash
update-claw --node 26
```

The installer supports Node.js 24 LTS and Node.js 26. Reinstalling Node.js also re-applies the launcher and patches.

### Repair patches and launcher only

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

### Reinstall OpenClaw

```bash
update-claw --reinstall
```

### Update the installer itself

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh -o install.sh
bash install.sh
```

The installer also checks the repository `VERSION` file when it starts.

## Advanced debugging

### Collect system information

```bash
{
  echo "=== Termux ==="
  termux-info
  uname -a
  echo "=== Storage ==="
  df -h "$HOME"
  echo "=== Versions ==="
  node --version
  npm --version
  openclaw --version
} > debug-report.txt
```

### Check the runtime layout

```bash
ls -la ~/.openclaw-android
ls -la ~/.openclaw-android/bin
ls -la ~/.openclaw-android/lib
ls -la ~/.openclaw-android/patches
```

### Check the generated launcher

```bash
sed -n '1,120p' ~/.openclaw-android/bin/openclaw
```

The launcher should invoke the Node wrapper under `~/.openclaw-android/bin`, not a system Node.js binary.

### Check logs

```bash
openclaw logs --follow
openclaw logs --limit 100 --plain
```

Raw logs, if present:

```bash
ls -la /tmp/openclaw/
grep -i error /tmp/openclaw/*.log
```

### Debug network interfaces

```bash
~/.openclaw-android/bin/node -e "console.log(require('os').networkInterfaces())"
```

### Enable debug logging

```bash
export DEBUG=openclaw:*
start-claw
```

## Reset procedures

### Repair first

Most patch, launcher, and permission problems can be fixed without deleting data:

```bash
bash ~/.openclaw-android/installer/install.sh --repair --yes
```

### Reset OpenClaw configuration only

> This deletes OpenClaw's local configuration and sessions. Back up `~/.openclaw` first if you need it.

```bash
rm -rf ~/.openclaw
openclaw onboard
```

### Reset OpenClaw but keep the runtime

```bash
update-claw --reinstall
```

### Full reset

> This deletes the no-PRoot runtime and, if you remove `~/.openclaw`, your OpenClaw data.

```bash
# Back up anything you need first
rm -rf ~/.openclaw-android
rm -rf ~/.openclaw

# Run the installer again
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/no-proot/install.sh -o install.sh
bash install.sh
```

The installer does not migrate an older Debian/PRoot installation. A no-PRoot install is a fresh installation.

## Getting help

If the steps above do not solve the problem:

1. Save the debug report and the failing command output.
2. Search [existing issues](https://github.com/iyeoh88-svg/openclaw-android/issues).
3. Open a [new issue](https://github.com/iyeoh88-svg/openclaw-android/issues/new) with:
   - Device model and Android version
   - `uname -m` output
   - Termux source (F-Droid or Play Store)
   - Installer version
   - Node.js and OpenClaw versions
   - Patch output, including any `NOMATCH` or `WRITEFAIL` lines
   - Steps to reproduce

For PRoot installations, see the [With-PRoot troubleshooting guide](../with-proot/TROUBLESHOOTING.md).

---

**Last updated**: October 2026  
**Applies to**: `termux/no-proot/install.sh`  
**Related**: [No-PRoot guide](README.md) · [With-PRoot troubleshooting](../with-proot/TROUBLESHOOTING.md)
