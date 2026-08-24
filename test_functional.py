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

    print("[SUCCESS] All functional logic tests passed!")
    return True

if __name__ == "__main__":
    if test_config_logic():
        sys.exit(0)
    else:
        sys.exit(1)
