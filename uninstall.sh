#!/bin/bash
# ==============================================================================
# Plasma 6 Wallpaper Plugin Uninstaller
# Plugin ID: org.kde.plasma.cropwallpaper
# ==============================================================================

set -e

PLUGIN_ID="org.kde.plasma.cropwallpaper"
SERVICEMENU_FILE="$HOME/.local/share/kio/servicemenus/plasma_crop_wallpaper.desktop"
INSTALL_DIR="$HOME/.local/share/plasma/wallpapers/$PLUGIN_ID"

echo "==> Uninstalling KDE Plasma 6 Crop & Pan Wallpaper Plugin..."

# 1. Remove KPackage via kpackagetool6 if installed
if command -v kpackagetool6 &> /dev/null; then
    if kpackagetool6 --type Plasma/Wallpaper --show "$PLUGIN_ID" &> /dev/null; then
        echo "--> Removing wallpaper package via kpackagetool6..."
        kpackagetool6 --type Plasma/Wallpaper --remove "$PLUGIN_ID" || true
    fi
fi

# Fallback cleanup if directory exists
if [ -d "$INSTALL_DIR" ]; then
    echo "--> Removing residual wallpaper directory: $INSTALL_DIR..."
    rm -rf "$INSTALL_DIR"
fi

# 2. Remove Dolphin Service Menu
if [ -f "$SERVICEMENU_FILE" ]; then
    echo "--> Removing Dolphin service menu: $SERVICEMENU_FILE..."
    rm -f "$SERVICEMENU_FILE"
fi

# 3. Refresh KDE Service Cache
if command -v kbuildsycoca6 &> /dev/null; then
    echo "--> Refreshing KDE service cache..."
    kbuildsycoca6 --noincremental 2>/dev/null || true
fi

echo ""
echo "[✓] Crop & Pan Wallpaper plugin successfully uninstalled!"
