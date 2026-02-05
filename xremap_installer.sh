#!/bin/bash
#
# xremap_installer.sh - KDE Wayland + xremap installer (user systemd)
#
# Notes:
# - Fixes the "input group membership not reflected in NSS" case by creating/updating /etc/group override
#   when getent group input does not list $USER (common on systems with /usr/lib/group base + /etc/group override).
# - Requires logout/login for the new group to apply to already-running user sessions/services.

set -e

# ==============================
# Settings
# ==============================
APP_DIR="$HOME/.config/xremap"
SERVICE_DIR="$HOME/.config/systemd/user"
BIN_PATH="$HOME/.local/bin/xremap"
SERVICE_FILE="$SERVICE_DIR/xremap.service"
AUTOSTART_FILE="$HOME/.config/autostart/xremap.desktop"

XREMAP_VERSION="v0.14.11"
ARCHIVE="xremap-linux-x86_64-kde.zip"
BIN_DL_URL="https://github.com/xremap/xremap/releases/download/${XREMAP_VERSION}/${ARCHIVE}"

# ==============================
# Functions
# ==============================
check_requirements() {
  echo "✅ Checking required tools..."
  for cmd in curl unzip sudo setcap systemctl getent awk mktemp install; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "❌ $cmd is not installed."; exit 1; }
  done
}

# Ensure $USER is reflected as a member of the "input" group via NSS (getent).
# On some systems, the group is defined in /usr/lib/group and usermod may not create an /etc/group override
# entry; then getent group input shows no members, and membership does not persist after relogin.
ensure_user_in_input_group() {
  local user="$1"
  local group="input"

  local entry gid members
  entry="$(getent group "$group" || true)"
  if [[ -z "$entry" ]]; then
    echo "❌ Group '$group' was not found (getent group $group)."
    exit 1
  fi

  gid="$(echo "$entry" | cut -d: -f3)"
  members="$(echo "$entry" | cut -d: -f4)"

  # Already reflected in NSS
  if echo ",${members}," | grep -q ",${user},"; then
    return 0
  fi

  # If /etc/group is not readable, do not attempt to generate a new one (dangerous).
  if [[ ! -r /etc/group ]]; then
    echo "❌ /etc/group is not readable. Cannot safely create override for '${group}'."
    echo "   Please check permissions/FS state, then re-run."
    exit 1
  fi

  if ! grep -qE "^${group}:" /etc/group 2>/dev/null; then
    echo "⚠ /etc/group has no '${group}' entry; creating a local override (GID=${gid})..."
  else
    echo "⚠ '${user}' is not listed in '${group}' via NSS. Updating /etc/group override (GID=${gid})..."
  fi

  # Best-effort backup
  sudo cp -a /etc/group "/etc/group.bak.xremap.$(date +%F-%H%M%S)" 2>/dev/null || true

  local tmp
  tmp="$(mktemp)"

  # Update existing /etc/group entry for 'input' or append a new one with the same GID.
  awk -F: -v OFS=: -v g="$group" -v gid="$gid" -v u="$user" '
    BEGIN { seen=0 }
    $1==g {
      seen=1
      $3=gid
      if ($4=="") { $4=u }
      else {
        n=split($4,a,","); found=0
        for (i=1; i<=n; i++) if (a[i]==u) found=1
        if (!found) $4=$4 "," u
      }
    }
    { print }
    END {
      if (!seen) print g, "x", gid, u
    }
  ' /etc/group > "$tmp"

  sudo install -m 0644 -o root -g root "$tmp" /etc/group
  rm -f "$tmp"

  # Re-check (this ensures it persists for *new* logins; already-running sessions still need relogin)
  members="$(getent group "$group" | cut -d: -f4)"
  if ! echo ",${members}," | grep -q ",${user},"; then
    echo "⚠ Still not reflected: getent group ${group} => $(getent group "${group}" || true)"
    echo "⚠ Please check /etc/group and /etc/nsswitch.conf (group: ... merge)."
  fi
}

install_xremap() {
  check_requirements

  echo "🔽 Downloading xremap binary..."
  tmpdir="$(mktemp -d)"
  (
    cd "$tmpdir"
    curl -L -o "$ARCHIVE" "$BIN_DL_URL"
    unzip -o "$ARCHIVE"
    chmod +x xremap
    mkdir -p "$(dirname "$BIN_PATH")"
    mv -f xremap "$BIN_PATH"
  )
  rm -rf "$tmpdir"

  echo "⚙ Setting up config..."
  mkdir -p "$APP_DIR"
  # If you already have config.yml, keep it. Create a minimal one if missing.
  if [[ ! -f "$APP_DIR/config.yml" ]]; then
    cat > "$APP_DIR/config.yml" <<'EOF'
keypress_delay_ms: 2

modmap:
  - name: caps2ctrl
    remap:
      CapsLock: Control_L

keymap:
  - name: Emacs style keys
    application:
      only: ["microsoft-edge", "google-chrome", "firefox", "brave-browser", "org.kde.dolphin", "org.kde.kate", "org.kde.kwrite", "org.kde.discover", "org.kde.systemsettings"]
    remap:
      C-a: home
      C-e: end
      C-k: [Shift-End, C-x]
      C-y: C-v
      C-u: [Shift-Home, C-x]
      C-b: left
      C-f: right
      C-n: down
      C-p: up
      C-h: backspace
      C-d: delete
      C-Shift-n: C-n
      C-Shift-p: C-p
      C-Shift-f: C-f
      C-Shift-a: C-a
EOF
  fi

  echo "🛠 Creating user systemd service..."
  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xremap Daemon
After=graphical-session.target

[Service]
ExecStart=${BIN_PATH} --watch ${APP_DIR}/config.yml
Restart=always

[Install]
WantedBy=default.target
EOF

  echo "🖼 Setting up autostart entry..."
  mkdir -p "$(dirname "$AUTOSTART_FILE")"
  cat > "$AUTOSTART_FILE" <<'EOF'
[Desktop Entry]
Type=Application
Exec=systemctl --user restart xremap.service
Hidden=false
X-GNOME-Autostart-enabled=true
Name=xremap autostart
Comment=Start xremap via systemd user service at login
EOF

  echo "👥 Adding user to input group (may require relogin)..."
  sudo usermod -aG input "$USER"
  ensure_user_in_input_group "$USER"

  echo "🔐 Setting cap_dac_override capability on xremap..."
  sudo setcap cap_dac_override+ep "$BIN_PATH"

  echo "🚀 Enabling user service..."
  systemctl --user daemon-reexec
  systemctl --user enable xremap.service

  echo "✅ Installation complete!"
  echo "⚠ Please log out and back in to apply group membership."
  echo "   Then start with: systemctl --user restart xremap.service"
}

uninstall_xremap() {
  echo "🧹 Stopping and disabling user service..."
  systemctl --user disable --now xremap.service || true
  rm -fv "$SERVICE_FILE"

  echo "🗑 Removing config..."
  rm -rfv "$APP_DIR"

  echo "🗑 Removing autostart entry..."
  rm -fv "$AUTOSTART_FILE"

  echo "🗑 Removing binary..."
  rm -fv "$BIN_PATH"

  echo "✅ Uninstallation complete!"
}

# ==============================
# Main
# ==============================
case "${1:-}" in
  install)
    install_xremap
    ;;
  uninstall)
    uninstall_xremap
    ;;
  *)
    echo "Usage: $0 {install|uninstall}"
    exit 1
    ;;
esac

