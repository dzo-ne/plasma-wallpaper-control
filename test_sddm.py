#!/usr/bin/env python3
"""
Unit and functional tests for SDDM export, multi-target wallpaper setting logic,
and safe URL/path conversions (handling special characters like '#', '?', spaces).
"""

import os
import sys
import tempfile
from PIL import Image

# Import from bin/
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "bin"))
from set_wallpaper import export_cropped_image, get_active_sddm_theme, to_file_url, from_file_url

def test_url_handling():
    print("[*] Testing to_file_url() and from_file_url() special character handling ...")
    from PyQt6.QtCore import QUrl

    test_paths = [
        "/tmp/Wallpapers/Collection/2026-08-25 -- Photo Sample #08 -- image.jpg",
        "/tmp/wallpaper sample with spaces #01.png",
        "/tmp/question?mark#hash.jpg",
        "/tmp/percentage %20 literal % test.png",
        "/tmp/壁紙/japanese_wallpaper #03.png",
        "/tmp/test+plus&amp.jpg",
    ]

    for p in test_paths:
        url = to_file_url(p)
        assert ("%23" in url) if ("#" in p) else True
        assert " " not in url
        # Verify Qt parses URL correctly without fragment truncation
        qurl = QUrl(url)
        assert qurl.toLocalFile() == p, f"QUrl.toLocalFile() mismatch: '{qurl.toLocalFile()}' != '{p}'"
        # Verify from_file_url roundtrip
        dec = from_file_url(url)
        assert dec == p, f"from_file_url() mismatch: '{dec}' != '{p}'"
        # Verify idempotence
        assert to_file_url(url) == url

    # Test raw paths and unencoded file:// URLs
    raw = "/tmp/foo #08.jpg"
    assert from_file_url(raw) == raw
    assert from_file_url("file:///tmp/foo #08.jpg") == raw

    # Test export_cropped_image on file path with #
    special_img_path = os.path.join(tempfile.gettempdir(), "test #08 -- crop.png")
    test_img = Image.new("RGB", (200, 200), color=(0, 0, 255))
    test_img.save(special_img_path)
    try:
        # Pass as encoded file URL
        out = export_cropped_image(to_file_url(special_img_path), 0.0, 0.0, 1.0, 1.0)
        assert os.path.isfile(out)
        os.remove(out)
        # Pass as raw path
        out2 = export_cropped_image(special_img_path, 0.0, 0.0, 1.0, 1.0)
        assert os.path.isfile(out2)
        os.remove(out2)
        print("  [✓] URL encoding and special character export passed")
    finally:
        if os.path.isfile(special_img_path):
            os.remove(special_img_path)

def test_export_cropped_image():
    print("[*] Testing export_cropped_image() ...")
    # Create test image: 1000x500 (2:1 aspect)
    test_img = Image.new("RGB", (1000, 500), color=(255, 0, 0))
    # Fill quadrants with different colors
    for x in range(500, 1000):
        for y in range(0, 500):
            test_img.putpixel((x, y), (0, 255, 0))

    src_tmp = tempfile.mktemp(suffix=".png")
    test_img.save(src_tmp)

    try:
        # 1. Full frame crop (0, 0, 1, 1)
        out1 = export_cropped_image(src_tmp, 0.0, 0.0, 1.0, 1.0)
        with Image.open(out1) as img1:
            assert img1.size == (1000, 500), f"Expected (1000, 500), got {img1.size}"
        os.remove(out1)
        print("  [✓] Full frame crop passed")

        # 2. Right half crop (0.5, 0.0, 0.5, 1.0)
        out2 = export_cropped_image(src_tmp, 0.5, 0.0, 0.5, 1.0)
        with Image.open(out2) as img2:
            assert img2.size == (500, 500), f"Expected (500, 500), got {img2.size}"
            # Check color is green
            assert img2.getpixel((10, 10)) == (0, 255, 0)
        os.remove(out2)
        print("  [✓] Sub-rectangle crop and color passed")

        # 3. Clamping boundary checks
        out3 = export_cropped_image(src_tmp, -0.2, -0.2, 1.5, 1.5)
        with Image.open(out3) as img3:
            assert img3.size == (1000, 500), f"Expected (1000, 500), got {img3.size}"
        os.remove(out3)
        print("  [✓] Clamping boundary check passed")

    finally:
        if os.path.isfile(src_tmp):
            os.remove(src_tmp)

def test_sddm_theme_detection():
    print("[*] Testing get_active_sddm_theme() ...")
    theme = get_active_sddm_theme()
    print(f"  [✓] Detected active SDDM theme: '{theme}'")
    assert isinstance(theme, str) and len(theme) > 0

def main():
    test_url_handling()
    test_export_cropped_image()
    test_sddm_theme_detection()
    print("\n[SUCCESS] All SDDM backend and URL unit tests passed!")

if __name__ == "__main__":
    main()
