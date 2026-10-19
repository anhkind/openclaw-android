# 🔧 Troubleshooting Guide

## Table of Contents
- [Installation Issues](#installation-issues)
- [Runtime Errors](#runtime-errors)
- [Performance Problems](#performance-problems)
- [Network Issues](#network-issues)
- [Storage Issues](#storage-issues)
- [API Configuration](#api-configuration)
- [Advanced Debugging](#advanced-debugging)

## Installation Issues

### ❌ "No command y found" when responding to prompts

**Problem**: After typing "y" at a prompt, you see "No command y found"

**Solution**:
This is fixed in v2026.2.8. Update your installer:
```bash
# Download latest version
curl -O https://raw.githubusercontent.com/anhkind/openclaw-android/main/install.sh
chmod +x install.sh
./install.sh
```

**Why it happened**: The script wasn't reading from the terminal device properly in Termux.

---

### ❌ "Don't run this as root!" (Homebrew or other tools)

**Problem**: Tools like Homebrew refuse to install because everything runs as `root` inside Debian

**This is fixed in v2026.2.14** — the installer now creates a dedicated `openclaw` user.

**For fresh installations**, just re-run the installer:
```bash
curl -O https://raw.githubusercontent.com/anhkind/openclaw-android/main/install.sh
chmod +x install.sh
./install.sh --reinstall
```

Then log in with:
```bash
proot-distro login debian --user openclaw
```

**Manual fix for existing installations:**
```bash
# Log in as root first
proot-distro login debian

# Create dedicated user
useradd -m -s /bin/bash openclaw
echo "openclaw ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Exit root session
exit

# Now always log in as openclaw user
proot-distro login debian --user openclaw
```

**Why it matters**: Running as root blocks Homebrew and several other tools by design. The `openclaw` user has passwordless sudo so you can still install packages when needed.

---

### ❌ Error 13 during `openclaw onboard` or other commands

**Problem**: 
```
SystemError [ERR_SYSTEM_ERROR]: uv_interface_addresses returned Unknown system error 13
```
Appears when running `openclaw onboard`, `openclaw config`, `openclaw tui`, etc.

**Why it happens**: Android blocks low-level network interface access. The networking shim that fixes this was only applied to `start-claw` but not other commands.

**Note:** `start-claw` still works fine even if you see this error during onboard.

**Fix (for existing installations):**

Run this inside Debian to apply the shim globally:

```bash
# Inside Debian (proot-distro login debian)

# Add global shim to bashrc
echo 'export NODE_OPTIONS="--require /root/openclaw-shim.cjs"' >> ~/.bashrc

# Apply immediately
source ~/.bashrc

# Now retry - Error 13 should be gone
openclaw onboard
# or
openclaw config
```

**Permanent fix (v2026.2.13+):**

Re-run the installer to get the global fix applied automatically:

```bash
curl -O https://raw.githubusercontent.com/anhkind/openclaw-android/main/install.sh
chmod +x install.sh
./install.sh --reinstall
```

---

### ❌ OpenClaw onboarding skips model selection

**Problem**: Running `openclaw onboard` skips model selection and jumps directly to channel selection

**Solution**:
Use manual configuration instead of onboarding:

```bash
# Inside Debian (proot-distro login debian)

# Run manual configuration mode
openclaw config

# This opens an interactive menu where you can manually select:
# - model (choose your AI provider and model)
# - skills (configure available skills)
# - channel (telegram, whatsapp, etc.)
# - workspace (set up your workspace)
```

**Alternative - Set via command line:**
```bash
# Set Anthropic (Claude) API key
openclaw config set providers.anthropic.apiKey "your-api-key-here"

# Set default provider
openclaw config set defaultProvider anthropic

# Set model
openclaw config set defaultModel "claude-sonnet-4-20250514"

# List current configuration
openclaw config list
```

**Why it happens**: The onboarding flow may not work correctly on certain Android versions or configurations. Manual configuration provides more control.

---

### ❌ "nvm: command not found" during installation

**Problem**: Node.js installation fails with "nvm: command not found"

**Solution**:
This is fixed in v2026.2.11. Update your installer:
```bash
curl -O https://raw.githubusercontent.com/anhkind/openclaw-android/main/install.sh
chmod +x install.sh
./install.sh
```

**Manual workaround** (if needed):
```bash
# Inside Debian
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Then continue with:
nvm install 24
nvm use 24
nvm alias default 24
npm install -g openclaw@latest --allow-scripts=openclaw
```

**Why it happened**: NVM needs to be explicitly sourced after installation. The script now does this automatically with multiple fallback methods.

---

### ❌ "df: Unknown option 'm'" error

**Problem**: `df: Unknown option 'm'` during storage check

**Solution**:
This is fixed in v2026.2.10. Update your installer:
```bash
curl -O https://raw.githubusercontent.com/anhkind/openclaw-android/main/install.sh
chmod +x install.sh
./install.sh
```

**Why it happened**: Older Termux versions don't support `df -m`. Now uses `df -k` which is more compatible.

---

### ❌ Package upgrade hangs waiting for input

**Problem**: Installation stops at "What would you like to do about it?" prompt during package upgrade

**Solution**:
This is fixed in v2026.2.10. The installer now handles config file conflicts automatically.

Update to latest version:
```bash
curl -O https://raw.githubusercontent.com/anhkind/openclaw-android/main/install.sh
chmod +x install.sh
./install.sh
```

**Manual workaround** (if needed):
During the prompt, press `N` to keep your current config, then re-run the installer.

---

### ❌ Version shows strange concatenated numbers

**Problem**: Update check shows `2026.2.6 2026.2.7` or similar

**Solution**:
This is fixed in v2026.2.8. The version comparison now properly trims whitespace.

---

### ❌ "Permission denied" creating setup script

**Problem**: `/tmp/debian_setup.sh: Permission denied`

**Solution**:
```bash
# In Termux
# Grant storage permissions
termux-setup-storage

# Try the installer again
./install.sh

# If still failing, the installer now uses $HOME instead
# which should work on all Termux versions
```

---

### ❌ "pkg: command not found"

**Problem**: You're not running commands in Termux

**Solution**:
```bash
# Make sure you're in Termux, not in Debian
# Exit Debian if you're in it:
exit

# Now run Termux commands
pkg update
```

---

### ❌ "proot-distro: command not found"

**Problem**: proot-distro not installed

**Solution**:
```bash
# In Termux
pkg update
pkg install proot-distro -y
```

---

### ❌ "Distribution is already installed"

**Problem**: Trying to install Debian when it already exists

**Solution**:
```bash
# Option 1: Use existing installation
proot-distro login debian

# Option 2: Reinstall completely
proot-distro remove debian
proot-distro install --name debian debian:trixie
```

---

### ❌ "No space left on device"

**Problem**: Insufficient storage

**Solution**:
```bash
# Check available space
df -h $HOME

# Clean up Termux
pkg clean

# If still not enough, you need to free up space on your device
```

---

### ❌ "curl: command not found"

**Problem**: curl not installed in Termux

**Solution**:
```bash
# In Termux
pkg install curl -y
```

---

### ❌ Installation hangs or freezes

**Problem**: Network issues or resource constraints

**Solution**:
1. Check your internet connection
2. Close other apps to free up RAM
3. Restart Termux and try again
4. Use `--reinstall` flag if partially installed:
   ```bash
   ./install.sh --reinstall
   ```

## Runtime Errors

### ❌ Error 13: Permission denied (uv_interface_addresses)

**Problem**: This is the Android networking restriction

**Solution**: The installer handles this automatically with the shim. If you see this error:

```bash
# Inside Debian, verify shim exists:
ls -la /root/openclaw-shim.cjs

# If missing, recreate it:
cat > /root/openclaw-shim.cjs << 'EOF'
const os = require('os');
os.networkInterfaces = () => ({
  lo: [{
    address: '127.0.0.1',
    netmask: '255.0.0.0',
    family: 'IPv4',
    mac: '00:00:00:00:00:00',
    internal: true,
    cidr: '127.0.0.1/8'
  }]
});
EOF

# Make sure you're using the start-claw alias
start-claw
```

---

### ❌ "openclaw: command not found"

**Problem**: OpenClaw not installed or not in PATH

**Solution**:
```bash
# Inside Debian, check if installed:
npm list -g openclaw

# If not installed:
npm install -g openclaw@latest --allow-scripts=openclaw

# If installed but not found, reload environment:
source ~/.bashrc

# Check Node is in PATH:
which node
which npm
```

---

### ❌ "Cannot find module 'xyz'"

**Problem**: Missing or corrupted npm packages

**Solution**:
```bash
# Inside Debian
npm cache clean --force
npm install -g openclaw@latest --allow-scripts=openclaw --force
```

---

### ❌ Gateway won't start - "Address already in use"

**Problem**: Port 3000 is already occupied

**Solution**:
```bash
# Inside Debian
# Check what's using port 3000:
lsof -i :3000

# Kill the process (replace PID with actual number):
kill -9 [PID]

# Or use a different port:
NODE_OPTIONS="--require /root/openclaw-shim.cjs" openclaw gateway --bind loopback --port 3001
```

---

### ❌ TUI shows connection refused

**Problem**: Gateway not running or wrong port

**Solution**:
1. Make sure gateway is running in another session
2. Check gateway output for errors
3. Verify port number matches:
   ```bash
   # Gateway should show: Listening on 127.0.0.1:3000
   # If different, use: openclaw tui --port [number]
   ```

---

### ❌ "EACCES: permission denied"

**Problem**: File permission issues

**Solution**:
```bash
# Inside Debian
# Fix npm permissions:
mkdir -p ~/.npm-global
npm config set prefix '~/.npm-global'

# Add to PATH:
echo 'export PATH=~/.npm-global/bin:$PATH' >> ~/.bashrc
source ~/.bashrc

# Reinstall OpenClaw:
npm install -g openclaw@latest --allow-scripts=openclaw
```

## Performance Problems

### 🐌 OpenClaw is very slow

**Causes**: CPU throttling, low RAM, background apps

**Solutions**:

1. **Enable wake lock** (prevents CPU throttling):
   ```bash
   # In Termux (not Debian)
   termux-wake-lock
   ```

2. **Increase Node.js memory**:
   ```bash
   # Inside Debian, add to ~/.bashrc:
   export NODE_OPTIONS="--max-old-space-size=2048"
   source ~/.bashrc
   ```

3. **Close other apps** to free RAM

4. **Disable battery optimization**:
   - Settings → Apps → Termux → Battery → Unrestricted

5. **Keep device plugged in** during intensive tasks

---

### 🐌 Gateway uses too much CPU

**Solution**:
```bash
# Inside Debian
# Reduce worker threads:
NODE_OPTIONS="--require /root/openclaw-shim.cjs --max-old-space-size=1024" openclaw gateway --bind loopback
```

---

### 🐌 System becomes unresponsive

**Solution**:
1. Force stop OpenClaw: `Ctrl+C` in gateway terminal
2. Restart Termux
3. Clear cache:
   ```bash
   # In Termux
   pkg clean
   
   # Inside Debian
   npm cache clean --force
   ```

## Network Issues

### 🌐 "ENOTFOUND" or DNS errors

**Problem**: Network configuration issues

**Solution**:
```bash
# Inside Debian
# Test network:
ping -c 3 8.8.8.8

# If fails, check Termux has network:
# Exit to Termux and test:
ping -c 3 8.8.8.8

# If Termux works but Debian doesn't, restart proot:
exit  # Exit Debian
proot-distro login debian
```

---

### 🌐 API requests timeout

**Problem**: Network latency or firewall

**Solution**:
1. Check internet connection
2. Try different network (WiFi vs mobile)
3. Increase timeout:
   ```bash
   # Inside Debian
   export HTTP_TIMEOUT=60000
   start-claw
   ```

---

### 🌐 "Cannot reach gateway"

**Problem**: Firewall or binding issues

**Solution**:
```bash
# Inside Debian
# Verify gateway is bound to loopback:
start-claw  # Should show 127.0.0.1:3000

# If issues persist, try:
NODE_OPTIONS="--require /root/openclaw-shim.cjs" openclaw gateway --bind 0.0.0.0
```

## Storage Issues

### 💾 "ENOSPC: no space left on device"

**Problem**: Out of storage

**Solutions**:

1. **Clean npm cache**:
   ```bash
   # Inside Debian
   npm cache clean --force
   ```

2. **Clean apt cache**:
   ```bash
   # Inside Debian
   apt clean
   apt autoremove -y
   ```

3. **Clean Termux cache**:
   ```bash
   # In Termux
   pkg clean
   ```

4. **Remove old logs**:
   ```bash
   # Inside Debian (OpenClaw writes logs to /tmp/openclaw by default)
   rm -rf /tmp/openclaw/*.log.old
   ```

5. **Check space usage**:
   ```bash
   # See what's using space
   du -sh ~/.openclaw/*
   du -sh ~/.npm/*
   ```

---

### 💾 npm install fails due to space

**Solution**:
```bash
# Inside Debian
# Use smaller cache:
npm install -g openclaw@latest --allow-scripts=openclaw --prefer-online --no-audit
```

## API Configuration

### 🔑 "Invalid API key"

**Problem**: Incorrect or expired API key

**Solution**:
```bash
# Inside Debian
openclaw onboard

# Follow prompts to reconfigure
# Test with a simple request after
```

---

### 🔑 "Rate limit exceeded"

**Problem**: API quota exhausted

**Solution**:
1. Wait for quota to reset
2. Upgrade API plan
3. Use different provider:
   ```bash
   openclaw onboard
   ```

---

### 🔑 "API endpoint not responding"

**Problem**: Provider service issues

**Solution**:
1. Check provider status page
2. Test with curl:
   ```bash
   curl -X POST https://api.openai.com/v1/chat/completions \
     -H "Authorization: Bearer YOUR_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4","messages":[{"role":"user","content":"test"}]}'
   ```
3. Try alternative provider temporarily

## Advanced Debugging

### 🔍 Enable Debug Logging

```bash
# Inside Debian
# Set debug environment:
export DEBUG=openclaw:*
start-claw

# Or for specific modules:
export DEBUG=openclaw:gateway,openclaw:api
start-claw
```

---

### 🔍 Check OpenClaw Logs

```bash
# Inside Debian
# Tail the Gateway log over RPC:
openclaw logs --follow

# Raw log files (default location):
ls -la /tmp/openclaw/
grep -i error /tmp/openclaw/*.log

# View a log file:
less /tmp/openclaw/openclaw-*.log
```

---

### 🔍 System Information

```bash
# Collect debug info:

# Android version:
getprop ro.build.version.release

# Termux version:
termux-info

# Inside Debian:
uname -a
node --version
npm --version
openclaw --version

# Memory usage:
free -h

# Disk usage:
df -h
```

---

### 🔍 Process Monitoring

```bash
# Inside Debian
# See OpenClaw processes:
ps aux | grep openclaw

# Monitor resource usage:
top

# Find memory leaks:
while true; do
  ps aux | grep openclaw | grep -v grep
  sleep 5
done
```

---

### 🔍 Network Debugging

```bash
# Inside Debian
# Test local connectivity:
curl http://127.0.0.1:3000/health

# Check listening ports:
netstat -tlnp | grep openclaw

# DNS resolution:
nslookup api.openai.com
```

## Complete Reset Procedures

### 🔄 Reset OpenClaw Only

```bash
# Inside Debian
rm -rf ~/.openclaw
npm install -g openclaw@latest --allow-scripts=openclaw --force
openclaw onboard
```

### 🔄 Reset Debian Environment

```bash
# In Termux
proot-distro remove debian
proot-distro install --name debian debian:trixie

# Then run installer again:
./install.sh
```

### 🔄 Reset Everything

```bash
# In Termux
proot-distro remove debian
pkg uninstall proot-distro -y
pkg clean

# Remove installer cache:
rm -rf ~/openclaw-* ~/.openclaw-*

# Start fresh:
./install.sh --reinstall
```

## Getting Help

If none of these solutions work:

1. **Gather information**:
   ```bash
   # Create debug report:
   echo "=== System Info ===" > debug-report.txt
   getprop ro.build.version.release >> debug-report.txt
   termux-info >> debug-report.txt
   
   # Inside Debian:
   echo "=== Versions ===" >> debug-report.txt
   node --version >> debug-report.txt
   npm --version >> debug-report.txt
   openclaw --version >> debug-report.txt
   
   echo "=== Logs ===" >> debug-report.txt
   openclaw logs --limit 100 --plain >> debug-report.txt 2>&1 || tail -100 /tmp/openclaw/openclaw-*.log >> debug-report.txt 2>/dev/null
   ```

2. **Search existing issues**:
   - https://github.com/iyeoh88-svg/openclaw-android/issues

3. **Create new issue** with:
   - Debug report
   - Steps to reproduce
   - Expected vs actual behavior
   - Screenshots if relevant

4. **Community support**:
   - GitHub Discussions
   - Discord server (if available)

---

**Last Updated**: February 2026  
**Maintainer**: OpenClaw Android Team
