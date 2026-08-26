#!/usr/bin/env python3
"""
CLI & Service Menu Helper for KDE Plasma 6 Wallpaper Control.
Allows setting wallpaper on Desktop, Lockscreen, SDDM Login Screen, or all three,
launching an interactive cropping window, or toggling Dolphin context menu integration.
"""

import os
import sys
import shutil
import tempfile
import subprocess
import argparse
import configparser
from urllib.parse import urlparse, unquote

script_dir = os.path.dirname(os.path.abspath(__file__))
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

try:
    from color_manager import ensure_srgb_image, detect_color_profile, get_image_metadata, get_cache_dir
except ImportError:
    def ensure_srgb_image(p): return p, False
    def detect_color_profile(p): return {"is_non_srgb": False, "profile_name": "", "has_icc": False}
    def get_image_metadata(p): return {"is_non_srgb": False, "is_converted": False, "profile_name": "", "original_path": p}
    def get_cache_dir(): return "/tmp"

SERVICEMENU_DIR = os.path.expanduser("~/.local/share/kio/servicemenus")
SERVICEMENU_FILE = os.path.join(SERVICEMENU_DIR, "plasma_crop_wallpaper.desktop")

def to_file_url(path):
    if path.startswith("file://"):
        return path
    abs_path = os.path.abspath(os.path.expanduser(path))
    return f"file://{abs_path}"

def from_file_url(url_or_path):
    if url_or_path.startswith("file://"):
        parsed = urlparse(url_or_path)
        return unquote(parsed.path)
    return os.path.abspath(os.path.expanduser(url_or_path))

def export_cropped_image(image_path, crop_x=0.0, crop_y=0.0, crop_w=1.0, crop_h=1.0, output_path=None):
    """
    Renders and exports the cropped viewport to a physical static image file.
    Applies sRGB conversion if needed for color fidelity.
    """
    raw_path = from_file_url(image_path)
    if not os.path.isfile(raw_path):
        raise FileNotFoundError(f"Source image not found: {raw_path}")

    # Use sRGB version if source has wide gamut
    source_to_open, _ = ensure_srgb_image(raw_path)

    if not HAS_PIL:
        # Fallback if Pillow is somehow unavailable: copy raw image
        if output_path is None:
            tmp_fd, output_path = tempfile.mkstemp(prefix="sddm_wallpaper_crop_", suffix=".png", dir="/tmp")
            os.close(tmp_fd)
        shutil.copy2(source_to_open, output_path)
        os.chmod(output_path, 0o644)
        return output_path

    with Image.open(source_to_open) as img:
        orig_w, orig_h = img.size

        # Clamp normalized crop parameters
        u = max(0.0, min(1.0, float(crop_x)))
        v = max(0.0, min(1.0, float(crop_y)))
        wn = max(0.001, min(1.0 - u, float(crop_w)))
        hn = max(0.001, min(1.0 - v, float(crop_h)))

        px = int(round(u * orig_w))
        py = int(round(v * orig_h))
        pw = int(round(wn * orig_w))
        ph = int(round(hn * orig_h))

        left = max(0, min(orig_w - 1, px))
        top = max(0, min(orig_h - 1, py))
        right = max(left + 1, min(orig_w, px + pw))
        bottom = max(top + 1, min(orig_h, py + ph))

        cropped = img.crop((left, top, right, bottom))

        if output_path is None:
            tmp_fd, output_path = tempfile.mkstemp(prefix="sddm_wallpaper_crop_", suffix=".png", dir="/tmp")
            os.close(tmp_fd)

        if output_path.lower().endswith((".jpg", ".jpeg")):
            if cropped.mode in ("RGBA", "P"):
                cropped = cropped.convert("RGB")
            cropped.save(output_path, "JPEG", quality=95)
        else:
            cropped.save(output_path, "PNG", optimize=False)

        os.chmod(output_path, 0o644)
        return output_path

def get_active_sddm_theme():
    """Detects active SDDM theme name from system config files or defaults to 'breeze'."""
    candidate_configs = [
        "/etc/sddm.conf.d/kde_settings.conf",
        "/etc/sddm.conf",
    ]
    if os.path.isdir("/etc/sddm.conf.d"):
        for f in sorted(os.listdir("/etc/sddm.conf.d")):
            if f.endswith(".conf") and f != "kde_settings.conf":
                candidate_configs.append(os.path.join("/etc/sddm.conf.d", f))
    candidate_configs.append("/usr/lib/sddm/sddm.conf.d/default.conf")

    for cfg_path in candidate_configs:
        if os.path.isfile(cfg_path):
            try:
                cp = configparser.ConfigParser()
                cp.read(cfg_path)
                if cp.has_section("Theme") and cp.has_option("Theme", "Current"):
                    val = cp.get("Theme", "Current").strip()
                    if val and os.path.isdir(os.path.join("/usr/share/sddm/themes", val)):
                        return val
            except Exception:
                pass

    if os.path.isdir("/usr/share/sddm/themes/breeze"):
        return "breeze"
    if os.path.isdir("/usr/share/sddm/themes"):
        themes = [d for d in os.listdir("/usr/share/sddm/themes") if os.path.isdir(os.path.join("/usr/share/sddm/themes", d))]
        if themes:
            return sorted(themes)[0]
    return "breeze"

def apply_sddm_root(theme_name: str, temp_image_path: str):
    """
    Executed as root via pkexec.
    Copies cropped image into /usr/share/sddm/themes/<theme_name>/ and
    updates theme.conf.user with background and type settings.
    """
    if not os.path.isfile(temp_image_path):
        print(f"[!] Cropped image not found: {temp_image_path}", file=sys.stderr)
        sys.exit(1)

    theme_dir = os.path.join("/usr/share/sddm/themes", theme_name)
    if not os.path.isdir(theme_dir):
        theme_dir = "/usr/share/sddm/themes/breeze"
        if not os.path.isdir(theme_dir):
            print(f"[!] SDDM theme directory not found: {theme_dir}", file=sys.stderr)
            sys.exit(1)

    ext = os.path.splitext(temp_image_path)[1]
    if not ext:
        ext = ".png"
    dest_filename = f"plasma_crop_wallpaper{ext}"
    dest_path = os.path.join(theme_dir, dest_filename)

    try:
        shutil.copy2(temp_image_path, dest_path)
        os.chmod(dest_path, 0o644)
    except Exception as e:
        print(f"[!] Error copying wallpaper to {dest_path}: {e}", file=sys.stderr)
        sys.exit(1)

    conf_user = os.path.join(theme_dir, "theme.conf.user")
    cp = configparser.RawConfigParser()
    if os.path.isfile(conf_user):
        try:
            cp.read(conf_user)
        except Exception:
            pass

    if not cp.has_section("General"):
        cp.add_section("General")

    cp.set("General", "background", dest_filename)
    cp.set("General", "type", "image")
    if not cp.has_option("General", "showClock"):
        cp.set("General", "showClock", "true")

    try:
        with open(conf_user, "w", encoding="utf-8") as f:
            cp.write(f)
        os.chmod(conf_user, 0o644)
    except Exception as e:
        print(f"[!] Error writing {conf_user}: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        if os.path.isfile(temp_image_path):
            os.remove(temp_image_path)
    except OSError:
        pass

    print(f"[✓] SDDM theme '{os.path.basename(theme_dir)}' updated with background '{dest_filename}'")
    sys.exit(0)

def set_desktop_wallpaper(image_path, crop_x=0.0, crop_y=0.0, crop_w=1.0, crop_h=1.0):
    img_url = to_file_url(image_path)

    js_script = f"""
    var allDesktops = desktops();
    for (var i = 0; i < allDesktops.length; i++) {{
        var d = allDesktops[i];
        d.wallpaperPlugin = "org.kde.plasma.cropwallpaper";
        d.currentConfigGroup = Array("Wallpaper", "org.kde.plasma.cropwallpaper", "General");
        d.writeConfig("Image", "{img_url}");
        d.writeConfig("CropX", {crop_x});
        d.writeConfig("CropY", {crop_y});
        d.writeConfig("CropWidth", {crop_w});
        d.writeConfig("CropHeight", {crop_h});
    }}
    """
    try:
        subprocess.run(["qdbus6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", js_script], check=True)
        print(f"[✓] Desktop wallpaper updated to: {img_url}")
        return True
    except Exception as e:
        print(f"[!] Error setting desktop wallpaper via DBus: {e}")
        return False

def set_lockscreen_wallpaper(image_path, crop_x=0.0, crop_y=0.0, crop_w=1.0, crop_h=1.0):
    img_url = to_file_url(image_path)
    try:
        subprocess.run(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--key", "WallpaperPlugin", "org.kde.plasma.cropwallpaper"], check=True)
        subprocess.run(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.plasma.cropwallpaper", "--group", "General", "--key", "Image", img_url], check=True)
        subprocess.run(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.plasma.cropwallpaper", "--group", "General", "--key", "CropX", str(crop_x)], check=True)
        subprocess.run(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.plasma.cropwallpaper", "--group", "General", "--key", "CropY", str(crop_y)], check=True)
        subprocess.run(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.plasma.cropwallpaper", "--group", "General", "--key", "CropWidth", str(crop_w)], check=True)
        subprocess.run(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.plasma.cropwallpaper", "--group", "General", "--key", "CropHeight", str(crop_h)], check=True)
        print(f"[✓] Lockscreen wallpaper updated to: {img_url}")
        return True
    except Exception as e:
        print(f"[!] Error setting lockscreen wallpaper via kwriteconfig6: {e}")
        return False

def set_sddm_wallpaper(image_path, crop_x=0.0, crop_y=0.0, crop_w=1.0, crop_h=1.0):
    """Crops and exports the image, then prompts for root permissions via pkexec to update SDDM."""
    try:
        temp_crop = export_cropped_image(image_path, crop_x, crop_y, crop_w, crop_h)
    except Exception as e:
        print(f"[!] Error exporting cropped image for SDDM: {e}")
        return False

    theme = get_active_sddm_theme()
    script_path = os.path.abspath(__file__)

    if not shutil.which("pkexec") and not shutil.which("sudo"):
        print("[!] No privilege escalation tool (pkexec/sudo) found.")
        return False

    cmd = ["pkexec", sys.executable, script_path, "--internal-sddm-apply", theme, temp_crop]
    try:
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode == 0:
            print(f"[✓] SDDM Login Screen wallpaper updated successfully.")
            return True
        else:
            err_msg = res.stderr.strip() or res.stdout.strip()
            print(f"[!] SDDM update cancelled or failed (exit code {res.returncode}): {err_msg}")
            return False
    except Exception as e:
        print(f"[!] Error executing privileged SDDM update: {e}")
        return False
    finally:
        if os.path.isfile(temp_crop):
            try:
                os.remove(temp_crop)
            except OSError:
                pass

def is_context_menu_enabled():
    return os.path.exists(SERVICEMENU_FILE)

def enable_context_menu():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    src_desktop = os.path.join(project_dir, "servicemenus", "plasma_crop_wallpaper.desktop")
    os.makedirs(SERVICEMENU_DIR, exist_ok=True)
    
    bin_path = os.path.abspath(__file__)
    with open(src_desktop, "r") as f:
        content = f.read()
    content = content.replace("@SET_WALLPAPER_BIN@", bin_path)
    with open(SERVICEMENU_FILE, "w") as f:
        f.write(content)
    os.chmod(SERVICEMENU_FILE, 0o755)
    
    # Disable default KDE wallpaperfileitemaction plugin in Dolphin context menu to avoid duplicate entries
    subprocess.run(["kwriteconfig6", "--file", "kservicemenurc", "--group", "Show", "--key", "wallpaperfileitemaction", "false"], capture_output=True)
    subprocess.run(["kbuildsycoca6", "--noincremental"], capture_output=True)
    print(f"[✓] Dolphin context menu enabled at: {SERVICEMENU_FILE} (original 'Set as Wallpaper' overridden)")
    return True

def disable_context_menu():
    if os.path.exists(SERVICEMENU_FILE):
        os.remove(SERVICEMENU_FILE)
    # Restore default KDE wallpaperfileitemaction plugin
    subprocess.run(["kwriteconfig6", "--file", "kservicemenurc", "--group", "Show", "--key", "wallpaperfileitemaction", "true"], capture_output=True)
    subprocess.run(["kbuildsycoca6", "--noincremental"], capture_output=True)
    print("[✓] Dolphin context menu disabled (original 'Set as Wallpaper' restored).")
    return True

def toggle_context_menu():
    if is_context_menu_enabled():
        disable_context_menu()
    else:
        enable_context_menu()

def launch_crop_dialog(image_path):
    from PyQt6.QtWidgets import QApplication
    from PyQt6.QtQuick import QQuickView
    from PyQt6.QtCore import QUrl, QObject, pyqtSlot, pyqtProperty, pyqtSignal

    raw_path = from_file_url(image_path)
    img_url = to_file_url(raw_path)

    app = QApplication(sys.argv)
    view = QQuickView()
    view.setTitle("Wallpaper Control")
    view.setResizeMode(QQuickView.ResizeMode.SizeRootObjectToView)

    class Bridge(QObject):
        contextMenuChanged = pyqtSignal()

        @pyqtSlot(float, float, float, float, str, bool, bool, bool, result=bool)
        def applyTargets(self, x, y, w, h, chosen_path, do_desktop, do_lockscreen, do_sddm):
            target = chosen_path if chosen_path else raw_path
            success = True
            if do_desktop:
                if not set_desktop_wallpaper(target, x, y, w, h):
                    success = False
            if do_lockscreen:
                if not set_lockscreen_wallpaper(target, x, y, w, h):
                    success = False
            if do_sddm:
                if not set_sddm_wallpaper(target, x, y, w, h):
                    success = False
            return success

        @pyqtSlot(float, float, float, float)
        @pyqtSlot(float, float, float, float, str)
        def applyDesktop(self, x, y, w, h, chosen_path=""):
            target = chosen_path if chosen_path else raw_path
            set_desktop_wallpaper(target, x, y, w, h)

        @pyqtSlot(float, float, float, float)
        @pyqtSlot(float, float, float, float, str)
        def applyLockscreen(self, x, y, w, h, chosen_path=""):
            target = chosen_path if chosen_path else raw_path
            set_lockscreen_wallpaper(target, x, y, w, h)

        @pyqtSlot(float, float, float, float)
        @pyqtSlot(float, float, float, float, str)
        def applyBoth(self, x, y, w, h, chosen_path=""):
            target = chosen_path if chosen_path else raw_path
            set_desktop_wallpaper(target, x, y, w, h)
            set_lockscreen_wallpaper(target, x, y, w, h)

        @pyqtSlot(float, float, float, float)
        @pyqtSlot(float, float, float, float, str)
        def applySDDM(self, x, y, w, h, chosen_path=""):
            target = chosen_path if chosen_path else raw_path
            set_sddm_wallpaper(target, x, y, w, h)

        @pyqtSlot(str, result=str)
        def getImageInfo(self, path):
            import json
            p = from_file_url(path)
            meta = get_image_metadata(p)
            meta["original_url"] = to_file_url(meta["original_path"])
            return json.dumps(meta)

        @pyqtSlot(str, result=str)
        def convertToSrgb(self, path):
            p = from_file_url(path)
            conv_p, _ = ensure_srgb_image(p)
            return to_file_url(conv_p)

        @pyqtSlot(bool)
        def setContextMenuEnabled(self, enabled):
            if enabled:
                enable_context_menu()
            else:
                disable_context_menu()
            self.contextMenuChanged.emit()

        @pyqtProperty(bool, notify=contextMenuChanged)
        def isContextMenuEnabled(self):
            return is_context_menu_enabled()

        @pyqtSlot()
        def closeWindow(self):
            app.quit()

    bridge = Bridge()
    view.rootContext().setContextProperty("wallpaperBridge", bridge)

    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_dir = os.path.dirname(script_dir)
    dialog_qml = os.path.join(project_dir, "contents", "ui", "CropDialogWindow.qml")

    view.setSource(QUrl.fromLocalFile(dialog_qml))
    root_obj = view.rootObject()
    if root_obj:
        root_obj.setProperty("cfg_Image", img_url)
        meta = get_image_metadata(raw_path)
        if meta.get("is_non_srgb"):
            root_obj.setProperty("isWideGamutImage", True)
            root_obj.setProperty("detectedProfileName", meta.get("profile_name", "Display P3"))

    from PyQt6.QtCore import QSize, QPoint
    from PyQt6.QtGui import QImageReader, QGuiApplication

    min_w = 850
    min_h = 650

    # Dynamically compute optimal dialog size based on screen geometry and image aspect ratio
    target_w = 1050
    target_h = 780
    screen = QGuiApplication.primaryScreen()
    screen_geo = screen.availableGeometry() if screen else None

    if screen_geo:
        max_w = int(screen_geo.width() * 0.90)
        max_h = int(screen_geo.height() * 0.88)
        min_w = min(min_w, max_w)
        min_h = min(min_h, max_h)

        if os.path.isfile(raw_path):
            reader = QImageReader(raw_path)
            img_size = reader.size()
            if img_size.isValid() and img_size.width() > 0 and img_size.height() > 0:
                aspect = img_size.width() / img_size.height()
                chrome_h = 200
                chrome_w = 40
                avail_w = max_w - chrome_w
                avail_h = max_h - chrome_h

                if aspect >= 1.0:
                    # Landscape image
                    canvas_h = min(680, avail_h)
                    canvas_w = int(canvas_h * aspect)
                    if canvas_w > avail_w:
                        canvas_w = avail_w
                        canvas_h = int(canvas_w / aspect)
                    target_w = max(min_w, min(max_w, canvas_w + chrome_w))
                    target_h = max(min_h, min(max_h, canvas_h + chrome_h))
                else:
                    # Portrait image (maximize canvas height, ensure toolbar fits)
                    canvas_h = min(740, avail_h)
                    canvas_w = int(canvas_h * aspect)
                    target_w = max(min_w, min(max_w, max(canvas_w + chrome_w, min_w)))
                    target_h = max(min_h, min(max_h, canvas_h + chrome_h))

    view.setMinimumSize(QSize(min_w, min_h))
    view.resize(target_w, target_h)

    # Center window on active desktop screen
    if screen_geo:
        x = screen_geo.x() + (screen_geo.width() - target_w) // 2
        y = screen_geo.y() + (screen_geo.height() - target_h) // 2
        view.setPosition(QPoint(x, y))

    view.show()
    sys.exit(app.exec())

def main():
    parser = argparse.ArgumentParser(description="Set Wallpaper Control wallpaper and manage Dolphin context menu in KDE Plasma 6")
    parser.add_argument("image", nargs="?", default="", help="Path to image file")
    parser.add_argument("--target", choices=["desktop", "lockscreen", "sddm", "both", "all"], default="desktop", help="Where to apply wallpaper (default: desktop)")
    parser.add_argument("--targets", nargs="+", choices=["desktop", "lockscreen", "sddm"], help="Multiple targets to apply wallpaper (e.g. --targets desktop sddm)")
    parser.add_argument("--crop", action="store_true", help="Launch interactive crop selector dialog")
    parser.add_argument("--convert-image", action="store_true", help="Convert non-sRGB image to sRGB cache and print URL")
    parser.add_argument("--get-info", action="store_true", help="Get JSON metadata about image and color profile")
    parser.add_argument("--enable-context-menu", action="store_true", help="Enable Dolphin context menu action")
    parser.add_argument("--disable-context-menu", action="store_true", help="Disable Dolphin context menu action")
    parser.add_argument("--toggle-context-menu", action="store_true", help="Toggle Dolphin context menu action")
    parser.add_argument("--status-context-menu", action="store_true", help="Print Dolphin context menu active status")
    parser.add_argument("--internal-sddm-apply", nargs=2, metavar=("THEME", "TEMP_IMAGE"), help=argparse.SUPPRESS)

    args = parser.parse_args()

    # Privileged internal helper invocation
    if args.internal_sddm_apply:
        theme, temp_img = args.internal_sddm_apply
        apply_sddm_root(theme, temp_img)
        return

    if args.enable_context_menu:
        enable_context_menu()
        return
    if args.disable_context_menu:
        disable_context_menu()
        return
    if args.toggle_context_menu:
        toggle_context_menu()
        return
    if args.status_context_menu:
        status = is_context_menu_enabled()
        print(f"Context menu enabled: {status}")
        return

    if not args.image:
        parser.print_help()
        return

    if args.get_info:
        import json
        raw_p = from_file_url(args.image)
        meta = get_image_metadata(raw_p)
        meta["original_url"] = to_file_url(meta["original_path"])
        print(json.dumps(meta))
        return

    if args.convert_image:
        raw_p = from_file_url(args.image)
        conv_p, converted = ensure_srgb_image(raw_p)
        print(to_file_url(conv_p))
        return

    if args.crop:
        launch_crop_dialog(args.image)
        return

    # Determine selected targets
    targets = set()
    if args.targets:
        targets = set(args.targets)
    elif args.target == "desktop":
        targets = {"desktop"}
    elif args.target == "lockscreen":
        targets = {"lockscreen"}
    elif args.target == "sddm":
        targets = {"sddm"}
    elif args.target == "both":
        targets = {"desktop", "lockscreen"}
    elif args.target == "all":
        targets = {"desktop", "lockscreen", "sddm"}

    if "desktop" in targets:
        set_desktop_wallpaper(args.image)
    if "lockscreen" in targets:
        set_lockscreen_wallpaper(args.image)
    if "sddm" in targets:
        set_sddm_wallpaper(args.image)

if __name__ == "__main__":
    main()
