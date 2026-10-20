# Troubleshooting: OpenClaw with PRoot

This guide covers the Debian/PRoot installation in [`install.sh`](install.sh). For the Termux-native installation, use [No-PRoot troubleshooting](../no-proot/TROUBLESHOOTING.md).

Before changing anything, run the basic diagnostics:

```bash
# In Termux
termux-info
proot-distro login debian --user openclaw

# Inside Debian
openclaw --version
node --version
npm --version
openclaw doctor
openclaw logs --follow
```

If you are using an older installer, update it first:

```bash
# In Termux
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh
```

## Table of Contents

- [Installation issues](#installation-issues)
- [Runtime errors](#runtime-errors)
- [Performance problems](#performance-problems)
- [Network issues](#network-issues)
- [Storage issues](#storage-issues)
- [API configuration](#api-configuration)
- [Advanced debugging](#advanced-debugging)
- [Reset procedures](#reset-procedures)
- [Getting help](#getting-help)

## Installation issues

### `pkg: command not found`

You are not running the command in Termux.

```bash
# If you are inside Debian, leave it first
exit

# Then run Termux commands
pkg update
```

### `curl: command not found`

```bash
pkg install curl -y
```

### `proot-distro: command not found`

```bash
pkg update
pkg install proot-distro -y
```

### “Distribution is already installed”

You can keep the existing installation or replace it.

```bash
# Keep the existing Debian container
proot-distro login debian --user openclaw

# Replace it completely (deletes all data inside Debian)
proot-distro remove debian
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh --reinstall
```

### Installation hangs while upgrading packages

Update to the current installer. Current versions set non-interactive package options and handle configuration-file conflicts.

```bash
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh
```

If the package prompt still appears, choose the default action with Enter, or press `N` to keep the current configuration. Then rerun the installer.

### `nvm: command not found`

Log in as the `openclaw` user and load NVM from the shell configuration:

```bash
proot-distro login debian --user openclaw
source ~/.bashrc
nvm --version
```

If NVM is missing entirely, rerun the installer. Manual repair:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
nvm install 24
nvm use 24
nvm alias default 24
```

### `df: Unknown option 'm'`

This affected older installers. Current versions use compatible `df -k` checks. Update the installer.

### Version shows concatenated numbers

This affected older update checks (for example, `2026.2.6 2026.2.7`). Update the installer; current versions trim whitespace before comparing versions.

### “No command y found” when answering prompts

This affected older installers. Current versions read prompts from `/dev/tty`, so they also work with `curl | bash`. Update the installer.

### `Permission denied` creating the setup script

The installer now writes temporary files under `$HOME` instead of `/tmp`.

```bash
# In Termux
termux-setup-storage
bash install.sh
```

If the error persists, check that your Termux home is writable:

```bash
touch "$HOME/.openclaw-write-test" && rm "$HOME/.openclaw-write-test"
```

### “Don't run this as root!” (Homebrew or other tools)

OpenClaw and Homebrew must run as the dedicated non-root user.

```bash
proot-distro login debian --user openclaw
```

For an existing installation that still uses root, create the user and sudo rule manually:

```bash
# In Termux, log in as root inside Debian
proot-distro login debian

# Create the user
useradd -m -s /bin/bash openclaw
echo "openclaw ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-openclaw
chmod 0440 /etc/sudoers.d/90-openclaw
chown -R openclaw:openclaw /home/openclaw
exit

# Log in as the new user from now on
proot-distro login debian --user openclaw
```

The user has passwordless sudo, but running OpenClaw itself as root is not supported.

### Error 13 during `openclaw onboard`, `openclaw config`, or `openclaw tui`

```text
SystemError [ERR_SYSTEM_ERROR]: uv_interface_addresses returned Unknown system error 13
```

Android blocks Node.js from reading low-level network interfaces. The installer creates a compatibility shim and loads it through `NODE_OPTIONS` for all OpenClaw commands.

Check the shim and shell configuration inside Debian:

```bash
ls -la "$HOME/openclaw-shim.cjs"
grep NODE_OPTIONS ~/.bashrc
```

The line should look like this:

```bash
export NODE_OPTIONS="--require $HOME/openclaw-shim.cjs"
```

Reload the shell and retry:

```bash
source ~/.bashrc
openclaw onboard
```

If the shim is missing, rerun the installer. Older guides tell you to create a short `os.networkInterfaces` stub at `/root/openclaw-shim.cjs`; that is outdated. The current installer writes the full shim at `$HOME/openclaw-shim.cjs` and also handles the PRoot gateway-lock issue.

### Onboarding skips model selection

Use the manual configuration menu instead:

```bash
# Inside Debian as openclaw
openclaw config
```

Or configure from the command line:

```bash
openclaw config set providers.anthropic.apiKey "your-api-key-here"
openclaw config set defaultProvider anthropic
openclaw config set defaultModel "claude-sonnet-4-20250514"
openclaw config list
```

### `No space left on device` during installation

```bash
# In Termux
df -h "$HOME"
pkg clean

# Inside Debian, if it is already installed
npm cache clean --force
sudo apt clean
sudo apt autoremove -y
```

Free space on the Android device if Termux is still short on storage.

### `curl: (23) Failure writing output` or interrupted download

The download was interrupted or storage is full. Check free space, then rerun:

```bash
pkg clean
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh
```

## Runtime errors

### `openclaw: command not found`

```bash
# Inside Debian as openclaw
source ~/.bashrc
which node
which npm
npm list -g openclaw
```

If OpenClaw is not installed:

```bash
npm install -g openclaw@latest --allow-scripts=openclaw
```

If it is installed but still not found, confirm that NVM's Node.js `bin` directory is on `PATH`:

```bash
echo "$PATH"
nvm current
```

Then reload `.bashrc` or log in again.

### `Cannot find module '...'`

```bash
# Inside Debian
npm cache clean --force
npm install -g openclaw@latest --allow-scripts=openclaw --force
openclaw doctor --fix
```

### Gateway will not start

```bash
# Inside Debian
claw-status
claw-logs
```

Also check whether a previous gateway is still running:

```bash
ps aux | grep -i openclaw | grep -v grep
```

Stop the stale process by PID, then start again:

```bash
kill <PID>
start-claw
```

If the gateway reports that its address is already in use, choose another local port:

```bash
NODE_OPTIONS="--require $HOME/openclaw-shim.cjs" \
  openclaw gateway --bind loopback --port 18790
```

### TUI shows “connection refused”

1. Make sure the gateway is running in another Termux session.
2. Make sure both sessions are logged in as the same `openclaw` user.
3. Check the gateway output for the actual address and port.
4. If you changed the gateway port, pass the same port to the TUI:

```bash
openclaw tui --port 18790
```

### `EACCES: permission denied`

Do not create a second npm prefix unless you have a specific reason. The installer uses the Node.js installation managed by NVM.

Try reloading the environment and repairing permissions first:

```bash
# Inside Debian
source ~/.bashrc
sudo chown -R openclaw:openclaw /home/openclaw
openclaw doctor --fix
```

If you intentionally use a custom npm prefix, make sure its `bin` directory is on `PATH` and is owned by `openclaw`.

### Gateway is killed with signal 9

Android is terminating the process, usually because of battery optimization or the Phantom Process Killer.

- Set Termux battery usage to **Unrestricted**.
- Disable the Phantom Process Killer. See the [reference guide](https://github.com/AidanPark/openclaw-android/blob/main/docs/disable-phantom-process-killer.md).
- Run `termux-wake-lock` in Termux while the gateway is running.
- Keep the device connected to power during long sessions.

### “Address already in use”

Find the process using the port:

```bash
# Install lsof if needed
sudo apt install -y lsof

# Replace 18789 with the port shown in the gateway error
lsof -i :18789
```

Stop the old process by PID:

```bash
kill <PID>
```

If the process does not exit, use `kill -9 <PID>` as a last resort, then start the gateway again.

## Performance problems

### OpenClaw is very slow

1. Enable the wake lock in Termux:

```bash
termux-wake-lock
```

2. Set Termux battery usage to **Unrestricted** in Android settings.

3. Close other apps to free RAM.

4. Check memory and storage:

```bash
# Inside Debian
free -h
df -h
```

5. If Node.js needs more heap, keep the shim and add a memory limit:

```bash
# Inside Debian, add to ~/.bashrc
export NODE_OPTIONS="--max-old-space-size=2048 --require $HOME/openclaw-shim.cjs"
```

Do not set `NODE_OPTIONS` to only `--max-old-space-size`; that removes the required compatibility shim.

### Gateway uses too much CPU

Reduce the Node.js heap size while keeping the shim:

```bash
NODE_OPTIONS="--require $HOME/openclaw-shim.cjs --max-old-space-size=1024" \
  openclaw gateway --bind loopback
```

Also check for stale OpenClaw processes:

```bash
ps aux | grep -i openclaw | grep -v grep
```

### System becomes unresponsive

1. Stop the gateway with `Ctrl+C`.
2. Close other apps.
3. Clear caches:

```bash
# In Termux
pkg clean

# Inside Debian
npm cache clean --force
sudo apt clean
```

4. Restart Termux if the device is still under memory pressure.

## Network issues

### `ENOTFOUND` or DNS errors

Test connectivity in Termux first, then inside Debian:

```bash
# In Termux
ping -c 3 8.8.8.8

# Inside Debian
ping -c 3 8.8.8.8
```

If Termux works but Debian does not, restart the PRoot session:

```bash
exit
proot-distro login debian --user openclaw
```

### API requests time out

1. Check your internet connection.
2. Try a different network (Wi-Fi versus mobile data).
3. Check the provider's status page.
4. Retry the request after restarting the gateway.

### “Cannot reach gateway”

The gateway listens on loopback by default. Confirm it is running:

```bash
claw-status
```

If you intentionally need to expose it on the local network, be aware that this increases risk:

```bash
NODE_OPTIONS="--require $HOME/openclaw-shim.cjs" \
  openclaw gateway --bind 0.0.0.0
```

Do not expose the gateway to the public internet without authentication and a firewall.

## Storage issues

### `ENOSPC: no space left on device`

```bash
# In Termux
pkg clean
df -h "$HOME"

# Inside Debian
npm cache clean --force
sudo apt clean
sudo apt autoremove -y
```

Remove old OpenClaw logs if they are large:

```bash
# Inside Debian
rm -f /tmp/openclaw/*.log.old
```

Check the largest directories:

```bash
du -sh ~/.openclaw/* 2>/dev/null
du -sh ~/.npm/* 2>/dev/null
```

### npm install fails because of storage

```bash
# Inside Debian
npm cache clean --force
npm install -g openclaw@latest --allow-scripts=openclaw --prefer-online --no-audit
```

Free storage before retrying rather than forcing the install repeatedly.

## API configuration

### “Invalid API key”

```bash
# Inside Debian
openclaw onboard
```

Or set the key directly:

```bash
openclaw config set providers.anthropic.apiKey "your-api-key-here"
```

Check that the key is active and has access to the selected model.

### “Rate limit exceeded”

1. Wait for the provider's quota window to reset.
2. Check the provider's usage dashboard.
3. Switch to another provider or model temporarily:

```bash
openclaw onboard
```

### “API endpoint not responding”

1. Check the provider's status page.
2. Test general connectivity from Debian.
3. Confirm the API base URL and key in `openclaw config list`.
4. Try another provider to determine whether the issue is provider-specific.

## Advanced debugging

### Enable debug logging

```bash
# Inside Debian
export DEBUG=openclaw:*
start-claw
```

For specific modules:

```bash
export DEBUG=openclaw:gateway,openclaw:api
start-claw
```

### Check OpenClaw logs

```bash
# Inside Debian
openclaw logs --follow
openclaw logs --limit 100 --plain

# Raw log files, if present
ls -la /tmp/openclaw/
grep -i error /tmp/openclaw/*.log
```

### Collect system information

```bash
# In Termux
getprop ro.build.version.release
termux-info

# Inside Debian
uname -a
node --version
npm --version
openclaw --version
free -h
df -h
```

### Monitor processes

```bash
# Inside Debian
ps aux | grep -i openclaw | grep -v grep
top
```

To watch memory usage:

```bash
while true; do
  ps aux | grep -i openclaw | grep -v grep
  sleep 5
done
```

### Debug network connectivity

```bash
# Inside Debian
ping -c 3 8.8.8.8
getent hosts api.openai.com
curl -I https://api.openai.com
```

Check listening ports if `ss` or `netstat` is available:

```bash
ss -ltnp 2>/dev/null || netstat -tlnp 2>/dev/null
```

## Reset procedures

### Reset OpenClaw configuration only

> This removes OpenClaw's configuration, sessions, and local state. Back up `~/.openclaw` first if you need it.

```bash
# Inside Debian
rm -rf ~/.openclaw
npm install -g openclaw@latest --allow-scripts=openclaw --force
openclaw onboard
```

### Reset the Debian environment

> This deletes the Debian container and everything inside it.

```bash
# In Termux
proot-distro remove debian
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh --reinstall
```

### Reset the installer cache

The With-PRoot installer writes temporary files in the Termux home directory. Remove only the generated helpers you no longer need:

```bash
# In Termux
rm -f "$HOME/start-openclaw.sh" "$HOME/debian_setup.sh" "$HOME/install_new.sh"
```

Do not delete `~/.openclaw` unless you intend to remove OpenClaw data.

### Reset everything

```bash
# In Termux
proot-distro remove debian
pkg uninstall proot-distro -y
pkg clean
rm -f "$HOME/start-openclaw.sh" "$HOME/debian_setup.sh" "$HOME/install_new.sh"

# Start again
curl -fsSL https://raw.githubusercontent.com/anhkind/openclaw-android/main/termux/with-proot/install.sh -o install.sh
bash install.sh --reinstall
```

## Getting help

If the steps above do not solve the problem:

1. Collect a debug report:

```bash
# In Termux
{
  echo "=== Android ==="
  getprop ro.build.version.release
  termux-info
  echo "=== Installer ==="
  ls -la "$HOME/start-openclaw.sh" 2>/dev/null
} > debug-report.txt

# Inside Debian
{
  echo "=== Versions ==="
  node --version
  npm --version
  openclaw --version
  echo "=== Doctor ==="
  openclaw doctor 2>&1
  echo "=== Logs ==="
  openclaw logs --limit 100 --plain 2>&1
} >> debug-report.txt
```

2. Search [existing issues](https://github.com/iyeoh88-svg/openclaw-android/issues).
3. Open a [new issue](https://github.com/iyeoh88-svg/openclaw-android/issues/new) with:
   - Android version and device model
   - Termux version and source (F-Droid or Play Store)
   - Installer version
   - The debug report or relevant logs
   - Steps to reproduce the problem

For Termux-native installations, see the [No-PRoot troubleshooting guide](../no-proot/TROUBLESHOOTING.md).

---

**Last updated**: October 2026  
**Applies to**: `termux/with-proot/install.sh`  
**Related**: [With-PRoot guide](README.md) · [No-PRoot troubleshooting](../no-proot/TROUBLESHOOTING.md)
