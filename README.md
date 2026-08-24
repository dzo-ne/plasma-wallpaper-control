# KDE Plasma 6 Crop & Pan Wallpaper Plugin

A standalone **KDE Plasma 6 / Qt 6 / KF6** wallpaper plugin that enables interactive selection, panning, resizing, and precision aspect-ratio cropping of wallpaper images (similar to modern mobile wallpaper crop selectors).

<img width="1378" height="1038" alt="image" src="https://github.com/user-attachments/assets/79d0687e-7a8a-4f72-88f4-1aeab24d356c" />

---

## 1. Architectural Design & Coordinate Transformations

To eliminate drift and ensure resolution independence across multi-monitor setups, high-DPI displays, and screen rotations, all geometry is modeled mathematically across three decoupled coordinate spaces:

```
[Raw Image Space: (0..W_i, 0..H_i)]
                 │
                 ▼  (Normalized Space: u = x/W_i, v = y/H_i)
[KConfigXT Storage: CropX, CropY, CropWidth, CropHeight ∈ [0.0, 1.0]]
                 │
                 ▼  (Display Viewport Space: Scale factor s = min(W_c/W_i, H_c/H_i))
[Interactive Canvas: x_b = X_d + u·W_d, y_b = Y_d + v·H_d]
```

### Mathematical Formulations

#### 1. Display Viewport Projection
For a preview canvas $(W_c, H_c)$ and image natural dimensions $(W_i, H_i)$:
$$s = \min\left(\frac{W_c}{W_i}, \frac{H_c}{H_i}\right), \quad W_d = W_i \cdot s, \quad H_d = H_i \cdot s$$
$$X_d = \frac{W_c - W_d}{2}, \quad Y_d = \frac{H_c - H_d}{2}$$

#### 2. Screen Aspect Ratio Enforcement
Let the desktop screen have aspect ratio $R_s = W_s / H_s$. In physical pixels, the crop rectangle satisfies:
$$\frac{w_{\text{pixel}}}{h_{\text{pixel}}} = \frac{w_n \cdot W_i}{h_n \cdot H_i} = R_s \implies \frac{w_n}{h_n} = R_s \cdot \frac{H_i}{W_i}$$

In canvas display space:
$$\frac{w_b}{h_b} = \frac{w_n \cdot W_d}{h_n \cdot H_d} = \frac{w_n \cdot W_i \cdot s}{h_n \cdot H_i \cdot s} = \frac{w_n \cdot W_i}{h_n \cdot H_i} = R_s$$
Thus, the displayed crop window $(w_b, h_b)$ directly mirrors the physical proportions of the target display screen.

#### 3. Normalized Panning & Corner Resizing
When dragged by $(\Delta x, \Delta y)$ in display pixels:
$$u_{\text{new}} = \text{clamp}\left(u + \frac{\Delta x}{W_d}, 0, 1 - w_n\right), \quad v_{\text{new}} = \text{clamp}\left(v + \frac{\Delta y}{H_d}, 0, 1 - h_n\right)$$

---

## 2. Package File Structure

```
plasma-wallpaper-control/
├── metadata.json              # KPackage Plasma/Wallpaper manifest
├── contents/
│   ├── config/
│   │   └── main.xml           # KConfigXT schema for wallpaper settings
│   └── ui/
│       ├── main.qml           # Desktop wallpaper renderer (sourceClipRect)
│       └── config.qml         # Interactive configuration & crop canvas UI
├── install.sh                 # Packaging and installation script
├── test_runner.py             # Headless QML compilation and syntax validator
├── test_functional.py         # Headless functional unit test for crop math
└── README.md                  # Complete documentation
```

---

## 3. Configuration Properties (`KConfigXT`)

| Property | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `Image` | `String` | `""` | Source file URL or path |
| `CropX` | `Double` | `0.0` | Normalized horizontal offset ($0.0 \dots 1.0$) |
| `CropY` | `Double` | `0.0` | Normalized vertical offset ($0.0 \dots 1.0$) |
| `CropWidth` | `Double` | `1.0` | Normalized crop width ($0.0 \dots 1.0$) |
| `CropHeight` | `Double` | `1.0` | Normalized crop height ($0.0 \dots 1.0$) |
| `LockScreenAspect` | `bool` | `true` | Enforces display aspect ratio constraint |
| `AspectRatioMode` | `int` | `0` | Aspect ratio mode (0: Screen, 1: Free, 2: 16:9, etc.) |
| `Color` | `Color` | `#000000` | Fallback matte color |
| `FillMode` | `int` | `1` | Viewport fill mode (`Image.PreserveAspectCrop`) |

---

## 4. Installation & Usage

### Installing via `kpackagetool6`

```bash
# Install the wallpaper package to ~/.local/share/plasma/wallpapers/
kpackagetool6 --type Plasma/Wallpaper --install .

# Or upgrade an existing installation
kpackagetool6 --type Plasma/Wallpaper --upgrade .
```

Alternatively, execute the included script:
```bash
./install.sh
```

### Running in Standalone Window for Testing

```bash
plasmawindowed org.kde.plasma.cropwallpaper
```

### Dolphin / File Manager Context Menu

When right-clicking any image in Dolphin / KDE File Manager:
- **Crop & Pan as Wallpaper…**: Opens an interactive visual crop selector preloaded with the selected image, allowing you to pan/zoom/crop and apply to **Desktop**, **Lockscreen**, or **Both**.

### Uninstallation

To cleanly uninstall the wallpaper plugin and remove the Dolphin context menu:

```bash
./uninstall.sh
```

Or manually via `kpackagetool6`:
```bash
kpackagetool6 --type Plasma/Wallpaper --remove org.kde.plasma.cropwallpaper
rm -f ~/.local/share/kio/servicemenus/plasma_crop_wallpaper.desktop
kbuildsycoca6 --noincremental
```

---

## 5. Documentation & Technical Specifications

For detailed architecture and system interaction specifications:
- **[Frontend Architecture & Design Decisions](docs/FRONTEND.md)**: QtQuick/QML UI layer, coordinate geometry math, zero-flicker dual-layer preview, and responsive layout constraints.
- **[Backend Architecture & Design Decisions](docs/BACKEND.md)**: Python CLI bridge, LittleCMS color management, session cache policy, and dynamic window sizing algorithms.
