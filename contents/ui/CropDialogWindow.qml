/*
    SPDX-FileCopyrightText: 2026 DZO <dragozeroone@hotmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Window
import org.kde.kirigami as Kirigami

Rectangle {
    id: windowRoot
    implicitWidth: 1024
    implicitHeight: 768
    color: Kirigami.Theme.backgroundColor ? Kirigami.Theme.backgroundColor : "#232629"

    property string cfg_Image: ""
    property string rawImagePath: ""
    property string srgbImagePath: ""
    property bool useSrgbFix: false
    property string detectedProfileName: ""
    property bool isWideGamutImage: false
    property bool isConverting: false

    readonly property bool isConvertedImage: cfg_Image.includes("/plasma-crop-wallpaper/converted/") || cfg_Image.includes("_srgb.png")

    onCfg_ImageChanged: {
        if (cfg_Image.length > 0 && cfg_Image !== rawImagePath && cfg_Image !== srgbImagePath) {
            if (isConvertedImage) {
                useSrgbFix = true;
                srgbImagePath = cfg_Image;
                isWideGamutImage = true;
                if (typeof wallpaperBridge !== "undefined") {
                    try {
                        const meta = JSON.parse(wallpaperBridge.getImageInfo(cfg_Image));
                        if (meta.profile_name) detectedProfileName = meta.profile_name;
                        if (meta.original_url) rawImagePath = meta.original_url;
                    } catch(e) {}
                }
            } else {
                rawImagePath = cfg_Image;
                srgbImagePath = "";
                useSrgbFix = false;
                detectedProfileName = "";
                isWideGamutImage = false;
                if (typeof wallpaperBridge !== "undefined") {
                    try {
                        const meta = JSON.parse(wallpaperBridge.getImageInfo(cfg_Image));
                        if (meta.is_non_srgb) {
                            isWideGamutImage = true;
                            if (meta.profile_name) detectedProfileName = meta.profile_name;
                        }
                    } catch(e) {}
                }
            }
        }
    }

    Component.onCompleted: {
        if (typeof wallpaperBridge !== "undefined" && rawImagePath) {
            try {
                const meta = JSON.parse(wallpaperBridge.getImageInfo(rawImagePath));
                if (meta.is_non_srgb) {
                    windowRoot.isWideGamutImage = true;
                    if (meta.profile_name) {
                        windowRoot.detectedProfileName = meta.profile_name;
                    }
                }
            } catch(e) {}
        }
    }

    // Hidden probe for the raw source image to detect native color profile reliably
    Image {
        id: rawProbeImage
        source: rawImagePath
        visible: false
        asynchronous: true
        cache: true
        onStatusChanged: {
            if (status === Image.Ready && colorSpace) {
                const cs = colorSpace;
                let wide = false;
                let profName = "";
                if (cs.namedColorSpace && cs.namedColorSpace !== 1 && cs.namedColorSpace !== 2) {
                    wide = true;
                } else if (cs.transferFunction && cs.transferFunction !== 0 && cs.transferFunction !== 3) {
                    wide = true;
                } else if (cs.primaries && cs.primaries !== 0 && cs.primaries !== 1) {
                    wide = true;
                }
                if (wide) {
                    if (cs.namedColorSpace === 3) profName = "Adobe RGB";
                    else if (cs.namedColorSpace === 4) profName = "Display P3";
                    else if (cs.namedColorSpace === 5) profName = "ProPhoto RGB";
                    else if (cs.namedColorSpace === 6) profName = "Rec. 2020";
                    else if (cs.transferFunction === 2 && cs.gamma > 2.4) profName = "Display P3 / Wide Gamut";
                    else profName = "Display P3 / Wide Gamut";
                    windowRoot.isWideGamutImage = true;
                    if (windowRoot.detectedProfileName.length === 0) {
                        windowRoot.detectedProfileName = profName;
                    }
                }
            }
        }
    }

    property double cfg_CropX: 0.0
    property double cfg_CropY: 0.0
    property double cfg_CropWidth: 1.0
    property double cfg_CropHeight: 1.0
    property int cfg_AspectRatioMode: 0

    // Target Screen Aspect Ratio (Width / Height)
    readonly property real screenAspect: {
        const w = (Screen.width > 0) ? Screen.width : 1920;
        const h = (Screen.height > 0) ? Screen.height : 1080;
        return w / h;
    }

    // Non-sRGB / Wide Gamut Color Space Detection
    readonly property bool isNonSrgbProfile: isWideGamutImage || isConvertedImage || (srgbImagePath.length > 0)

    readonly property string colorProfileName: {
        if (detectedProfileName.length > 0) {
            const lower = detectedProfileName.toLowerCase();
            if (lower.includes("p3") || lower.includes("smpte") || lower.includes("dci")) return "Display P3";
            if (lower.includes("adobe")) return "Adobe RGB";
            if (lower.includes("prophoto") || lower.includes("romm")) return "ProPhoto RGB";
            if (lower.includes("2020") || lower.includes("rec2020")) return "Rec. 2020";
            return detectedProfileName;
        }
        return "Display P3";
    }

    // Active Aspect Ratio based on selected mode
    readonly property real targetAspect: {
        switch (cfg_AspectRatioMode) {
            case 0: return screenAspect;      // Screen Match
            case 1: return 0.0;               // Free Crop (unconstrained)
            case 2: return 16.0 / 9.0;        // 16:9
            case 3: return 16.0 / 10.0;       // 16:10
            case 4: return 21.0 / 9.0;        // 21:9 Ultrawide
            case 5: return 4.0 / 3.0;         // 4:3
            case 6: return 1.0;               // 1:1 Square
            case 7: return 9.0 / 16.0;        // 9:16 Portrait
            default: return screenAspect;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.mediumSpacing

        // -------------------------------------------------------------
        // Top Controls Bar
        // -------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Heading {
                text: "Crop & Pan"
                level: 2
                Layout.preferredWidth: Kirigami.Units.gridUnit * 8
            }

            Item { Layout.fillWidth: true } // spacer

            QQC2.Label {
                text: "Aspect Ratio:"
            }

            QQC2.ComboBox {
                id: aspectCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: [
                    { text: `Current Screen (${windowRoot.screenAspect.toFixed(2)}:1)`, mode: 0 },
                    { text: "Free", mode: 1 },
                    { text: "16:9", mode: 2 },
                    { text: "16:10", mode: 3 },
                    { text: "21:9", mode: 4 },
                    { text: "4:3", mode: 5 },
                    { text: "1:1", mode: 6 },
                    { text: "9:16", mode: 7 }
                ]
                textRole: "text"
                currentIndex: cfg_AspectRatioMode
                onActivated: {
                    cfg_AspectRatioMode = model[currentIndex].mode;
                    if (cfg_AspectRatioMode !== 1) {
                        enforceCurrentAspectRatio();
                    }
                }
            }

            QQC2.Button {
                text: "Fit Screen"
                icon.name: "zoom-fit-best"
                onClicked: fitToScreenCrop(false)
            }

            QQC2.Button {
                text: "Center"
                icon.name: "align-horizontal-center"
                onClicked: centerCurrentCrop()
            }

            QQC2.Button {
                text: "Reset"
                icon.name: "edit-reset"
                onClicked: resetCrop()
            }
        }

        // -------------------------------------------------------------
        // Full Edge-to-Edge Interactive Crop Canvas
        // -------------------------------------------------------------
        Rectangle {
            id: canvasFrame
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "#141414"
            radius: Kirigami.Units.smallSpacing
            border.color: Kirigami.Theme.separatorColor ? Kirigami.Theme.separatorColor : "#333333"
            border.width: 1
            clip: true

            // Base Raw Image Layer (Always loaded at bottom, never flickers or drops)
            Image {
                id: rawPreviewImage
                source: (rawImagePath.length > 0) ? rawImagePath : cfg_Image
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                visible: true
                smooth: true

                onStatusChanged: {
                    if (status === Image.Ready && implicitWidth > 0 && implicitHeight > 0) {
                        if (cfg_CropWidth <= 0.0 || cfg_CropHeight <= 0.0 || (cfg_CropWidth === 1.0 && cfg_CropHeight === 1.0 && cfg_CropX === 0.0 && cfg_CropY === 0.0)) {
                            fitToScreenCrop(true);
                        } else {
                            enforceCurrentAspectRatio();
                        }
                    }
                }
            }

            // Converted sRGB Image Layer (Instant atop raw image without transition or unload)
            Image {
                id: srgbPreviewImage
                source: srgbImagePath
                anchors.fill: parent
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: true
                visible: windowRoot.useSrgbFix && (srgbImagePath.length > 0) && (status === Image.Ready)
                smooth: true
            }

            // Initial Cold Load Animation Overlay (Only when no image is loaded yet)
            Rectangle {
                id: loadingOverlay
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)
                visible: (rawPreviewImage.status === Image.Loading) && (rawPreviewImage.status !== Image.Ready)
                z: 99

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Kirigami.Units.mediumSpacing

                    QQC2.BusyIndicator {
                        Layout.alignment: Qt.AlignHCenter
                        running: loadingOverlay.visible
                        implicitWidth: Kirigami.Units.gridUnit * 3
                        implicitHeight: Kirigami.Units.gridUnit * 3
                    }

                    QQC2.Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: "Loading image preview…"
                        font: Kirigami.Theme.defaultFont ? Kirigami.Theme.defaultFont : Qt.font({ pointSize: 10 })
                        color: "#ffffff"
                    }
                }
            }

            // Viewport Display Geometry Math Item
            Item {
                id: viewport
                anchors.fill: parent
                visible: rawPreviewImage.status === Image.Ready && rawPreviewImage.implicitWidth > 0

                readonly property real cw: canvasFrame.width
                readonly property real ch: canvasFrame.height
                readonly property real iw: rawPreviewImage.implicitWidth > 0 ? rawPreviewImage.implicitWidth : 1
                readonly property real ih: rawPreviewImage.implicitHeight > 0 ? rawPreviewImage.implicitHeight : 1

                readonly property real scaleFactor: Math.min(cw / iw, ch / ih)
                readonly property real dispW: iw * scaleFactor
                readonly property real dispH: ih * scaleFactor
                readonly property real dispX: (cw - dispW) / 2.0
                readonly property real dispY: (ch - dispH) / 2.0

                readonly property real boxX: dispX + cfg_CropX * dispW
                readonly property real boxY: dispY + cfg_CropY * dispH
                readonly property real boxW: cfg_CropWidth * dispW
                readonly property real boxH: cfg_CropHeight * dispH

                // Dark Mask: Top
                Rectangle {
                    x: viewport.dispX
                    y: viewport.dispY
                    width: viewport.dispW
                    height: Math.max(0, viewport.boxY - viewport.dispY)
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                // Dark Mask: Bottom
                Rectangle {
                    x: viewport.dispX
                    y: viewport.boxY + viewport.boxH
                    width: viewport.dispW
                    height: Math.max(0, (viewport.dispY + viewport.dispH) - (viewport.boxY + viewport.boxH))
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                // Dark Mask: Left
                Rectangle {
                    x: viewport.dispX
                    y: viewport.boxY
                    width: Math.max(0, viewport.boxX - viewport.dispX)
                    height: viewport.boxH
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                // Dark Mask: Right
                Rectangle {
                    x: viewport.boxX + viewport.boxW
                    y: viewport.boxY
                    width: Math.max(0, (viewport.dispX + viewport.dispW) - (viewport.boxX + viewport.boxW))
                    height: viewport.boxH
                    color: Qt.rgba(0, 0, 0, 0.65)
                }

                // Crop Box & Grid Overlay
                Rectangle {
                    id: cropBox
                    x: viewport.boxX
                    y: viewport.boxY
                    width: viewport.boxW
                    height: viewport.boxH
                    color: "transparent"
                    border.color: Kirigami.Theme.highlightColor ? Kirigami.Theme.highlightColor : "#3daee9"
                    border.width: 2

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        color: "transparent"
                        border.color: Qt.rgba(0, 0, 0, 0.4)
                        border.width: 1
                        z: -1
                    }

                    Rectangle { x: 0; y: parent.height / 3.0; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.3) }
                    Rectangle { x: 0; y: (parent.height * 2.0) / 3.0; width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.3) }
                    Rectangle { x: parent.width / 3.0; y: 0; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.3) }
                    Rectangle { x: (parent.width * 2.0) / 3.0; y: 0; width: 1; height: parent.height; color: Qt.rgba(1, 1, 1, 0.3) }

                    CornerHandle { anchors.horizontalCenter: parent.left; anchors.verticalCenter: parent.top }
                    CornerHandle { anchors.horizontalCenter: parent.right; anchors.verticalCenter: parent.top }
                    CornerHandle { anchors.horizontalCenter: parent.left; anchors.verticalCenter: parent.bottom }
                    CornerHandle { anchors.horizontalCenter: parent.right; anchors.verticalCenter: parent.bottom }
                }

                // Master Interaction MouseArea
                MouseArea {
                    id: masterInteractionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true

                    readonly property real hitRadius: Kirigami.Units.gridUnit * 1.5

                    property string activeMode: "NONE"
                    property real startMouseX: 0
                    property real startMouseY: 0
                    property real startCropX: 0
                    property real startCropY: 0
                    property real startCropW: 0
                    property real startCropH: 0

                    function detectZone(mx, my) {
                        const bx = viewport.boxX;
                        const by = viewport.boxY;
                        const bw = viewport.boxW;
                        const bh = viewport.boxH;
                        const hr2 = hitRadius * hitRadius;

                        if ((mx - bx) * (mx - bx) + (my - by) * (my - by) <= hr2) return "TL";
                        if ((mx - (bx + bw)) * (mx - (bx + bw)) + (my - by) * (my - by) <= hr2) return "TR";
                        if ((mx - bx) * (mx - bx) + (my - (by + bh)) * (my - (by + bh)) <= hr2) return "BL";
                        if ((mx - (bx + bw)) * (mx - (bx + bw)) + (my - (by + bh)) * (my - (by + bh)) <= hr2) return "BR";

                        if (mx >= bx && mx <= bx + bw && my >= by && my <= by + bh) return "DRAG";
                        return "NONE";
                    }

                    function updateCursor(zone) {
                        switch (zone) {
                            case "TL":
                            case "BR":
                                cursorShape = Qt.SizeFDiagCursor;
                                break;
                            case "TR":
                            case "BL":
                                cursorShape = Qt.SizeBDiagCursor;
                                break;
                            case "DRAG":
                                cursorShape = Qt.SizeAllCursor;
                                break;
                            default:
                                cursorShape = Qt.ArrowCursor;
                                break;
                        }
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed) {
                            const zone = detectZone(mouse.x, mouse.y);
                            updateCursor(zone);
                            return;
                        }

                        if (viewport.dispW <= 0 || viewport.dispH <= 0) return;

                        const deltaX = mouse.x - startMouseX;
                        const deltaY = mouse.y - startMouseY;

                        if (activeMode === "DRAG") {
                            const deltaNormX = deltaX / viewport.dispW;
                            const deltaNormY = deltaY / viewport.dispH;
                            cfg_CropX = Math.max(0.0, Math.min(1.0 - startCropW, startCropX + deltaNormX));
                            cfg_CropY = Math.max(0.0, Math.min(1.0 - startCropH, startCropY + deltaNormY));
                        } else if (activeMode === "TL" || activeMode === "TR" || activeMode === "BL" || activeMode === "BR") {
                            resizeCorner(activeMode, deltaX, deltaY, startCropX, startCropY, startCropW, startCropH);
                        }
                    }

                    onPressed: (mouse) => {
                        const zone = detectZone(mouse.x, mouse.y);
                        activeMode = zone;
                        updateCursor(zone);

                        startMouseX = mouse.x;
                        startMouseY = mouse.y;
                        startCropX = cfg_CropX;
                        startCropY = cfg_CropY;
                        startCropW = cfg_CropWidth;
                        startCropH = cfg_CropHeight;
                    }

                    onReleased: (mouse) => {
                        activeMode = "NONE";
                        const zone = detectZone(mouse.x, mouse.y);
                        updateCursor(zone);
                    }

                    onCanceled: () => {
                        activeMode = "NONE";
                        cursorShape = Qt.ArrowCursor;
                    }

                    property var cachedFlickable: null

                    function getFlickable() {
                        if (cachedFlickable) return cachedFlickable;
                        let p = masterInteractionArea.parent;
                        while (p) {
                            if (p.flickableItem) {
                                cachedFlickable = p.flickableItem;
                                return cachedFlickable;
                            }
                            if (p.contentY !== undefined && p.contentHeight !== undefined) {
                                cachedFlickable = p;
                                return cachedFlickable;
                            }
                            p = p.parent;
                        }
                        return null;
                    }

                    onWheel: (wheel) => {
                        const f = getFlickable();
                        if (f) {
                            const dy = wheel.pixelDelta.y !== 0 ? wheel.pixelDelta.y : wheel.angleDelta.y;
                            const step = wheel.pixelDelta.y !== 0 ? dy : (dy / 120.0) * (Kirigami.Units.gridUnit * 3);
                            const maxY = Math.max(0, f.contentHeight - f.height);
                            f.contentY = Math.max(0, Math.min(maxY, f.contentY - step));
                            wheel.accepted = true;
                        } else {
                            wheel.accepted = false;
                        }
                    }
                }
            }
        }

        // -------------------------------------------------------------
        // Bottom Status & Action Bar
        // -------------------------------------------------------------
        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Kirigami.Theme.separatorColor ? Kirigami.Theme.separatorColor : Qt.rgba(1, 1, 1, 0.15)
        }

        // Non-sRGB / Wide Gamut Color Space Warning Row
        RowLayout {
            Layout.fillWidth: true
            visible: isNonSrgbProfile || (srgbImagePath.length > 0)
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "dialog-warning"
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
                color: Kirigami.Theme.neutralTextColor ? Kirigami.Theme.neutralTextColor : "#e5a50a"
            }

            QQC2.Label {
                Layout.fillWidth: true
                text: `Note: Image uses ${colorProfileName || "Display P3"} color profile. Colors may appear desaturated without sRGB conversion.`
                font: Kirigami.Theme.smallFont ? Kirigami.Theme.smallFont : Qt.font({ pointSize: 9 })
                color: Kirigami.Theme.neutralTextColor ? Kirigami.Theme.neutralTextColor : "#e5a50a"
                wrapMode: Text.WordWrap
            }

            QQC2.BusyIndicator {
                running: isConverting
                visible: isConverting
                implicitWidth: Kirigami.Units.iconSizes.small
                implicitHeight: Kirigami.Units.iconSizes.small
            }

            QQC2.Switch {
                id: srgbToggle
                text: "sRGB"
                checked: windowRoot.useSrgbFix
                onClicked: {
                    windowRoot.useSrgbFix = checked;
                    if (checked) {
                        if (!windowRoot.srgbImagePath && typeof wallpaperBridge !== "undefined") {
                            windowRoot.srgbImagePath = wallpaperBridge.convertToSrgb(windowRoot.rawImagePath);
                        }
                        if (windowRoot.srgbImagePath && windowRoot.srgbImagePath.length > 0) {
                            windowRoot.cfg_Image = windowRoot.srgbImagePath;
                        }
                    } else {
                        if (windowRoot.rawImagePath && windowRoot.rawImagePath.length > 0) {
                            windowRoot.cfg_Image = windowRoot.rawImagePath;
                        }
                    }
                }
            }
        }

        // Status & Action Buttons Row
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.Label {
                text: {
                    if (rawPreviewImage.status !== Image.Ready || rawPreviewImage.implicitWidth <= 0) return "";
                    const origW = rawPreviewImage.implicitWidth;
                    const origH = rawPreviewImage.implicitHeight;
                    const cropPixW = Math.round(cfg_CropWidth * origW);
                    const cropPixH = Math.round(cfg_CropHeight * origH);
                    const aspectStr = (cropPixW / Math.max(1, cropPixH)).toFixed(2);
                    return `Original: ${origW}×${origH} | Crop: ${cropPixW}×${cropPixH} (${aspectStr}:1)`;
                }
                font: Kirigami.Theme.smallFont ? Kirigami.Theme.smallFont : Qt.font({ pointSize: 9 })
                color: Kirigami.Theme.disabledTextColor ? Kirigami.Theme.disabledTextColor : "#888888"
            }

            Item { Layout.fillWidth: true } // spacer

            QQC2.Button {
                text: "Cancel"
                onClicked: {
                    if (typeof wallpaperBridge !== "undefined") {
                        wallpaperBridge.closeWindow();
                    }
                }
            }

            QQC2.Button {
                text: "Set on Desktop"
                icon.name: "preferences-desktop-wallpaper"
                onClicked: {
                    if (typeof wallpaperBridge !== "undefined") {
                        wallpaperBridge.applyDesktop(cfg_CropX, cfg_CropY, cfg_CropWidth, cfg_CropHeight, (useSrgbFix && srgbImagePath.length > 0) ? srgbImagePath : rawImagePath);
                        wallpaperBridge.closeWindow();
                    }
                }
            }

            QQC2.Button {
                text: "Set on Lockscreen"
                icon.name: "system-lock-screen"
                onClicked: {
                    if (typeof wallpaperBridge !== "undefined") {
                        wallpaperBridge.applyLockscreen(cfg_CropX, cfg_CropY, cfg_CropWidth, cfg_CropHeight, (useSrgbFix && srgbImagePath.length > 0) ? srgbImagePath : rawImagePath);
                        wallpaperBridge.closeWindow();
                    }
                }
            }

            QQC2.Button {
                text: "Set on Both"
                icon.name: "dialog-ok-apply"
                highlighted: true
                onClicked: {
                    if (typeof wallpaperBridge !== "undefined") {
                        wallpaperBridge.applyBoth(cfg_CropX, cfg_CropY, cfg_CropWidth, cfg_CropHeight, (useSrgbFix && srgbImagePath.length > 0) ? srgbImagePath : rawImagePath);
                        wallpaperBridge.closeWindow();
                    }
                }
            }
        }
    }

    // -------------------------------------------------------------
    // Corner Handle Component
    // -------------------------------------------------------------
    component CornerHandle : Rectangle {
        id: handle
        width: Kirigami.Units.gridUnit * 0.9
        height: Kirigami.Units.gridUnit * 0.9
        radius: width / 2.0
        color: Kirigami.Theme.highlightColor ? Kirigami.Theme.highlightColor : "#3daee9"
        border.color: "#ffffff"
        border.width: 1.5
    }

    // -------------------------------------------------------------
    // Math & Geometry Helper Functions
    // -------------------------------------------------------------
    function fitToScreenCrop(centerToImage) {
        centerToImage = !!centerToImage;
        if (rawPreviewImage.implicitWidth <= 0 || rawPreviewImage.implicitHeight <= 0) return;
        const iw = rawPreviewImage.implicitWidth;
        const ih = rawPreviewImage.implicitHeight;
        const ratio = targetAspect > 0.0 ? targetAspect : (iw / ih);

        const imgRatio = iw / ih;
        let wn = 1.0;
        let hn = 1.0;

        if (imgRatio > ratio) {
            hn = 1.0;
            wn = (ih * ratio) / iw;
        } else {
            wn = 1.0;
            hn = (iw / ratio) / ih;
        }

        wn = Math.max(0.01, Math.min(1.0, wn));
        hn = Math.max(0.01, Math.min(1.0, hn));

        let newU = (1.0 - wn) / 2.0;
        let newV = (1.0 - hn) / 2.0;

        if (!centerToImage && cfg_CropWidth > 0.0 && cfg_CropHeight > 0.0) {
            const currentCenterX = cfg_CropX + cfg_CropWidth / 2.0;
            const currentCenterY = cfg_CropY + cfg_CropHeight / 2.0;
            newU = Math.max(0.0, Math.min(1.0 - wn, currentCenterX - wn / 2.0));
            newV = Math.max(0.0, Math.min(1.0 - hn, currentCenterY - hn / 2.0));
        }

        cfg_CropWidth = wn;
        cfg_CropHeight = hn;
        cfg_CropX = newU;
        cfg_CropY = newV;
    }

    function centerCurrentCrop() {
        cfg_CropX = Math.max(0.0, Math.min(1.0 - cfg_CropWidth, (1.0 - cfg_CropWidth) / 2.0));
        cfg_CropY = Math.max(0.0, Math.min(1.0 - cfg_CropHeight, (1.0 - cfg_CropHeight) / 2.0));
    }

    function resetCrop() {
        cfg_AspectRatioMode = 0;
        fitToScreenCrop(true);
    }

    function enforceCurrentAspectRatio() {
        if (targetAspect <= 0.0 || rawPreviewImage.implicitWidth <= 0 || rawPreviewImage.implicitHeight <= 0) return;
        const iw = rawPreviewImage.implicitWidth;
        const ih = rawPreviewImage.implicitHeight;
        const ratio = targetAspect;
        const normRatio = ratio * (ih / iw);

        let wn = cfg_CropWidth;
        let hn = wn / normRatio;

        if (hn > 1.0) {
            hn = 1.0;
            wn = hn * normRatio;
        }
        if (wn > 1.0) {
            wn = 1.0;
            hn = wn / normRatio;
        }

        cfg_CropWidth = wn;
        cfg_CropHeight = hn;
        cfg_CropX = Math.max(0.0, Math.min(1.0 - wn, cfg_CropX));
        cfg_CropY = Math.max(0.0, Math.min(1.0 - hn, cfg_CropY));
    }

    function resizeCorner(corner, deltaDispX, deltaDispY, startU, startV, startW, startH) {
        if (viewport.dispW <= 0 || viewport.dispH <= 0) return;

        const dispX = viewport.dispX;
        const dispY = viewport.dispY;
        const dispW = viewport.dispW;
        const dispH = viewport.dispH;

        const curBoxX = dispX + startU * dispW;
        const curBoxY = dispY + startV * dispH;
        const curBoxW = startW * dispW;
        const curBoxH = startH * dispH;

        const minW = 24;
        const ratio = targetAspect;

        let newW = curBoxW;
        let newH = curBoxH;
        let newX = curBoxX;
        let newY = curBoxY;

        if (corner === 'BR') {
            const maxW = dispX + dispW - curBoxX;
            const maxH = dispY + dispH - curBoxY;
            newW = Math.max(minW, Math.min(maxW, curBoxW + deltaDispX));
            if (ratio > 0.0) {
                newH = newW / ratio;
                if (newH > maxH) {
                    newH = maxH;
                    newW = newH * ratio;
                }
            } else {
                newH = Math.max(minW, Math.min(maxH, curBoxH + deltaDispY));
            }
        } else if (corner === 'BL') {
            const anchorX = curBoxX + curBoxW;
            const maxW = anchorX - dispX;
            const maxH = dispY + dispH - curBoxY;
            newW = Math.max(minW, Math.min(maxW, curBoxW - deltaDispX));
            if (ratio > 0.0) {
                newH = newW / ratio;
                if (newH > maxH) {
                    newH = maxH;
                    newW = newH * ratio;
                }
            } else {
                newH = Math.max(minW, Math.min(maxH, curBoxH + deltaDispY));
            }
            newX = anchorX - newW;
        } else if (corner === 'TR') {
            const anchorY = curBoxY + curBoxH;
            const maxW = dispX + dispW - curBoxX;
            const maxH = anchorY - dispY;
            newW = Math.max(minW, Math.min(maxW, curBoxW + deltaDispX));
            if (ratio > 0.0) {
                newH = newW / ratio;
                if (newH > maxH) {
                    newH = maxH;
                    newW = newH * ratio;
                }
            } else {
                newH = Math.max(minW, Math.min(maxH, curBoxH - deltaDispY));
            }
            newY = anchorY - newH;
        } else if (corner === 'TL') {
            const anchorX = curBoxX + curBoxW;
            const anchorY = curBoxY + curBoxH;
            const maxW = anchorX - dispX;
            const maxH = anchorY - dispY;
            newW = Math.max(minW, Math.min(maxW, curBoxW - deltaDispX));
            if (ratio > 0.0) {
                newH = newW / ratio;
                if (newH > maxH) {
                    newH = maxH;
                    newW = newH * ratio;
                }
            } else {
                newH = Math.max(minW, Math.min(maxH, curBoxH - deltaDispY));
            }
            newX = anchorX - newW;
            newY = anchorY - newH;
        }

        newW = Math.max(minW, newW);
        newH = Math.max(minW, newH);

        const newNormW = newW / dispW;
        const newNormH = newH / dispH;
        const newNormX = (newX - dispX) / dispW;
        const newNormY = (newY - dispY) / dispH;

        cfg_CropWidth = Math.max(0.01, Math.min(1.0, newNormW));
        cfg_CropHeight = Math.max(0.01, Math.min(1.0, newNormH));
        cfg_CropX = Math.max(0.0, Math.min(1.0 - cfg_CropWidth, newNormX));
        cfg_CropY = Math.max(0.0, Math.min(1.0 - cfg_CropHeight, newNormY));
    }
}
