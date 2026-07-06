export TERM=xterm-256color
export LANG=C.UTF-8
export PATH="/homeassistant/.claudecode/npm-global/bin:/root/.local/bin:$PATH"
PS1='\[\033[1;36m\]claude-code\[\033[0m\]:\[\033[1;34m\]\w\[\033[0m\]\$ '

# Wrapper: intercept `claude update` (built-in updater fails on read-only image layer)
claude() {
    if [ "$1" = "update" ]; then
        echo "Updating Claude Code via add-on method (npm --prefix)..."
        npm install -g @anthropic-ai/claude-code@latest \
            --prefix /homeassistant/.claudecode/npm-global \
            --no-fund --no-audit 2>&1
        hash -r 2>/dev/null
        echo "Done: $(command claude --version 2>/dev/null)"
        return 0
    fi
    command claude "$@"
}

# Aliases
alias ll='ls -la'
alias c='claude'
alias cc='claude --continue'
alias ha-config='cd /homeassistant'
alias ha-logs='cat /homeassistant/home-assistant.log 2>/dev/null || echo "Log not found"'
alias claude-update='claude update'

source /root/.claude-notify.sh
