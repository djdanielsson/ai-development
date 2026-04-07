#!/usr/bin/env zsh
export ZSH="$HOME/.oh-my-zsh"

# oh-my-zsh configuration
plugins=(git)

ZSH_THEME="agnoster"
source $ZSH/oh-my-zsh.sh

# History options should be set in .zshrc and after oh-my-zsh sourcing.
# See https://github.com/nix-community/home-manager/issues/177.
HISTSIZE="10000"
SAVEHIST="10000"

HISTFILE="$HOME/.zsh_history"
mkdir -p "$(dirname "$HISTFILE")"

setopt HIST_FCNTL_LOCK
unsetopt APPEND_HISTORY
setopt HIST_IGNORE_DUPS
unsetopt HIST_IGNORE_ALL_DUPS
unsetopt HIST_SAVE_NO_DUPS
unsetopt HIST_FIND_NO_DUPS
setopt HIST_IGNORE_SPACE
unsetopt HIST_EXPIRE_DUPS_FIRST
setopt SHARE_HISTORY
unsetopt EXTENDED_HISTORY
setopt autocd

export EDITOR=vim
export PATH="$HOME/.devcontainers/bin:$PATH"
export PATH="$HOME/bin:$HOME/.local/bin:$PATH"
export GPG_TTY=$(tty)
__gitca() {
  git add .
  git commit -am "$(git status | grep -e 'modified:\|deleted:\|added:\|renamed:\|new file:')"
  git push origin $(git status | grep -i "on branch" | awk '{ print $3}')
}

# ==============================================================================
# AI Box Launcher - Biometric Sandbox
# ==============================================================================
aibox() {
  echo "👆 Requesting Vaultwarden Touch ID..."

  local -x BW_SESSION=$(bwbio unlock --raw)

  if [ -z "$BW_SESSION" ] || [[ "$BW_SESSION" == *"error"* ]]; then
    echo "❌ Touch ID canceled or failed."
    return 1
  fi

  echo "🔑 Vault unlocked! Fetching zero-footprint secrets..."

#  local -x ANTHROPIC_API_KEY=$(bw get password "Anthropic API")|| { echo "❌ Failed to fetch Anthropic API key."; return 1; }
  local -x CURSOR_API_KEY=$(bw get password "Cursor API") || { echo "❌ Failed to fetch Cursor API key."; return 1; }
  local -x AI_GITHUB_TOKEN=$(bw get password "AI GitHub PAT")|| { echo "❌ Failed to fetch GitHub PAT."; return 1; }

  local GITHUB_PAT_JSON
  GITHUB_PAT_JSON=$(bw get item "AI GitHub PAT") || { echo "❌ Failed to fetch GitHub PAT item."; return 1; }
  local -x AI_GIT_NAME=$(echo "$GITHUB_PAT_JSON" | jq -r '.fields[] | select(.name == "Git Name").value')
  local -x AI_GIT_EMAIL=$(echo "$GITHUB_PAT_JSON" | jq -r '.fields[] | select(.name == "Git Email").value')
  unset GITHUB_PAT_JSON

  local -x AI_SSH_KEY_B64=$(bw get notes "AI SSH Key" | base64 -b 0) || { echo "❌ Failed to fetch SSH key."; return 1; }
  local -x AI_GPG_KEY_B64=$(bw get notes "AI GPG Key" | base64 -b 0) || { echo "❌ Failed to fetch GPG key."; return 1; }

  local CONFIG_PATH="$HOME/.config/devcontainers/fedora-sandbox/devcontainer.json"
  echo "🚀 Starting AI Sandbox for: $(pwd)"

  local rc=0
  if devcontainer up --workspace-folder . --config "$CONFIG_PATH" --docker-path podman; then
      echo "💻 Attaching to sandbox terminal..."
      devcontainer exec --workspace-folder . --config "$CONFIG_PATH" --docker-path podman zsh
  else
      echo "❌ Failed to start the AI Sandbox."
      rc=1
  fi

  # Always scrub secrets from the host shell, regardless of success or failure.
  unset BW_SESSION ANTHROPIC_API_KEY CURSOR_API_KEY AI_GITHUB_TOKEN
  unset AI_GIT_NAME AI_GIT_EMAIL AI_SSH_KEY_B64 AI_GPG_KEY_B64
  return $rc
}

# ==============================================================================
# AI Box Reverse Tunnel - Dynamically open ports to Mac Host
# ==============================================================================

tunnel() {
    echo -n "🔌 Enter the port number to expose (e.g. 8080): "
    read PORT

    # Validate input is a number
    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Port must be a number."
        return 1
    fi

    # Strict duplicate check using ${PORT} to prevent Bash boundary errors
    if ps aux | grep -q "[s]sh -R ${PORT}:localhost:${PORT}"; then
        echo "✅ Tunnel for port $PORT is already active!"
        return 0
    fi

    echo "🚀 Initiating reverse tunnel for port $PORT..."

    # Use strict ${} wrapping and quotes to guarantee the colon survives
    ssh -R "${PORT}:localhost:${PORT}" "$AIBOX_HOST_USER@host.containers.internal"

    if [ $? -eq 0 ]; then
        echo "✨ Success! Port $PORT is now mapped."
        echo "   Access it on your Mac at: http://localhost:$PORT"
        echo "   To stop this tunnel later, run: pkill -f 'ssh.*-R ${PORT}'"
    else
        echo "❌ Failed to create tunnel."
    fi
}

# ==============================================================================
# AI Box Reverse Tunnel - Dynamically open ports to Mac Host
# ==============================================================================

tunnel() {
    local MAC_USER="${AIBOX_HOST_USER:?AIBOX_HOST_USER is not set — launch via aibox to inject it}"

    echo -n "🔌 Enter the port number to expose (e.g. 8080): "
    read PORT

    if ! [[ "$PORT" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Port must be a number."
        return 1
    fi

    if ss -tln | grep -q ":$PORT "; then
        echo "⚠️  Warning: Port $PORT is currently in use by an app inside this container."
        echo "   The tunnel will work, but make sure your app is running before testing."
    fi

    if ps aux | grep "[s]sh -R $PORT:localhost:$PORT" > /dev/null; then
        echo "✅ Tunnel for port $PORT is already active!"
        return 0
    fi

    echo "🚀 Initiating reverse tunnel for port $PORT as $MAC_USER..."
    echo "   (You may be prompted for your Mac login password)"

    ssh -f -N -R "$PORT:localhost:$PORT" "$MAC_USER@host.containers.internal"

    if [ $? -eq 0 ]; then
        echo "✨ Success! Port $PORT is now mapped."
        echo "   Access it on your Mac at: http://localhost:$PORT"
        echo "   To stop the tunnel later, run: pkill -f 'ssh -R $PORT'"
    else
        echo "❌ Failed to create tunnel. Ensure 'Remote Login' (SSH) is enabled on your Mac."
    fi
}

alias -- gitca=__gitca
alias -- gitcm='git add . ;git gen-commit'
alias -- ll='eza -l'
alias -- ls=eza
alias -- lt='eza -a --tree --level=1'
alias -- devc-update='curl --proto "=https" --tlsv1.2 -fsSL https://raw.githubusercontent.com/devcontainers/cli/main/scripts/install.sh | sh -s -- --update'
ZSH_HIGHLIGHT_HIGHLIGHTERS+=()
