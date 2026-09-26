# Backend Architecture & Design Decisions

This document details the Python CLI backend, KDE Plasma DBus inter-process communication, ICC color management, cache lifecycle, and dynamic window sizing algorithms for the **Wallpaper Control** plugin.

---

## 1. Backend Components Overview

```
plasma-wallpaper-control/
├── bin/
│   ├── set_wallpaper.py     # Main CLI orchestrator, DBus bridge & standalone QQuickView host
│   └── color_manager.py     # ICC profile extraction, canonicalization & LittleCMS sRGB conversion
└── servicemenus/
    └── plasma_crop_wallpaper.desktop  # Dolphin file manager right-click service menu
```

---

## 2. ICC Profile & Color Management (`bin/color_manager.py`)

### 1. Detection and Profile Parsing
Wide-gamut wallpapers (such as Display P3, Adobe RGB, ProPhoto RGB, DCI-P3) appear desaturated in Qt 6 / Plasma without color space conversion.
- `detect_color_profile(image_path)` extracts embedded ICC profile metadata using Pillow (`PIL.ImageCms`).
- Distinguishes between standard sRGB and wide-gamut profiles (matching primaries, transfer function, or profile description).

### 2. Canonical Profile Naming
- **Problem:** Raw embedded ICC descriptions often contain lengthy technical strings (e.g. `SMPTE RP 431-2-2007 DCI (P3)` or `Display P3 v4`).
- **Design Decision:** `canonicalize_profile_name(raw_name)` standardizes all profile descriptions to clean, user-friendly labels across both QML interfaces:
  - Matches `p3`, `smpte`, or `dci` $\rightarrow$ **`Display P3`**
  - Matches `adobe` $\rightarrow$ **`Adobe RGB`**
  - Matches `prophoto` or `romm` $\rightarrow$ **`ProPhoto RGB`**
  - Matches `2020` or `rec2020` $\rightarrow$ **`Rec. 2020`**

### 3. On-Demand LittleCMS Conversion
When `convert_to_srgb(image_path)` is invoked:
- Uses `ImageCms.buildTransform()` to perform perceptual-intent color conversion from the input ICC profile to standard sRGB.
- Saves the output as a losslessly compressed PNG with stripped/normalized metadata in the local cache.

---

## 3. Cache Management: Single-Image Session Cache

### Architectural Policy & Design Choice
- **Problem:** Storing multi-image converted caches consumes unnecessary disk space over time.
- **Design Decision:** Enforce a **single-image session cache** policy:
  - Converted images are stored under `~/.cache/plasma-crop-wallpaper/converted/`.
  - When a new image is selected and converted, previous cached sRGB conversions for other wallpapers are pruned from disk.
  - Conserves storage while maintaining instantaneous switching during the current cropping session.

---

## 4. Standalone Window Sizing Algorithm (`bin/set_wallpaper.py`)

To prevent UI elements from being pushed off-screen and provide a visually pleasing preview:

```
Screen Available Geometry: [max_w = 90% Screen Width, max_h = 88% Screen Height]
Minimum Dimensions:        [min_w = 850px, min_h = 650px]
```

### Orientation-Specific Calculations
1. **Landscape Images ($\text{Aspect} \ge 1.0$):**
   - Targets a base canvas height of $\min(680, H_{\text{avail}})$.
   - Scales canvas width $W_{\text{canvas}} = H_{\text{canvas}} \times \text{Aspect}$.
   - Clamps dialog dimensions:
     $$W_{\text{target}} = \max(W_{\text{min}}, \min(W_{\text{max}}, W_{\text{canvas}} + W_{\text{chrome}}))$$
     $$H_{\text{target}} = \max(H_{\text{min}}, \min(H_{\text{max}}, H_{\text{canvas}} + H_{\text{chrome}}))$$

2. **Portrait Images ($\text{Aspect} < 1.0$):**
   - Maximizes canvas height $H_{\text{canvas}} = \min(740, H_{\text{avail}})$.
   - Calculates canvas width $W_{\text{canvas}} = H_{\text{canvas}} \times \text{Aspect}$.
   - Window width is strictly clamped to at least $W_{\text{min}}$ ($850\text{px}$) to ensure the top toolbar, aspect ratio combo, and action buttons never overflow:
     $$W_{\text{target}} = \max(W_{\text{min}}, \min(W_{\text{max}}, \max(W_{\text{canvas}} + W_{\text{chrome}}, W_{\text{min}})))$$
     $$H_{\text{target}} = \max(H_{\text{min}}, \min(H_{\text{max}}, H_{\text{canvas}} + H_{\text{chrome}}))$$

---

## 5. KDE Plasma 6 DBus Wallpaper Application

### Desktop Wallpaper Script Injection
Applying wallpaper to the desktop communicates with `org.kde.plasmashell` via `evaluateScript`:

```javascript
let allDesktops = desktops();
for (let i = 0; i < allDesktops.length; ++i) {
    let d = allDesktops[i];
    d.wallpaperPlugin = "org.kde.plasma.cropwallpaper";
    d.currentConfigGroup = Array("Wallpaper", "org.kde.plasma.cropwallpaper", "General");
    d.writeConfig("Image", "%IMAGE_URL%");
    d.writeConfig("CropX", %CROP_X%);
    d.writeConfig("CropY", %CROP_Y%);
    d.writeConfig("CropWidth", %CROP_W%);
    d.writeConfig("CropHeight", %CROP_H%);
}
```

### Lockscreen Configuration
Lockscreen settings are written directly to `~/.config/kscreenlockerrc` under `[Greeter][Wallpaper][org.kde.plasma.cropwallpaper][General]` and synchronized with `kwriteconfig6`.

---

## 6. SDDM Login Screen Wallpaper Application & Privilege Elevation

### 1. Architectural Challenge
SDDM (Simple Desktop Display Manager) operates outside user session context as a system-level daemon (`root` or `sddm` user). Unlike `plasmashell` or `kscreenlocker`, SDDM:
1. Does not evaluate Plasma wallpaper packages (`org.kde.plasma.cropwallpaper`).
2. Requires a physically rendered, static image file.
3. Requires root privileges to modify theme configurations in `/usr/share/sddm/themes/`.

### 2. Physical Crop Rasterization (`export_cropped_image`)
When SDDM is selected as a target, `set_wallpaper.py` uses Pillow to calculate the exact pixel crop geometry `[left, top, right, bottom]` based on normalized `[CropX, CropY, CropWidth, CropHeight]`, ensuring sRGB conversion is applied if the source image uses a wide color gamut. The cropped output is rendered to a temporary image with world-readable permissions (`0o644`).

### 3. Active Theme Detection (`get_active_sddm_theme`)
The backend parses system configuration files in priority order to identify the current active theme:
1. `/etc/sddm.conf.d/kde_settings.conf`
2. `/etc/sddm.conf.d/*.conf`
3. `/etc/sddm.conf`
4. `/usr/lib/sddm/sddm.conf.d/default.conf`
5. Fallback: `breeze` or first available folder under `/usr/share/sddm/themes/`.

### 4. Privilege Elevation via PolicyKit (`pkexec`)
The GUI application never runs as root. Instead, the backend invokes a scoped root helper via `pkexec`:

```bash
pkexec python3 bin/set_wallpaper.py --internal-sddm-apply <THEME> <TEMP_IMAGE>
```

The privileged helper routine:
- Copies the rendered crop into `/usr/share/sddm/themes/<THEME>/plasma_crop_wallpaper.<ext>`.
- Applies safe permissions (`0o644`).
- Updates `/usr/share/sddm/themes/<THEME>/theme.conf.user` with `background=plasma_crop_wallpaper.<ext>` and `type=image`.
- Safely cleans up temporary files upon completion.

---

## 7. Dolphin Service Menu Lifecycle, Uninstallation Safety & Self-Healing

### 1. Dual-Layer Uninstallation Safety
KDE Plasma's KNewStuff engine does not execute uninstallation scripts when a wallpaper plugin is removed via the GUI ("More Plugins..."). To prevent broken menu entries or orphaned files:

1. **Passive Omission (`TryExec`):**
   - The desktop file sets `TryExec=@SET_WALLPAPER_BIN@`.
   - When the package directory is removed by KDE, Dolphin detects the missing binary and immediately omits the context action from the right-click menu.
2. **Active Cleanup Fallback (`Exec`):**
   - If a menu entry remains cached in an active session, clicking it triggers:
     ```bash
     Exec=sh -c 'if [ -f "$0" ]; then exec "$0" "$@"; else kwriteconfig6 --file kservicemenurc --group Show --key wallpaperfileitemaction true && kbuildsycoca6 --noincremental && rm -f "$HOME/.local/share/kio/servicemenus/plasma_crop_wallpaper.desktop"; fi' @SET_WALLPAPER_BIN@ --crop %u
     ```
   - If the binary is missing, it automatically restores `wallpaperfileitemaction = true`, removes the residual `.desktop` file, and updates the Sycoca cache.

### 2. Zero-Overhead Self-Healing (`heal_legacy_context_menu`)
Earlier versions (v1.1.0) disabled KDE's built-in `wallpaperfileitemaction` in `~/.config/kservicemenurc`. To repair affected systems cleanly:
- `heal_legacy_context_menu()` checks `kservicemenurc` and resets `wallpaperfileitemaction` back to `true`.
- **Strictly Scoped Execution:** The check runs **only** during context menu setup (`enable_context_menu()`) or explicit maintenance (`--heal`).
- Routine image inspection (`--get-info`), conversion (`--convert-image`), and cropping (`--crop`) never perform regex or file checks against `kservicemenurc`, ensuring zero runtime latency.

### 3. CLI Command Reference

| Flag / Option | Description |
| :--- | :--- |
| `[image_path]` | Path or URL to target image file. |
| `--crop` | Launches the interactive standalone crop dialog (`CropDialogWindow.qml`). |
| `--target [desktop\|lockscreen\|sddm\|both\|all]` | Target surface(s) to apply wallpaper to (default: `desktop`). |
| `--targets [TARGET ...]` | Space-separated list of multiple destinations (e.g. `--targets desktop sddm`). |
| `--get-info` | Returns JSON metadata with detected dimensions, color profile name, and wide-gamut status. |
| `--convert-image` | Converts wide-gamut image to cached sRGB PNG and prints cached URL. |
| `--enable-context-menu` | Installs the Dolphin service menu and performs legacy self-healing. |
| `--disable-context-menu` | Removes the Dolphin service menu and ensures default action is enabled. |
| `--status-context-menu` | Outputs whether the service menu file currently exists. |
| `--heal` | Performs one-time self-healing of legacy `kservicemenurc` configuration. |
| `--internal-sddm-apply` | Internal privileged root helper invoked via `pkexec`. |

---

## 8. Safe URL & Path Handling (Special Characters & Fragments)

### 1. The Fragment Identifier Collision
In standard URI syntax (RFC 3986), `#` introduces a fragment identifier (anchor).
- **Failure Mode:** When unencoded `file:///path/to/image #08.jpg` URLs were passed to Qt Quick's `Image` element or Python's `urlparse()`, everything following `#` was stripped as a fragment identifier. Qt Quick attempted to open `/path/to/image `, which did not exist on disk, causing `QQuickImage: Cannot open` errors and displaying a blank preview canvas.

### 2. Idempotent Encoding & Decoding Pipeline
- **`to_file_url(path)`:**
  Standardizes input paths and encodes them using `urllib.parse.quote(local_path, safe="/:@&+$,~-_.!*'")`.
  Special characters (`#` $\rightarrow$ `%23`, `?` $\rightarrow$ `%3F`, spaces $\rightarrow$ `%20`) are safely escaped, guaranteeing that `QUrl::toLocalFile()` resolves the exact, unabridged filesystem path without fragment truncation.
- **`from_file_url(url_or_path)`:**
  Extracts and resolves physical filesystem paths.
  Only strips and unquotes `file://` or `file://localhost/` prefixes, leaving raw local paths containing literal `%` characters (e.g. `/path/to/100% pure.png`) intact without double-decoding or corruption.
- **DBus & Configuration Parity:**
  Desktop (`evaluateScript`) and Lockscreen (`kwriteconfig6`) configuration updates always store percent-encoded `to_file_url()` values, ensuring Plasma's desktop wallpaper item loads images with `#` without displaying a black fallback matte.



