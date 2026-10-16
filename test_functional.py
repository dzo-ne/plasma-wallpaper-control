#!/usr/bin/env python3
"""
Interactive / functional unit test for the interactive crop math logic
and property updates in config.qml.
"""

import sys
import os
from PyQt6.QtWidgets import QApplication
from PyQt6.QtQml import QQmlApplicationEngine, QQmlComponent
from PyQt6.QtCore import QUrl, QTimer
from PyQt6.QtGui import QImage, QColor, QPainter

def create_dummy_images():
    # 1. 16:9 3840x2160
    img1 = QImage(3840, 2160, QImage.Format.Format_ARGB32)
    img1.fill(QColor("#204a87"))
    p = QPainter(img1)
    p.setPen(QColor("#ffffff"))
    p.drawText(100, 200, "3840x2160 Sample")
    p.end()
    img1.save("/tmp/wallpaper_sample_16_9.png")

    # 2. Portrait 1080x1920
    img2 = QImage(1080, 1920, QImage.Format.Format_ARGB32)
    img2.fill(QColor("#ce5c00"))
    img2.save("/tmp/wallpaper_sample_portrait.png")

def test_config_logic():
    app = QApplication(sys.argv)
    create_dummy_images()
    engine = QQmlApplicationEngine()

    url = QUrl.fromLocalFile(os.path.abspath("contents/ui/config.qml"))
    component = QQmlComponent(engine, url)
    if component.isError():
        for err in component.errors():
            print(f"[!] Error: {err.toString()}")
        return False

    obj = component.create()
    if not obj:
        print("[!] Failed to create config object")
        return False

    print("\n--- Running Functional Logic Tests on config.qml ---")
    # Test setting image
    obj.setProperty("cfg_Image", "file:///tmp/wallpaper_sample_16_9.png")
    print(f"[✓] Set cfg_Image: {obj.property('cfg_Image')}")

    # Test initial crop properties
    print(f"[✓] Default Crop: X={obj.property('cfg_CropX')}, Y={obj.property('cfg_CropY')}, W={obj.property('cfg_CropWidth')}, H={obj.property('cfg_CropHeight')}")

    # Invoke fitToScreenCrop
    obj.fitToScreenCrop(False)
    print(f"[✓] After fitToScreenCrop(False): X={obj.property('cfg_CropX')}, Y={obj.property('cfg_CropY')}, W={obj.property('cfg_CropWidth')}, H={obj.property('cfg_CropHeight')}")

    # Invoke centerCurrentCrop
    obj.centerCurrentCrop()
    print(f"[✓] After centerCurrentCrop: X={obj.property('cfg_CropX')}, Y={obj.property('cfg_CropY')}")

    # Invoke resetCrop
    obj.resetCrop()
    print(f"[✓] After resetCrop: X={obj.property('cfg_CropX')}, Y={obj.property('cfg_CropY')}, W={obj.property('cfg_CropWidth')}, H={obj.property('cfg_CropHeight')}")
    assert obj.property('cfg_CropWidth') == 1.0
    assert obj.property('cfg_CropHeight') == 1.0

    # Test formatDisplayPath and toEncodedFileUrl
    encoded_sample = "file:///tmp/Sample%20%5Btag%5D%20%28artist%29%20%2308%20original.png"
    decoded_display = obj.formatDisplayPath(encoded_sample)
    assert decoded_display == "/tmp/Sample [tag] (artist) #08 original.png", f"Unexpected display path: {decoded_display}"
    re_encoded = obj.toEncodedFileUrl(decoded_display)
    assert QUrl(re_encoded).toLocalFile() == decoded_display
    print(f"[✓] Display path decoding & re-encoding passed: {decoded_display}")

    # Test that opening settings with existing config does not mutate any cfg_* properties (no false unsaved changes)
    from PyQt6.QtCore import QEventLoop, QTimer
    from PyQt6.QtGui import QImage
    test_img_path = "/tmp/test_wallpaper_unsaved_check.png"
    img = QImage(800, 1000, QImage.Format.Format_RGB32)
    img.fill(0x224466)
    img.save(test_img_path)

    initial_props = {
        "cfg_Image": f"file://{test_img_path}",
        "cfg_CropX": 0.1,
        "cfg_CropY": 0.2,
        "cfg_CropWidth": 0.8,
        "cfg_CropHeight": 0.6,
        "cfg_AspectRatioMode": 0,
        "cfg_ShowContextMenu": True,
    }
    loaded_obj = component.createWithInitialProperties(initial_props)
    assert loaded_obj is not None, "Failed to create config.qml with initial properties"
    loop = QEventLoop()
    QTimer.singleShot(250, loop.quit)
    loop.exec()
    for k, expected in initial_props.items():
        actual = loaded_obj.property(k)
        if isinstance(expected, float):
            assert abs(actual - expected) < 1e-9, f"{k} mutated on load: {expected} -> {actual}"
        else:
            assert actual == expected, f"{k} mutated on load: {expected} -> {actual}"
    os.remove(test_img_path)
    print("[✓] Initial config load preserves all cfg_* properties without false unsaved changes")

    print("[SUCCESS] All functional logic tests passed!")
    return True

if __name__ == "__main__":
    if test_config_logic():
        sys.exit(0)
    else:
        sys.exit(1)
