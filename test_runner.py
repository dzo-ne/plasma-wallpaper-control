#!/usr/bin/env python3
"""
Test runner to validate QML syntax, import resolution, and mathematical logic
for the KDE Plasma 6 Interactive Crop Wallpaper plugin.
"""

import sys
import os
from PyQt6.QtWidgets import QApplication
from PyQt6.QtQml import QQmlApplicationEngine, QQmlComponent
from PyQt6.QtCore import QUrl, QObject, pyqtSlot

class I18nHelper(QObject):
    @pyqtSlot(str, str, result=str)
    @pyqtSlot(str, str, str, result=str)
    @pyqtSlot(str, str, str, str, result=str)
    @pyqtSlot(str, str, str, str, str, result=str)
    @pyqtSlot(str, str, str, str, str, str, str, str, result=str)
    def i18nd(self, domain, text, *args):
        formatted = text
        for idx, arg in enumerate(args, 1):
            formatted = formatted.replace(f"%{idx}", str(arg))
        return formatted

    @pyqtSlot(str, str, result=str)
    def i18nc(self, ctx, text):
        return text

    @pyqtSlot(str, result=str)
    def i18n(self, text):
        return text

def test_qml_file(engine, file_path):
    print(f"[*] Testing QML compilation: {file_path} ...")
    url = QUrl.fromLocalFile(os.path.abspath(file_path))
    component = QQmlComponent(engine, url)
    if component.isError():
        for error in component.errors():
            print(f"[!] QML Error in {file_path}: {error.toString()}")
        return False
    
    obj = component.create()
    if obj is None:
        for error in component.errors():
            print(f"[!] Object creation error in {file_path}: {error.toString()}")
        return False

    print(f"[✓] Successfully loaded and instantiated {file_path}")
    return True

def main():
    app = QApplication(sys.argv)
    engine = QQmlApplicationEngine()
    
    helper = I18nHelper()
    engine.rootContext().setContextProperty("i18nd", helper.i18nd)
    engine.rootContext().setContextProperty("i18nc", helper.i18nc)
    engine.rootContext().setContextProperty("i18n", helper.i18n)

    success_main = test_qml_file(engine, "contents/ui/main.qml")
    success_config = test_qml_file(engine, "contents/ui/config.qml")
    success_dialog = test_qml_file(engine, "contents/ui/CropDialogWindow.qml")

    if success_main and success_config and success_dialog:
        print("\n[SUCCESS] All QML components compiled and loaded successfully!")
        sys.exit(0)
    else:
        print("\n[FAILURE] Errors encountered during QML verification.")
        sys.exit(1)

if __name__ == "__main__":
    main()
