#!/bin/bash
#
# xremap_installer_v3b.sh - KDE Wayland +xremap fully automatic installer

set -e

# ==============================
# 設定
# ==============================
APP_DIR="$HOME/.config/xremap"
SERVICE_DIR="$HOME/.config/systemd/user"
BIN_PATH="$HOME/.local/bin/xremap"
SERVICE_FILE="$SERVICE_DIR/xremap.service"
AUTOSTART_FILE="$HOME/.config/autostart/xremap.desktop"
XREMAP_VERSION="v0.10.12"
ARCHIVE="xremap-linux-x86_64-kde.zip"
BIN_DL_URL="https://github.com/xremap/xremap/releases/download/${XREMAP_VERSION}/${ARCHIVE}"

# ==============================
# 関数
# ==============================
function check_requirements() {
  echo "✅ Checking required tools..."
  for cmd in curl unzip sudo setcap systemctl; do
    command -v $cmd >/dev/null 2>&1 || { echo "❌ $cmd is not installed."; exit 1; }
  done
}

function install_xremap() {
  check_requirements

  echo "🔽 Downloading xremap binary..."
  mkdir -p /tmp/xremap-installer
  cd /tmp/xremap-installer
  curl -LO "$BIN_DL_URL"
  unzip -o "$ARCHIVE"
  chmod +x xremap
  mkdir -p "$HOME/.local/bin"
  mv -f xremap "$BIN_PATH"

  echo "⚙ Setting up config..."
  mkdir -p "$APP_DIR"
  cat > "$APP_DIR/config.yml" <<EOF
keypress_delay_ms: 2

modmap:
  - name: caps2ctrl
    remap:
      CapsLock: Control_L

keymap:
  - name: Emacs style keys
    application:
      only: ["Microsoft-edge", "google-chrome", "firefox", "org.kde.dolphin", "org.kde.kate", "org.kde.kwrite", "org.kde.discover", "org.kde.systemsettings"]
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

  echo "🛠 Creating user systemd service..."
  mkdir -p "$SERVICE_DIR"
  cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Xremap Daemon
After=graphical-session.target

[Service]
ExecStart=${BIN_PATH} --watch ${APP_DIR}/config.yml
Restart=always
Environment=WAYLAND_DISPLAY=wayland-0

[Install]
WantedBy=default.target
EOF

  echo "🖼 Setting up autostart entry..."
  mkdir -p "$(dirname "$AUTOSTART_FILE")"
  cat > "$AUTOSTART_FILE" <<EOF
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

  echo "🔐 Setting cap_dac_override capability on xremap..."
  sudo setcap cap_dac_override+ep "$BIN_PATH"

  echo "🚀 Enabling user service..."
  systemctl --user daemon-reexec
  systemctl --user enable xremap.service

  echo "\n✅ Installation complete!"
  echo "⚠ Please log out and back in to apply group membership."
  echo "   Then start with: systemctl --user restart xremap.service\n"
}

function uninstall_xremap() {
  echo "🧹 Stopping and disabling user service..."
  systemctl --user disable --now xremap.service || true
  rm -fv "$SERVICE_FILE"

  echo "🗑 Removing config..."
  rm -rfv "$APP_DIR"

  echo "🗑 Removing autostart entry..."
  rm -fv "$AUTOSTART_FILE"

  echo "🗑 Removing binary..."
  rm -fv "$BIN_PATH"

  echo "\n✅ Uninstallation complete!"
}

# ==============================
# main
# ==============================
case "$1" in
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

