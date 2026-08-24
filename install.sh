#!/bin/bash
# ==============================================================================
# Plasma 6 Wallpaper Plugin Installer & Tester
# Plugin ID: org.kde.plasma.cropwallpaper
# ==============================================================================

set -e

PLUGIN_ID="org.kde.plasma.cropwallpaper"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Validating KDE Plasma 6 Wallpaper Package at: $SRC_DIR"

if ! command -v kpackagetool6 &> /dev/null; then
    echo "[ERROR] kpackagetool6 not found. Please ensure KDE Plasma 6 development tools are installed."
    exit 1
fi

# Check if already installed
if kpackagetool6 --type Plasma/Wallpaper --show "$PLUGIN_ID" &> /dev/null; then
    echo "==> Existing installation found. Upgrading..."
    kpackagetool6 --type Plasma/Wallpaper --upgrade "$SRC_DIR"
else
    echo "==> Installing wallpaper package..."
    kpackagetool6 --type Plasma/Wallpaper --install "$SRC_DIR"
fi

# ------------------------------------------------------------------------------
# Install Dolphin Service Menu (Right click image -> Set as Wallpaper)
# ------------------------------------------------------------------------------
SERVICEMENU_DIR="$HOME/.local/share/kio/servicemenus"
mkdir -p "$SERVICEMENU_DIR"

INSTALLED_BIN="$HOME/.local/share/plasma/wallpapers/$PLUGIN_ID/bin/set_wallpaper.py"
if [ -f "$INSTALLED_BIN" ]; then
    SET_WALLPAPER_BIN="$INSTALLED_BIN"
else
    SET_WALLPAPER_BIN="$SRC_DIR/bin/set_wallpaper.py"
fi
chmod +x "$SET_WALLPAPER_BIN"

sed "s|@SET_WALLPAPER_BIN@|$SET_WALLPAPER_BIN|g" "$SRC_DIR/servicemenus/plasma_crop_wallpaper.desktop" > "$SERVICEMENU_DIR/plasma_crop_wallpaper.desktop"
chmod +x "$SERVICEMENU_DIR/plasma_crop_wallpaper.desktop"

if command -v kbuildsycoca6 &> /dev/null; then
    kbuildsycoca6 --noincremental 2>/dev/null || true
fi

echo ""
echo "[✓] Wallpaper plugin '$PLUGIN_ID' successfully installed/updated!"
echo "[✓] Dolphin Service Menu installed to: $SERVICEMENU_DIR/plasma_crop_wallpaper.desktop"
echo ""
echo "To test this wallpaper in a standalone window, run:"
echo "    plasmawindowed $PLUGIN_ID"
echo ""
echo "To select it on your desktop:"
echo "    Right-click Desktop -> Configure Desktop and Wallpaper... -> Wallpaper Type -> 'Crop & Pan'"
echo ""
echo "From Dolphin / File Manager:"
echo "    Right-click any image -> 'Crop & Pan as Wallpaper…'"
