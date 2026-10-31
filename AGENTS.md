# AGENTS.md

## Project
**Wallpaper Control** (`org.kde.plasma.cropwallpaper`) is a KDE Plasma 6 wallpaper plugin and standalone management utility written in QML (Qt 6 / Kirigami / KF6) and Python 3 (PyQt6, Pillow/LittleCMS, Polkit `pkexec`).

## Layout
- `contents/config/main.xml`: KConfigXT schema — single source of truth for persisted `cfg_*` wallpaper configuration properties.
- `contents/ui/main.qml`: Desktop/lockscreen `WallpaperItem` renderer using `sourceClipRect` and an invisible `imageProbe` to avoid `implicitWidth`/`implicitHeight` binding loops.
- `contents/ui/config.qml`: Embedded Plasma Desktop Settings UI; shells out to `bin/set_wallpaper.py` via `Plasma5Support.DataSource`.
- `contents/ui/CropDialogWindow.qml`: Standalone crop/apply window hosted by `bin/set_wallpaper.py --crop` (`QQuickView`) with the `wallpaperBridge` (`QObject`) context property.
- `bin/set_wallpaper.py`: CLI orchestrator, standalone QML host, DBus script evaluator (`org.kde.plasmashell`), lockscreen writer (`kwriteconfig6`), and `pkexec` SDDM helper.
- `bin/color_manager.py`: ICC profile inspection (`detect_color_profile`) and single-image session cache sRGB converter (`~/.cache/plasma-crop-wallpaper/converted/`).
- `servicemenus/plasma_crop_wallpaper.desktop`: Dolphin context menu template (`@SET_WALLPAPER_BIN@` substituted on install).

## Rules
- **Normalized Crop Geometry**: Crop coordinates (`CropX`, `CropY`, `CropWidth`, `CropHeight`) are always normalized floats in `[0.0, 1.0]` relative to natural image dimensions.
- **No False Unsaved Changes on Init**: Opening `config.qml` with an existing configuration must never mutate `cfg_*` properties during initial load (`pendingNewImageFit` guards auto-fitting so it only triggers on user-selected new images).
- **URL & Special Character Safety**: Image properties bound to QML `Image.source` or persisted to config must be percent-encoded `file://` URLs (`to_file_url()` in Python, `toEncodedFileUrl()` in QML) so `#`, `?`, `[`, `]`, and spaces do not truncate as URI fragments. Never double-encode URLs; `pathField` displays decoded paths via `formatDisplayPath()`.
- **Dual-Layer Zero-Flicker Preview**: Keep `rawPreviewImage` (`visible: true`) beneath `srgbPreviewImage` (`visible: useSrgbFix && srgbImagePath.length > 0`). Bind geometry only to `rawPreviewImage.implicitWidth`/`implicitHeight` and never add opacity fade animations.
- **QQC2 Two-Way Bindings**: Never attach `Binding on checked` to `QQC2.Switch` or `QQC2.CheckBox`; bind `checked: ...` directly and mutate state inside `onClicked`.
- **Component Scoping & Scroll Passthrough**: Keep the Dolphin context menu toggle exclusively in `config.qml` (never in `CropDialogWindow.qml`). In `config.qml`, plain mouse wheel over the canvas must pass through (`wheel.accepted = false`) for page scrolling; only `Ctrl + Wheel` zooms the crop box.
- **Privilege & Cache Boundaries**: Never run the GUI as root; SDDM updates must rasterize a static crop first (`export_cropped_image`) and invoke `pkexec python3 bin/set_wallpaper.py --internal-sddm-apply <THEME> <TEMP_IMAGE>`. Keep `heal_legacy_context_menu()` scoped to `--enable-context-menu` and `--heal` only.

## Commands
```bash
# Run QML compilation, SDDM export, URL encoding, and functional tests (headless, no side effects)
QT_QPA_PLATFORM=offscreen python3 test_runner.py
QT_QPA_PLATFORM=offscreen python3 test_functional.py
python3 test_sddm.py

# Safe read-only CLI inspection (no desktop/system changes)
python3 bin/set_wallpaper.py --get-info /path/to/image.jpg
python3 bin/set_wallpaper.py --status-context-menu

# Interactive / system-modifying commands (modifies user config, service menus, or SDDM via pkexec)
python3 bin/set_wallpaper.py --crop /path/to/image.jpg
./install.sh
./uninstall.sh
```

## More
- `docs/FRONTEND.md`: QML component architecture, coordinate math, dual-layer preview, and responsive layout rules.
- `docs/BACKEND.md`: Python CLI flags, DBus/lockscreen/SDDM application flow, ICC color pipeline, and service menu self-healing.
