# xremap-kde-wayland-installer

Simple installer script for [xremap](https://github.com/xremap/xremap) on KDE Plasma + Wayland.

## 📋 Overview

This script automates the installation of `xremap` including:
- Downloading and deploying pre-built `xremap` binary
- Setting up systemd user service
- Autostart integration for login
- Adding user to `input` group and setting required capabilities
- Providing an example `config.yml` with Emacs-like keybindings

Tested on:
- KDE neon (Plasma 6.x)
- Fedora KDE Spin
- Arch Linux + KDE Plasma

## 💻 Requirements

- KDE Plasma + Wayland session
- `curl`, `unzip`, `sudo`, `setcap`, `systemctl`

## 🚀 Installation

```bash
git clone https://github.com/YOURNAME/xremap-kde-wayland-installer.git
cd xremap-kde-wayland-installer
chmod +x xremap_installer_v3b.sh
./xremap_installer_v3b.sh install
