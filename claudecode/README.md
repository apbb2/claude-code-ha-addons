# Claude Code for Home Assistant

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code), Anthropic's AI-powered coding assistant, directly in your Home Assistant sidebar with full access to your configuration.

## Quick Start

```bash
claude "List all my automations"
claude "Turn off all lights in the living room"
claude "Create an automation to turn on lights at sunset"
claude "Why isn't my motion sensor automation working?"
```

## Requirements

- Home Assistant OS or Supervised installation
- [Anthropic account](https://console.anthropic.com/) (authentication handled in terminal)

## Features

- **Web Terminal**: Access Claude Code through a browser-based terminal
- **Config Access**: Read and write Home Assistant configuration files
- **hass-mcp Integration**: Direct control of HA entities and services
- **Session Persistence**: Optional tmux integration to preserve sessions across page refreshes
- **Customizable Theme**: Choose between dark and light terminal themes
- **Multi-Architecture**: Supports amd64, aarch64, armv7, armhf, and i386
- **Secure Authentication**: Claude Code handles its own authentication securely

## Setup

### 1. Install the Add-on

1. Add the repository to Home Assistant
2. Install the "Claude Code" add-on
3. Start the add-on
4. Open the Web UI from the sidebar

### 2. Authenticate with Claude Code

On first launch, Claude Code will prompt you to authenticate:

1. Open the terminal from the HA sidebar
2. Type `claude` to start
3. Follow the authentication prompts
4. Your credentials are stored securely by Claude Code

**Note**: The add-on does NOT require you to enter API keys in the configuration. Claude Code handles authentication itself, storing credentials securely in its own configuration directory. This is more secure than storing keys in Home Assistant's add-on config.

## Using Claude Code

### Basic Usage

Once authenticated, Claude Code is ready to help with:

- Editing Home Assistant YAML configurations
- Creating automations and scripts
- Debugging configuration issues
- Writing custom integrations

### Home Assistant Integration

With hass-mcp enabled, Claude can:

- Query entity states: "What's the temperature in the living room?"
- Control devices: "Turn off all lights in the bedroom"
- List services: "What services are available for climate control?"
- Debug automations: "Why didn't my morning routine trigger?"

### Example Commands

```bash
# Start interactive session
claude

# One-off commands
claude "Add a new automation that turns on the porch light at sunset"
claude "Check my configuration.yaml for errors"
claude "List all unavailable entities"

# Continue previous conversation
claude --continue
```

### Keyboard Shortcuts

| Shortcut | Command |
|----------|---------|
| `c` | `claude` |
| `cc` | `claude --continue` |
| `ha-config` | Navigate to config directory |
| `ha-logs` | View Home Assistant logs |

## Configuration Options

| Option | Description | Default |
|--------|-------------|---------|
| `enable_mcp` | Enable HA integration | true |
| `terminal_font_size` | Font size (10-24) | 14 |
| `terminal_theme` | dark or light | dark |
| `working_directory` | Start directory | /homeassistant |
| `session_persistence` | Use tmux for persistent sessions | true |
| `auto_update_claude` | Auto-update Claude Code on startup | true |
| `model` | Claude model to use | claude-sonnet-4-6 |

### Model Selection

Three models are available:

| Model | Best for |
|-------|----------|
| `claude-sonnet-4-6` | Best balance of speed and capability (default) |
| `claude-opus-4-7` | Most powerful, for complex tasks |
| `claude-haiku-4-5-20251001` | Fastest, for simple queries |

Enable `auto_update_claude` to ensure new models become available as Anthropic releases them, without needing an add-on update.

## Update Notifications

When `auto_update_claude` is enabled, the add-on checks for newer versions of Claude Code in the background every hour. If an update is available:

- A **persistent notification** appears in the HA UI notification bell with the title "Claude Code Update Available"
- A **yellow banner** is shown in the terminal each time you open a session

Both clear automatically after restarting the add-on, which installs the latest version on startup.

## File Locations

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration directory | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media folder | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Session Persistence

When `session_persistence` is enabled, the add-on uses tmux to maintain your terminal session. This means:

- Your session survives browser refreshes
- You can disconnect and reconnect without losing context
- Claude Code conversations are preserved

### tmux Commands

If you're new to tmux:

| Key | Action |
|-----|--------|
| `Ctrl+b d` | Detach from session (keeps it running) |
| `Ctrl+b [` | Enter scroll/copy mode (use arrow keys, `q` to exit) |

### Copy and Paste

tmux mouse mode is disabled, so the browser handles selection natively:

| Action | How to do it |
|--------|--------------|
| **Copy** | Select text with the mouse, then `Ctrl+C` / `Cmd+C` |
| **Paste** | `Ctrl+V` / `Cmd+V` or `Shift+Insert` |
| **Scroll** | Mouse wheel or touch (works on tablets) |

#### Authenticating Claude Code (first launch)

1. **Click the authentication link** — it should open in a new tab (on narrow windows the URL may wrap; if clicking doesn't work, select and copy it into your browser)
2. Complete authentication in the browser and **copy the auth code**
3. Click back on the terminal and **paste** the code

### Session Persistence Trade-offs

**With tmux (`session_persistence: true`, default):**
- ✅ Session survives browser refresh/disconnect
- ✅ Can detach and reattach to running sessions
- ✅ Long-running Claude tasks continue in background
- ✅ Native browser scrolling, copy, and paste

**Without tmux (`session_persistence: false`):**
- ✅ Simpler terminal behavior
- ❌ Session lost on browser refresh

## Security

### Authentication
- **No API keys in add-on config**: Claude Code handles authentication itself
- Credentials are stored securely in Claude Code's own directory (`~/.claude/`)
- This is more secure than storing keys in Home Assistant's configuration

### Container Security
- The Supervisor token is automatically managed and not exposed
- File access is limited to mapped directories
- The add-on runs in an isolated container

## Troubleshooting

### "Illegal instruction" crash / add-on won't start (Proxmox users)

Claude Code uses [Bun](https://bun.sh/) as its runtime, which requires SSE4.2 CPU instructions (Intel Nehalem 2009+ / AMD Bulldozer 2011+).

**Proxmox VMs:** The default CPU type `kvm64` is a minimal baseline that strips out these instructions even if your host CPU supports them. Fix:

1. Shut down the HA VM
2. Go to **Hardware → Processors → Type**
3. Change from `kvm64` to **`host`** (passes through all real CPU capabilities)
4. Start the VM

Other CPU types that include SSE4.2 also work (e.g. `Haswell`, `Skylake-Client`). The add-on startup log will show a clear warning if the CPU is incompatible.

### Authentication issues

Claude Code manages its own authentication. If you have issues:
1. Type `claude` to start the authentication flow
2. Follow the prompts to log in or enter your API key
3. Credentials are saved automatically for future sessions

**Can't copy the URL or paste the auth code?** See [Copy and Paste](#copy-and-paste) — selection and paste work natively in the browser.

### hass-mcp not working

1. Verify `enable_mcp` is true in configuration
2. Check add-on logs for connection errors
3. Restart the add-on after configuration changes

### Terminal not loading

1. Check that the add-on is running (green indicator)
2. Try refreshing the page
3. Check browser console for errors
4. Review add-on logs for ttyd errors

### Session not persisting

1. Ensure `session_persistence` is set to true
2. The session is named "claude" - it will auto-attach on reconnect

### Configuration changes not applying

After changing configuration:
1. Save the configuration
2. Restart the add-on completely

## Support

- [GitHub Issues](https://github.com/apbb2/robsonfelix-hass-addons/issues)
- [Home Assistant Community](https://community.home-assistant.io/)
