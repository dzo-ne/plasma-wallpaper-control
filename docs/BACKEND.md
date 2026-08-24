# Backend Architecture & Design Decisions

This document details the Python CLI backend, KDE Plasma DBus inter-process communication, ICC color management, cache lifecycle, and dynamic window sizing algorithms for the **Crop & Pan Wallpaper** plugin.

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
