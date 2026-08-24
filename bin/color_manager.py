#!/usr/bin/env python3
"""
SPDX-FileCopyrightText: 2026 DZO <dragozeroone@hotmail.com>
SPDX-License-Identifier: GPL-3.0-or-later

Color Management Engine:
Detects non-sRGB ICC color profiles (e.g. Display P3, AdobeRGB, DCI-P3)
and non-destructively converts them to standard sRGB cached images
for accurate desktop wallpaper and crop preview rendering.
"""

import os
import io
import hashlib
from typing import Tuple, Dict, Any

try:
    from PIL import Image, ImageCms
    HAS_PIL = True
except ImportError:
    HAS_PIL = False


def get_cache_dir() -> str:
    """Returns the cache directory for converted wallpapers."""
    base_cache = os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache"))
    cache_dir = os.path.join(base_cache, "plasma-crop-wallpaper", "converted")
    os.makedirs(cache_dir, exist_ok=True)
    return cache_dir


def canonicalize_profile_name(prof_str: str) -> str:
    if not prof_str:
        return "Display P3"
    lower = prof_str.lower()
    if "p3" in lower or "smpte" in lower or "dci" in lower:
        return "Display P3"
    if "adobe" in lower:
        return "Adobe RGB"
    if "prophoto" in lower or "romm" in lower:
        return "ProPhoto RGB"
    if "2020" in lower or "rec2020" in lower:
        return "Rec. 2020"
    return prof_str


def detect_color_profile(image_path: str) -> dict:
    """
    Inspects an image's embedded ICC profile.
    Returns dict: {
        'has_icc': bool,
        'is_non_srgb': bool,
        'profile_name': str,
        'raw_description': str
    }
    """
    result = {
        "has_icc": False,
        "is_non_srgb": False,
        "profile_name": "sRGB",
        "raw_description": ""
    }

    if not HAS_PIL or not os.path.isfile(image_path):
        return result

    try:
        with Image.open(image_path) as img:
            icc = img.info.get("icc_profile")
            if not icc:
                return result

            result["has_icc"] = True
            try:
                src_profile = ImageCms.getOpenProfile(io.BytesIO(icc))
                desc = ImageCms.getProfileDescription(src_profile).strip()
                name = ImageCms.getProfileName(src_profile).strip()
                prof_str = desc or name
                result["raw_description"] = prof_str

                # Check if profile is standard sRGB
                lower_prof = prof_str.lower()
                is_srgb = ("srgb" in lower_prof or "iec61966-2.1" in lower_prof) and ("display" not in lower_prof and "p3" not in lower_prof and "smpte" not in lower_prof)

                if not is_srgb:
                    result["is_non_srgb"] = True
                    result["profile_name"] = canonicalize_profile_name(prof_str)
                else:
                    result["profile_name"] = "sRGB"
            except Exception:
                result["is_non_srgb"] = True
                result["profile_name"] = "Display P3"
    except Exception:
        pass

    return result


def get_active_wallpaper_paths() -> set:
    """Returns absolute paths of all currently referenced wallpapers."""
    active = set()
    cfg_paths = [
        os.path.expanduser("~/.config/kscreenlockerrc"),
        os.path.expanduser("~/.config/plasma-org.kde.plasma.desktop-appletsrc")
    ]
    for cfg in cfg_paths:
        if os.path.isfile(cfg):
            try:
                with open(cfg, "r", errors="ignore") as f:
                    for line in f:
                        if "Image=" in line or "usersWallpapers=" in line:
                            val = line.split("=", 1)[1].strip()
                            for item in val.split(","):
                                item = item.strip()
                                if item.startswith("file://"):
                                    item = item[7:]
                                if item:
                                    active.add(os.path.abspath(item))
            except Exception:
                pass
    return active


def clean_cache(current_session_file: str = ""):
    """
    Cleans up stale caches from previous sessions, retaining only currently applied
    wallpapers (desktop/lockscreen) and the active selection session's cache file.
    """
    cache_dir = get_cache_dir()
    if not os.path.isdir(cache_dir):
        return

    try:
        active = get_active_wallpaper_paths()
        if current_session_file:
            active.add(os.path.abspath(current_session_file))

        for entry in os.scandir(cache_dir):
            if entry.is_file() and entry.name.endswith("_srgb.png"):
                full_path = os.path.abspath(entry.path)
                if full_path not in active:
                    try:
                        os.remove(full_path)
                        json_sidecar = full_path[:-4] + ".json"
                        if os.path.isfile(json_sidecar):
                            os.remove(json_sidecar)
                    except OSError:
                        pass
    except Exception:
        pass


def get_image_metadata(image_path: str) -> Dict[str, Any]:
    """
    Returns metadata for either a raw source image or a converted cached image.
    """
    if not os.path.isfile(image_path):
        return {"is_non_srgb": False, "is_converted": False, "profile_name": "", "original_path": image_path}

    # Check if this is a cached sRGB image
    if image_path.endswith("_srgb.png"):
        orig_path = ""
        prof_name = ""

        # 1. Check sidecar JSON
        json_sidecar = image_path[:-4] + ".json"
        if os.path.isfile(json_sidecar):
            try:
                import json
                with open(json_sidecar, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    orig_path = data.get("original_path", "")
                    prof_name = data.get("profile_name", "")
            except Exception:
                pass

        # 2. Check embedded PNG text chunk
        if not orig_path and HAS_PIL:
            try:
                with Image.open(image_path) as img:
                    orig_path = img.text.get("original_path", "")
                    if not prof_name:
                        prof_name = img.text.get("profile_name", "")
            except Exception:
                pass

        # 3. Fallback: Search active wallpaper configs
        if not orig_path or not os.path.isfile(orig_path):
            active = get_active_wallpaper_paths()
            base_cached = os.path.basename(image_path).split("_")[0].lower()
            for cand in active:
                if not cand.endswith("_srgb.png") and os.path.isfile(cand):
                    cand_base = os.path.splitext(os.path.basename(cand))[0].lower().replace(" ", "").replace("-", "")
                    clean_cached = base_cached.replace("-", "")
                    if cand_base.startswith(clean_cached[:10]) or clean_cached.startswith(cand_base[:10]):
                        orig_path = cand
                        if not prof_name:
                            p_info = detect_color_profile(cand)
                            prof_name = p_info.get("profile_name", "")
                        break

        if not prof_name:
            prof_name = "Display P3 / Wide Gamut"

        return {
            "is_non_srgb": True,
            "is_converted": True,
            "profile_name": prof_name,
            "original_path": orig_path if (orig_path and os.path.isfile(orig_path)) else image_path
        }

    # Raw source image
    prof = detect_color_profile(image_path)
    return {
        "is_non_srgb": prof["is_non_srgb"],
        "is_converted": False,
        "profile_name": prof["profile_name"],
        "original_path": image_path
    }


def ensure_srgb_image(image_path: str) -> Tuple[str, bool]:
    """
    Checks if an image is non-sRGB, converts it to sRGB, and caches it.
    Returns (path_to_use, was_converted).
    """
    if not HAS_PIL or not os.path.isfile(image_path):
        return image_path, False

    info = detect_color_profile(image_path)
    if not info["is_non_srgb"]:
        return image_path, False

    try:
        # Generate cache key based on path, mtime, and file size
        st = os.stat(image_path)
        cache_key_data = f"{os.path.abspath(image_path)}:{st.st_mtime}:{st.st_size}".encode("utf-8")
        cache_hash = hashlib.sha256(cache_key_data).hexdigest()[:16]

        base_name = os.path.splitext(os.path.basename(image_path))[0]
        safe_name = "".join(c for c in base_name if c.isalnum() or c in ("-", "_")).strip() or "image"
        cached_file = os.path.join(get_cache_dir(), f"{safe_name}_{cache_hash}_srgb.png")
        cached_json = os.path.join(get_cache_dir(), f"{safe_name}_{cache_hash}_srgb.json")

        if os.path.isfile(cached_file) and os.path.getsize(cached_file) > 0:
            # Update access timestamp for LRU tracking
            try:
                os.utime(cached_file, None)
            except OSError:
                pass
            return cached_file, True

        # Perform ICC color space transform to sRGB
        with Image.open(image_path) as img:
            icc = img.info.get("icc_profile")
            if not icc:
                return image_path, False

            src_profile = ImageCms.getOpenProfile(io.BytesIO(icc))
            srgb_profile = ImageCms.createProfile("sRGB")

            # Convert image to RGB if necessary (e.g. RGBA)
            if img.mode == "RGBA":
                converted = ImageCms.profileToProfile(img, src_profile, srgb_profile, outputMode="RGBA")
            else:
                if img.mode != "RGB":
                    img = img.convert("RGB")
                converted = ImageCms.profileToProfile(img, src_profile, srgb_profile, outputMode="RGB")

            # Embed self-describing metadata into PNG chunks
            from PIL import PngImagePlugin
            png_meta = PngImagePlugin.PngInfo()
            png_meta.add_text("original_path", os.path.abspath(image_path))
            png_meta.add_text("profile_name", info["profile_name"])

            converted.save(cached_file, format="PNG", pnginfo=png_meta, optimize=False)

            # Save sidecar metadata linking cached image to original source and color profile
            try:
                import json
                with open(cached_json, "w", encoding="utf-8") as f:
                    json.dump({
                        "original_path": os.path.abspath(image_path),
                        "profile_name": info["profile_name"]
                    }, f)
            except Exception:
                pass

            # Clean up stale unapplied caches from previous sessions
            clean_cache(current_session_file=cached_file)

            return cached_file, True
    except Exception as e:
        print(f"[color_manager] Warning: Failed to convert color space: {e}")
        return image_path, False


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 1:
        test_path = sys.argv[1]
        print("Detecting profile for:", test_path)
        print("Profile Info:", detect_color_profile(test_path))
        conv_path, converted = ensure_srgb_image(test_path)
        print(f"Result Path: {conv_path} (Converted: {converted})")
