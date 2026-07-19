#!/bin/bash
set -e

export HA_TOKEN="$SUPERVISOR_TOKEN"
export HA_URL="http://supervisor/core"
# NOTE: do NOT install an xdg-open/$BROWSER shim. When Claude Code believes a
# browser opened locally it switches to a localhost-callback OAuth flow that can
# never complete from the user's real browser. With no opener present, it
# correctly uses the manual paste-a-code flow. Login URLs are captured
# passively by the tmux watcher below instead.
PERSIST_DIR=/homeassistant/.claudecode
NPM_GLOBAL_DIR="$PERSIST_DIR/npm-global"
# Prepend writable npm prefix to PATH so any installed update takes priority over the image binary
export PATH="$NPM_GLOBAL_DIR/bin:$PATH"

mkdir -p "$PERSIST_DIR/config" "$NPM_GLOBAL_DIR" /root/.config

# Write CLAUDE.md for Claude's context — only if missing, so user edits via /memory survive restarts
if [ ! -f "$PERSIST_DIR/CLAUDE.md" ]; then
cat > "$PERSIST_DIR/CLAUDE.md" << 'CLAUDEMD'
# Claude Code - Home Assistant Add-on

## Path Mapping

In this add-on container, paths are mapped differently than HA Core:
- `/homeassistant` = HA config directory (equivalent to `/config` in HA Core)
- `/config` does NOT exist - always use `/homeassistant`

When users mention `/config/...`, translate to `/homeassistant/...`

## Available Paths

| Path | Description | Access |
|------|-------------|--------|
| `/homeassistant` | HA configuration | read-write |
| `/share` | Shared folder | read-write |
| `/media` | Media files | read-write |
| `/ssl` | SSL certificates | read-only |
| `/backup` | Backups | read-only |

## Home Assistant Integration

Use the `homeassistant` MCP server to query entities and call services.

## Reading Home Assistant Logs

**Log levels (from most to least verbose):**
- `debug` - Only shown if explicitly enabled in configuration.yaml
- `info` - General information, shown by default
- `warning` - Warnings, always shown
- `error` - Errors, always shown

**Commands to read logs:**
```bash
# View recent logs (ha CLI)
ha core logs 2>&1 | tail -100

# Filter by keyword
ha core logs 2>&1 | grep -i keyword

# Filter errors only
ha core logs 2>&1 | grep -iE "(error|exception)"

# Alternative: read log file directly
tail -100 /homeassistant/home-assistant.log
```

**To enable debug logging for an integration**, add to `configuration.yaml`:
```yaml
logger:
  default: info
  logs:
    custom_components.YOUR_INTEGRATION: debug
```

**Key insight:** `_LOGGER.debug()` calls are invisible unless the logger level is set to debug. Use `_LOGGER.info()` or `_LOGGER.warning()` for logs that should always appear.
CLAUDEMD
fi

# Persistence symlinks — keep Claude auth and config across container rebuilds
[ ! -L /root/.claude ] && { rm -rf /root/.claude; ln -s "$PERSIST_DIR" /root/.claude; }
[ ! -L /root/.config/claude-code ] && { rm -rf /root/.config/claude-code; ln -s "$PERSIST_DIR/config" /root/.config/claude-code; }
[ ! -L /root/.claude.json ] && { touch "$PERSIST_DIR/.claude.json"; rm -f /root/.claude.json; ln -s "$PERSIST_DIR/.claude.json" /root/.claude.json; }

# Persist ~/.local/bin and ~/.local/share/claude across container rebuilds.
# claude update stores symlinks in local-bin and actual version binaries in local-share-claude.
# Without persisting both, the symlink survives but points to a missing binary after rebuild.
mkdir -p "$PERSIST_DIR/local-bin"
[ ! -L /root/.local/bin ] && { rm -rf /root/.local/bin; ln -s "$PERSIST_DIR/local-bin" /root/.local/bin; }
# Remove stale claude from local-bin — AppArmor blocks exec from /root/.local/bin/
rm -f "$PERSIST_DIR/local-bin/claude" 2>/dev/null || true

# Remove native claude installation — causes "multiple installations" conflict with npm-global.
# No longer persisted; npm-global is the sole update path.
rm -rf /root/.local/share/claude 2>/dev/null || true
rm -rf "$PERSIST_DIR/local-share-claude" 2>/dev/null || true

# CPU compatibility check — Claude Code's Bun binary uses JavaScriptCore, which
# requires AVX (not just SSE4.2). Without it claude HANGS rather than crashing,
# which is why every claude call below is wrapped in timeout.
# Only applies to x86; ARM cpuinfo has neither flag and would false-positive.
CPU_ARCH=$(uname -m)
if { [ "$CPU_ARCH" = "x86_64" ] || [ "$CPU_ARCH" = "i686" ] || [ "$CPU_ARCH" = "i386" ]; } \
    && ! grep -qw avx /proc/cpuinfo 2>/dev/null; then
    echo "[WARN] ============================================================"
    echo "[WARN] CPU INCOMPATIBILITY DETECTED"
    echo "[WARN] This CPU does not expose AVX instructions, required by"
    echo "[WARN] Claude Code's runtime. Claude Code will hang or crash."
    echo "[WARN] Minimum hardware: Intel Sandy Bridge (2011) / AMD Bulldozer (2011)."
    echo "[WARN] Running on Proxmox? Change VM CPU type from 'kvm64' to 'host'"
    echo "[WARN] in the VM hardware settings to expose real CPU capabilities."
    echo "[WARN] The terminal will still start so you can see this message."
    echo "[WARN] ============================================================"
fi

# Report active version (npm-global/bin is first in PATH, so updated version is used automatically)
if [ -f "$NPM_GLOBAL_DIR/bin/claude" ]; then
    echo "[INFO] Using npm-updated Claude Code: $(timeout 30 claude --version 2>/dev/null)"
fi

# Read options from HA config
FONT_SIZE=$(jq -r '.terminal_font_size // 14' /data/options.json)
THEME=$(jq -r --arg d dark '.terminal_theme // $d' /data/options.json)
SESSION_PERSIST=$(jq -r '.session_persistence // true' /data/options.json)
ENABLE_MCP=$(jq -r '.enable_mcp // true' /data/options.json)
ENABLE_PLAYWRIGHT=$(jq -r '.enable_playwright_mcp // false' /data/options.json)
PLAYWRIGHT_HOST=$(jq -r --arg d '' '.playwright_cdp_host // $d' /data/options.json)

# Auto-detect Playwright Browser hostname if not explicitly set
if [ -z "$PLAYWRIGHT_HOST" ] && [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    echo '[INFO] Auto-detecting Playwright Browser hostname...'
    PLAYWRIGHT_HOST=$(curl -s -H "Authorization: Bearer $SUPERVISOR_TOKEN" http://supervisor/addons \
        | jq -r --arg s1 playwright-browser --arg s2 _playwright-browser \
          '.data.addons[] | select(.slug | (endswith($s1) or endswith($s2))) | .hostname' | head -1)
    if [ -n "$PLAYWRIGHT_HOST" ] && [ "$PLAYWRIGHT_HOST" != "null" ]; then
        echo "[INFO] Found Playwright Browser: $PLAYWRIGHT_HOST"
    else
        echo '[WARN] Playwright Browser add-on not found, using default hostname'
        PLAYWRIGHT_HOST="playwright-browser"
    fi
fi

# Auto-update Claude Code on startup if enabled
AUTO_UPDATE=$(jq -r '.auto_update_claude // true' /data/options.json)
if [ "$AUTO_UPDATE" = "true" ]; then
    CURRENT_VER=$(timeout 30 claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LATEST_VER=$(timeout 30 npm show @anthropic-ai/claude-code version 2>/dev/null) || LATEST_VER=""
    if [ -n "$LATEST_VER" ] && [ -n "$CURRENT_VER" ] && [ "$CURRENT_VER" != "$LATEST_VER" ]; then
        echo "[INFO] Updating Claude Code from $CURRENT_VER to $LATEST_VER..."
        # Install into the writable persisted prefix — avoids read-only Docker layer restriction
        # that blocks `claude update` (which tries to update the npm global in /usr/local)
        timeout 300 npm install -g "@anthropic-ai/claude-code@$LATEST_VER" \
            --prefix "$NPM_GLOBAL_DIR" --no-fund --no-audit 2>&1 || true
        hash -r 2>/dev/null || true
        # Smoke test: a release that hangs or crashes on this hardware must not stick.
        # Rolling back = removing the npm-global install so PATH falls through to the bundled binary.
        if ! timeout 30 claude --version </dev/null >/dev/null 2>&1; then
            echo "[WARN] Claude Code $LATEST_VER fails to run on this system — rolling back to bundled version"
            rm -rf "$NPM_GLOBAL_DIR"
            mkdir -p "$NPM_GLOBAL_DIR"
            hash -r 2>/dev/null || true
        fi
        echo "[INFO] Claude Code update complete: $(timeout 30 claude --version 2>/dev/null)"
    else
        echo "[INFO] Claude Code $CURRENT_VER is up to date"
    fi
fi

# Set Claude model
MODEL=$(jq -r --arg d claude-sonnet-4-6 '.model // $d' /data/options.json)
export ANTHROPIC_MODEL="$MODEL"
echo "[INFO] Using Claude model: $MODEL"

# Configure MCP servers (timeout: on AVX-less CPUs claude hangs — must not block ttyd startup)
timeout 30 claude mcp remove homeassistant -s user 2>/dev/null || true
timeout 30 claude mcp remove playwright -s user 2>/dev/null || true

# Ensure settings.json exists so jq merges below work on fresh installs
SETTINGS_FILE=/root/.claude/settings.json
[ -s "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"

# Scrub Supervisor token persisted by older add-on versions (kept secrets out of HA backups).
# hass-mcp reads HA_TOKEN from the environment (exported above); nothing reads this key.
if jq -e '.mcpServers.homeassistant.env.HASS_TOKEN?' "$SETTINGS_FILE" >/dev/null 2>&1; then
    jq 'del(.mcpServers.homeassistant.env.HASS_TOKEN)' "$SETTINGS_FILE" > /tmp/settings.tmp \
        && mv /tmp/settings.tmp "$SETTINGS_FILE"
    echo '[INFO] Removed legacy token from persisted settings'
fi

# Remove obsolete Glob()/Grep() permission rules written by older versions —
# Claude Code warns about them at startup; Read(path) rules cover those tools.
jq '.permissions.allow = ((.permissions.allow // []) - [
        "Glob(/homeassistant/**)", "Glob(/config/**)",
        "Grep(/homeassistant/**)", "Grep(/config/**)"
    ])' "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"

if [ "$ENABLE_MCP" = "true" ]; then
    timeout 30 claude mcp add-json homeassistant '{"command":"hass-mcp"}' -s user || true
    ALLOWED_TOOLS='[
      "mcp__homeassistant__get_version",
      "mcp__homeassistant__get_entity",
      "mcp__homeassistant__list_entities",
      "mcp__homeassistant__search_entities_tool",
      "mcp__homeassistant__domain_summary_tool",
      "mcp__homeassistant__list_automations",
      "mcp__homeassistant__get_history",
      "mcp__homeassistant__get_error_log",
      "Read(/homeassistant/**)",
      "Read(/config/**)",
      "Read(/share/**)",
      "Read(/media/**)"
    ]'
    jq --argjson tools "$ALLOWED_TOOLS" \
        '.permissions.allow = ($tools + (.permissions.allow // []) | unique)' \
        "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"
    echo '[INFO] MCP configured with Home Assistant integration'
    echo '[INFO] Pre-authorized read-only MCP tools'
else
    echo '[INFO] MCP disabled'
fi

if [ "$ENABLE_PLAYWRIGHT" = "true" ]; then
    PW_CONFIG=$(jq -cn --arg url "http://${PLAYWRIGHT_HOST}:9222" \
        '{command:"npx",args:["--no-install","@playwright/mcp","--cdp-endpoint",$url]}')
    timeout 30 claude mcp add-json playwright "$PW_CONFIG" -s user || true
    echo "[INFO] Playwright MCP enabled (CDP: http://${PLAYWRIGHT_HOST}:9222)"
    echo '[INFO] Make sure the Playwright Browser add-on is installed and running'
else
    echo '[INFO] Playwright MCP disabled'
fi

# Remote Control — lets claude.ai/code and the Claude mobile app view and steer sessions.
# Off by default: this add-on runs as root with full host access, so anyone signed in to
# the linked Claude account could control it.
REMOTE_CONTROL=$(jq -r '.enable_remote_control // false' /data/options.json)
RC_SESSION_PREFIX=$(jq -r --arg d HomeAssistant '.remote_control_session_prefix // $d' /data/options.json)
if [ "$REMOTE_CONTROL" = "true" ]; then
    jq '.remoteControlAtStartup = true' "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"
    export CLAUDE_REMOTE_CONTROL_SESSION_NAME_PREFIX="$RC_SESSION_PREFIX"
    echo '[INFO] Remote Control enabled — sessions can be steered from claude.ai'
else
    jq 'del(.remoteControlAtStartup)' "$SETTINGS_FILE" > /tmp/settings.tmp && mv /tmp/settings.tmp "$SETTINGS_FILE"
fi

# Set terminal colors based on theme
if [ "$THEME" = "dark" ]; then
    COLORS='background=#1e1e2e,foreground=#cdd6f4,cursor=#f5e0dc'
else
    COLORS='background=#eff1f5,foreground=#4c4f69,cursor=#dc8a78'
fi

# Set shell command based on session persistence setting
if [ "$SESSION_PERSIST" = "true" ]; then
    SHELL_CMD='tmux new-session -A -s claude'
else
    SHELL_CMD='bash --login'
fi

# Clear any stale open-URL notification from a previous session
printf '{"notification_id":"claude_code_open_url"}' \
    | curl -sf -X POST \
      -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
      -H "Content-Type: application/json" \
      -d @- http://supervisor/core/api/services/persistent_notification/dismiss >/dev/null 2>&1 || true

# Background login-URL watcher — reads the tmux pane with wrapped lines joined
# (capture-pane -J) and posts any Claude OAuth URL as a clickable HA notification.
# Purely passive: Claude Code's login flow is not touched.
if [ "$SESSION_PERSIST" = "true" ]; then
(LAST_URL=""
while true; do
    if tmux has-session -t claude 2>/dev/null; then
        URL=$(tmux capture-pane -t claude -p -J -S -80 2>/dev/null \
              | grep -oE 'https://claude\.(ai|com)/[^[:space:]]*oauth[^[:space:]]*' | tail -1)
        if [ -n "$URL" ] && [ "$URL" != "$LAST_URL" ]; then
            LAST_URL="$URL"
            printf '%s\n' "$URL" > /tmp/claude-last-url
            jq -cn --arg url "$URL" '{
                title: "Claude Code — login link",
                message: ("[**Click here to open the login page**](" + $url + ")\n\nAfter approving, copy the code and paste it back into the terminal."),
                notification_id: "claude_code_open_url"
            }' | curl -sf -X POST \
                -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
                -H "Content-Type: application/json" \
                -d @- http://supervisor/core/api/services/persistent_notification/create >/dev/null 2>&1 || true
        fi
    fi
    sleep 3
done) &
fi

# Background update checker — runs hourly, posts HA notification when update is available
(while true; do
    IV=$(timeout 30 claude --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    LV=$(npm show @anthropic-ai/claude-code version 2>/dev/null)
    if [ -n "$LV" ] && [ -n "$IV" ] && [ "$IV" != "$LV" ]; then
        echo "$LV" > "$PERSIST_DIR/.update_notice"
        echo "[INFO] Claude Code update available: $LV (installed: $IV)"
        printf '{"title":"Claude Code Update Available","message":"Version %s is available (installed: %s). Restart the add-on to update.","notification_id":"claude_code_update"}' "$LV" "$IV" \
            | curl -sf -X POST \
              -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
              -H "Content-Type: application/json" \
              -d @- http://supervisor/core/api/services/persistent_notification/create 2>/dev/null || true
    else
        rm -f "$PERSIST_DIR/.update_notice" 2>/dev/null
        printf '{"notification_id":"claude_code_update"}' \
            | curl -sf -X POST \
              -H "Authorization: Bearer $SUPERVISOR_TOKEN" \
              -H "Content-Type: application/json" \
              -d @- http://supervisor/core/api/services/persistent_notification/dismiss 2>/dev/null || true
    fi
    sleep 3600
done) &

# Start web terminal in the configured working directory
WORKDIR=$(jq -r --arg d /homeassistant '.working_directory // $d' /data/options.json)
[ -d "$WORKDIR" ] || { echo "[WARN] working_directory '$WORKDIR' not found, using /homeassistant"; WORKDIR=/homeassistant; }
cd "$WORKDIR"
exec ttyd --port 7681 --writable --ping-interval 30 --max-clients 5 \
    -t fontSize="$FONT_SIZE" \
    -t fontFamily=Monaco,Consolas,monospace \
    -t scrollback=20000 \
    -t "theme=$COLORS" \
    $SHELL_CMD
