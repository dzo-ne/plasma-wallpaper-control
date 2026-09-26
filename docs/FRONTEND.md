# Frontend Architecture & Design Decisions

This document details the QtQuick/QML frontend architecture, UI layout constraints, interactive canvas geometry, system interactions, and all frontend-specific design choices and intentional omissions for the **Wallpaper Control** plugin.

---

## 1. Component Overview & Scoping

The frontend consists of three decoupled QML components:

| Component | File Path | Context & Scope |
| :--- | :--- | :--- |
| **Wallpaper View** | `contents/ui/main.qml` | Desktop background rendering component instantiated by Plasma Shell. Uses `sourceClipRect` to display the cropped region on the desktop/lockscreen. |
| **Desktop Settings UI** | `contents/ui/config.qml` | Embedded configuration page rendered within KDE's "Configure Desktop and Wallpaper..." dialog. Contains full settings including the Dolphin context menu toggle, color profile fix, fallback matte color, and aspect ratio selector. |
| **Standalone Crop Dialog** | `contents/ui/CropDialogWindow.qml` | Standalone window launched from the Dolphin context menu (`--crop`) or CLI. Focused strictly on interactive cropping and immediate wallpaper application. |

### Design Choice: Standalone Dialog vs Desktop Settings Scoping
- **Decision:** The standalone dialog (`CropDialogWindow.qml`) is kept minimal, distraction-free, and dedicated solely to cropping and applying wallpapers.
- **Intentional Omission:** **The Dolphin context menu checkbox is intentionally omitted from `CropDialogWindow.qml`.** System integration settings belong exclusively in the desktop settings page (`config.qml`).

---

## 2. Interactive Canvas & Coordinate Transformations

To eliminate drift and ensure resolution independence across multi-monitor setups, high-DPI displays, and screen rotations, all geometry is modeled mathematically across three decoupled coordinate spaces:

```
[Raw Image Space: (0..W_i, 0..H_i)]
                 │
                 ▼  (Normalized Space: u = x / W_i, v = y / H_i ∈ [0.0, 1.0])
[KConfigXT / Properties: CropX, CropY, CropWidth, CropHeight]
                 │
                 ▼  (Canvas Viewport Space: Scale factor s = min(W_c / W_i, H_c / H_i))
[Interactive Viewport: x_disp = X_off + u * W_disp, y_disp = Y_off + v * H_disp]
```

### Mathematical Formulations
1. **Aspect-Fit Display Projection:**
   $$s = \min\left(\frac{W_c}{W_i}, \frac{H_c}{H_i}\right), \quad W_d = W_i \cdot s, \quad H_d = H_i \cdot s$$
   $$X_d = \frac{W_c - W_d}{2}, \quad Y_d = \frac{H_c - H_d}{2}$$
2. **Normalized Drag & Panning:**
   $$u_{\text{new}} = \text{clamp}\left(u + \frac{\Delta x}{W_d}, 0, 1 - w_n\right), \quad v_{\text{new}} = \text{clamp}\left(v + \frac{\Delta y}{H_d}, 0, 1 - h_n\right)$$
3. **Screen Aspect Ratio Constraint:**
   $$\frac{w_n}{h_n} = R_{\text{target}} \cdot \frac{H_i}{W_i}$$

---

## 3. Zero-Flicker Dual-Layer Image Preview

### Problem Solved
Switching an `Image.source` property directly unloads the existing texture buffer in QtQuick, exposing the canvas background (`#141414`) for 50–150ms while decoding the new image. This creates a harsh stroboscopic black flash that causes visual discomfort.

### Architecture & Layer Stacking
Both `config.qml` and `CropDialogWindow.qml` use a **stacked dual-layer image architecture**:

```
┌──────────────────────────────────────────────────────────────┐
│ Viewport Overlay (Crop rectangle, handles, 3x3 grid, masks)  │
├──────────────────────────────────────────────────────────────┤
│ Top Layer: srgbPreviewImage                                  │
│   source: srgbImagePath                                      │
│   visible: useSrgbFix && (srgbImagePath.length > 0)          │
├──────────────────────────────────────────────────────────────┤
│ Base Layer: rawPreviewImage                                  │
│   source: rawImagePath                                       │
│   visible: true (Keeps GPU texture warm; never unloads)      │
└──────────────────────────────────────────────────────────────┘
```

- **Instant Zero-Latency Toggling:** Toggling `useSrgbFix` mutates `srgbPreviewImage.visible` instantaneously (0ms GPU state toggle).
- **Persistent Geometry Anchoring:** All viewport geometry, drag handlers, and dimension labels bind exclusively to `rawPreviewImage.implicitWidth` and `rawPreviewImage.implicitHeight`.
- **Targeted Loading Indicators:**
  - Full-canvas `loadingOverlay` is shown **only** on the initial cold load of an un-cached image from disk.
  - On-demand background sRGB conversion displays a compact 16×16 `QQC2.BusyIndicator` next to the `sRGB` switch without darkening or obscuring the canvas.

### Design Choice: Rejection of Fade Transitions
- **Decision:** **Fade animations (e.g. `NumberAnimation on opacity`) are intentionally omitted.** Instant layer switching (`visible: true/false`) avoids perceptual lag, eliminates soft ghosting, and keeps GPU redraw overhead at zero.

---

## 4. UI Layout & Responsive Sizing Constraints

To prevent horizontal clipping and ensure all action controls remain accessible across varied window dimensions:

1. **Top Controls Bar Layout:**
   - **Streamlined Design:** The inner `"Wallpaper Control"` heading is omitted from the toolbar to avoid duplicating the window title bar and to eliminate horizontal crowding.
   - **Visual Hierarchy:** The Aspect Ratio dropdown is positioned on the left (`Layout.alignment: Qt.AlignLeft`), followed by an expanding spacer, with positioning actions (`Fit Screen`, `Center`, `Reset`) cleanly grouped on the right.
2. **Dedicated Color Warning Row:**
   - The wide-gamut / Display P3 warning label uses `wrapMode: Text.WordWrap` and `Layout.fillWidth: true`.
   - Placed in its own dedicated row to prevent displacing canvas elements or action controls.
3. **Unified Destination Action Row:**
   - Crop resolution badge and inline error reporting are aligned on the left.
   - Destination targets (`[ ] Desktop`, `[ ] Lockscreen`, `[ ] Login Screen (SDDM)`) are rendered as checkboxes (untoggled by default to prevent accidental overwrites).
   - An inline `QQC2.BusyIndicator` provides visual feedback during PolicyKit authentication and file generation.
   - Action buttons (`Cancel` and `Apply`) are grouped on the far right. The `Apply` button dynamically enables only when at least one destination checkbox is selected.
   - The layout comfortably fits within the minimum 850px window constraint.

---

## 5. QtQuick Controls 2 Two-Way Binding Rules

### Design Choice: Avoiding Cyclic Binding Collisions
In QtQuick Controls 2 (such as `QQC2.Switch` and `QQC2.CheckBox`), adding `Binding on checked { value: ... }` causes cyclic binding fights where Qt resets `checked` back to its pre-click state before click handlers execute.
- **Enforced Rule:** Always bind `checked: root.useSrgbFix` and update state via `onClicked: { root.useSrgbFix = checked; ... }`.

---

## 6. Safe URL & Special Character Handling

In QML, `Image.source` is a `url` property backed by Qt's `QUrl`.
- **Fragment Delimiter Collision:** In URI syntax, `#` introduces a fragment identifier. Passing an unencoded `#` in a file path causes `QUrl` to truncate the path, causing image loading to fail.
- **Enforced Rule:** All image sources passed to QML are normalized and percent-encoded with `%23` for `#`, `%20` for spaces, and `%3F` for `?`.
- **Manual Input Sanitization:** When paths are typed or pasted into `pathField` in `config.qml`, `onEditingFinished` automatically formats the input into a `file://` URL with `#` encoded to `%23` before assigning to `cfg_Image`.
- **Process Parameter Quoting:** Path arguments passed to backend command line invocations via `Plasma5Support.DataSource` are escaped to prevent shell interpretation issues.

