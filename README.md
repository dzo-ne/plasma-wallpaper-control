# Wallpaper Control for KDE Plasma 6

A standalone wallpaper plugin and management utility for KDE Plasma 6 that provides interactive image selection, panning, zooming, precision aspect-ratio cropping, and multi-surface synchronization.

<img width="1378" height="1038" alt="Wallpaper Control Preview" src="https://github.com/user-attachments/assets/79d0687e-7a8a-4f72-88f4-1aeab24d356c" />

---

## Features

- **Interactive Cropping and Panning**: Real-time interactive crop box with 4-corner resizing handles, rule-of-thirds grid, and drag-and-pan positioning.
- **Screen & Custom Aspect Ratios**: Constrain crops to active display screen proportions (e.g. 16:9, 16:10, 21:9, 4:3, 1:1, 9:16) or freeform dimensions.
- **Seamless Dolphin Integration**: Seamlessly replaces KDE's default "Set as Wallpaper…" context menu action with the interactive crop & pan selector without cluttering your menu.
- **Desktop, Lockscreen & SDDM Support**: Apply cropped wallpapers directly to the active desktop, lockscreen, SDDM login screen, or all three simultaneously.
- **Privilege-Aware Elevation**: Uses PolicyKit (`pkexec`) to securely export and configure SDDM login screen wallpapers without running the whole app as root.
- **Color Profile Awareness**: Automatic detection and on-demand sRGB conversion for wide-gamut images (Display P3, Adobe RGB, Rec. 2020) to prevent desaturated rendering.
- **High-DPI & Multi-Monitor Support**: Resolution-independent normalized coordinate model ensures consistent wallpaper scaling across different display setups and rotations.

---

## Requirements

- **Desktop Environment**: KDE Plasma 6.0 or newer
- **Frameworks**: Qt 6, KDE Frameworks 6 (KF6)
- **Dependencies**: Python 3, PyQt6, Pillow (`python3-pillow` / `python-pillow`), Polkit (`pkexec` for SDDM support)

---

## Installation

### Automated Installation

Run the included installation script to install the wallpaper package and configure the Dolphin context menu:

```bash
./install.sh
```

### Manual Installation via `kpackagetool6`

```bash
# Install package
kpackagetool6 --type Plasma/Wallpaper --install .

# Upgrade existing package
kpackagetool6 --type Plasma/Wallpaper --upgrade .
```

---

## Usage

### 1. From Desktop Settings
1. Right-click the desktop and select **Configure Desktop and Wallpaper...**
2. In the **Wallpaper Type** dropdown, select **Wallpaper Control**.
3. Choose an image, adjust the crop box or aspect ratio, and click **Apply**.

### 2. From Dolphin File Manager
1. Right-click any image file in Dolphin.
2. Select **Set as Wallpaper…**
3. Adjust the crop selection, check your desired targets (**Desktop**, **Lockscreen**, and/or **Login Screen (SDDM)**), and click **Apply**.
4. If SDDM is selected, confirm the standard KDE authentication prompt to apply the wallpaper to the login manager.

---

## Uninstallation

To remove the wallpaper package and the Dolphin context menu:

```bash
./uninstall.sh
```

---

## Technical Documentation

For in-depth architectural specifications and implementation details:
- **[Frontend Architecture & Design Decisions](docs/FRONTEND.md)**: QtQuick/QML UI layer, coordinate geometry math, zero-flicker preview, and layout constraints.
- **[Backend Architecture & Design Decisions](docs/BACKEND.md)**: Python CLI bridge, DBus evaluation, LittleCMS color management, and session cache lifecycle.

---

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.
