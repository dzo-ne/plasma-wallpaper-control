/*
    SPDX-FileCopyrightText: 2026 DZO <dragozeroone@hotmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtQuick.Dialogs as QtDialogs
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasma5support as Plasma5Support

ColumnLayout {
    id: root
    spacing: Kirigami.Units.smallSpacing

    // KConfigXT Property Bindings
    property string cfg_Image: ""
    property string rawImagePath: ""
    property string srgbImagePath: ""
    property bool useSrgbFix: false
    property string detectedProfileName: ""
    property bool isWideGamutImage: false
    property bool isConverting: false

    readonly property bool isConvertedImage: cfg_Image.includes("/plasma-crop-wallpaper/converted/") || cfg_Image.includes("_srgb.png")

    function handleImageChange(newImg) {
        if (!newImg || newImg.length === 0) return;
        const isConverted = newImg.includes("/plasma-crop-wallpaper/converted/") || newImg.includes("_srgb.png");
        if (isConverted) {
            srgbImagePath = newImg;
            useSrgbFix = true;
            isWideGamutImage = true;
            queryImageMetadata(newImg);
        } else {
            rawImagePath = newImg;
            srgbImagePath = "";
            useSrgbFix = false;
            detectedProfileName = "";
            isWideGamutImage = false;
            queryImageMetadata(newImg);
        }
    }

    onCfg_ImageChanged: {
        if (cfg_Image.length > 0 && cfg_Image !== rawImagePath && cfg_Image !== srgbImagePath) {
            handleImageChange(cfg_Image);
        }
    }

    Component.onCompleted: {
        handleImageChange(cfg_Image);
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
                    root.isWideGamutImage = true;
                    if (root.detectedProfileName.length === 0) {
                        root.detectedProfileName = profName;
                    }
                }
            }
        }
    }

    property double cfg_CropX: 0.0
    property double cfg_CropY: 0.0
    property double cfg_CropWidth: 1.0
    property double cfg_CropHeight: 1.0
    property bool cfg_LockScreenAspect: true
    property int cfg_AspectRatioMode: 0
    property alias cfg_Color: colorButton.color
    property int cfg_FillMode: 1
    property bool cfg_ShowContextMenu: true
    property alias formLayout: topFormLayout

    // Target Screen Aspect Ratio (Width / Height)
    readonly property real screenAspect: {
        const w = (Screen.width > 0) ? Screen.width : 1920;
        const h = (Screen.height > 0) ? Screen.height : 1080;
        return w / h;
    }

    // Cache last valid image aspect ratio to prevent canvas height collapse/jump during reloads
    property real lastImageAspect: 1.7777777777777777

    readonly property real canvasHeight: {
        const aspect = (rawPreviewImage.status === Image.Ready && rawPreviewImage.implicitWidth > 0 && rawPreviewImage.implicitHeight > 0)
            ? (rawPreviewImage.implicitWidth / rawPreviewImage.implicitHeight)
            : root.lastImageAspect;
        if (aspect < 1.0) {
            const portraitFactor = Math.min(1.0, (1.0 - aspect) / 0.5);
            return Math.round(Kirigami.Units.gridUnit * (24 + 12 * portraitFactor));
        }
        return Math.round(Kirigami.Units.gridUnit * 24);
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

    // File Picker Dialog
    QtDialogs.FileDialog {
        id: fileDialog
        title: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Select Wallpaper Image")
        nameFilters: [
            i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Image Files (*.png *.jpg *.jpeg *.webp *.avif *.bmp *.svg)"),
            i18nd("plasma_wallpaper_org.kde.cropwallpaper", "All Files (*)")
        ]
        onAccepted: {
            if (fileDialog.selectedFile) {
                const pathStr = fileDialog.selectedFile.toString();
                rawImagePath = pathStr;
                srgbImagePath = "";
                useSrgbFix = false;
                detectedProfileName = "";
                isWideGamutImage = false;
                cfg_Image = pathStr;
                // Automatically initialize crop to fill screen aspect ratio when a new image is picked
                fitToScreenCrop(true);
            }
        }
    }

    // -------------------------------------------------------------
    // Top Form Controls (Labels + Inputs)
    // -------------------------------------------------------------
    Kirigami.FormLayout {
        id: topFormLayout
        Layout.fillWidth: true
        twinFormLayouts: (typeof parentLayout !== "undefined") ? parentLayout : null

        // Dolphin Context Menu Integration Toggle
        QQC2.CheckBox {
            id: contextMenuCheckbox
            Kirigami.FormData.label: (typeof i18nd !== "undefined")
                ? i18nd("plasma_wallpaper_org.kde.cropwallpaper", "File manager:")
                : "File manager:"
            text: (typeof i18nd !== "undefined")
                ? i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Show \"Crop & Pan as Wallpaper…\" in Dolphin context menu")
                : "Show \"Crop & Pan as Wallpaper…\" in Dolphin context menu"
            checked: cfg_ShowContextMenu
            onToggled: {
                cfg_ShowContextMenu = checked;
            }
        }

        // Image Selection Row
        RowLayout {
            Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Image:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.TextField {
                id: pathField
                Layout.fillWidth: true
                text: (rawImagePath.length > 0) ? rawImagePath : cfg_Image
                placeholderText: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Choose an image file...")
                onEditingFinished: {
                    if (text !== rawImagePath && text !== cfg_Image) {
                        rawImagePath = text;
                        srgbImagePath = "";
                        useSrgbFix = false;
                        detectedProfileName = "";
                        isWideGamutImage = false;
                        cfg_Image = text;
                    }
                }
            }

            QQC2.Button {
                text: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Browse…")
                icon.name: "document-open"
                onClicked: fileDialog.open()
            }
        }

        // Background Matte Color
        KQuickControls.ColorButton {
            id: colorButton
            Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Background color:")
            dialogTitle: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Select Background Matte Color")
        }

        // Aspect Ratio & Sizing Controls
        RowLayout {
            Kirigami.FormData.label: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Crop Aspect Ratio:")
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            QQC2.ComboBox {
                id: aspectCombo
                Layout.preferredWidth: Kirigami.Units.gridUnit * 12
                model: [
                    { text: (typeof i18nd !== "undefined" ? i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Current Screen (%1:1)", root.screenAspect.toFixed(2)) : `Current Screen (${root.screenAspect.toFixed(2)}:1)`), mode: 0 },
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
                text: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Fit Screen")
                icon.name: "zoom-fit-best"
                onClicked: fitToScreenCrop(false)
            }

            QQC2.Button {
                text: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Center")
                icon.name: "align-horizontal-center"
                onClicked: centerCurrentCrop()
            }

            QQC2.Button {
                text: i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Reset")
                icon.name: "edit-reset"
                onClicked: resetCrop()
            }
        }
    }

    // -------------------------------------------------------------
    // Full-Width Interactive Crop Canvas Area
    // -------------------------------------------------------------
    Rectangle {
        id: canvasFrame
        Layout.fillWidth: true
        Layout.preferredHeight: root.canvasHeight
        implicitHeight: root.canvasHeight
        height: root.canvasHeight
        color: "#181818"
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
                    root.lastImageAspect = implicitWidth / implicitHeight;
                    // If dimensions are uninitialized, fit to screen
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
            visible: root.useSrgbFix && (srgbImagePath.length > 0) && (status === Image.Ready)
            smooth: true
        }

        // Empty state placeholder (when no image chosen)
        ColumnLayout {
            anchors.centerIn: parent
            visible: rawPreviewImage.status !== Image.Ready && rawPreviewImage.status !== Image.Loading && !isConverting
            spacing: Kirigami.Units.largeSpacing

            Kirigami.Icon {
                Layout.alignment: Qt.AlignHCenter
                source: "preferences-desktop-wallpaper"
                implicitWidth: Kirigami.Units.iconSizes.huge
                implicitHeight: Kirigami.Units.iconSizes.huge
                color: Kirigami.Theme.disabledTextColor ? Kirigami.Theme.disabledTextColor : "#888888"
            }

            QQC2.Label {
                Layout.alignment: Qt.AlignHCenter
                text: (typeof i18nd !== "undefined")
                    ? i18nd("plasma_wallpaper_org.kde.cropwallpaper", "No image selected. Click 'Browse' to choose a wallpaper.")
                    : "No image selected. Click 'Browse' to choose a wallpaper."
                color: Kirigami.Theme.disabledTextColor ? Kirigami.Theme.disabledTextColor : "#888888"
            }
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
                    text: (typeof i18nd !== "undefined")
                        ? i18nd("plasma_wallpaper_org.kde.cropwallpaper", "Loading image preview…")
                        : "Loading image preview…"
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

            // Canvas & Natural Image Dimensions
            readonly property real cw: canvasFrame.width
            readonly property real ch: canvasFrame.height
            readonly property real iw: rawPreviewImage.implicitWidth > 0 ? rawPreviewImage.implicitWidth : 1
            readonly property real ih: rawPreviewImage.implicitHeight > 0 ? rawPreviewImage.implicitHeight : 1

                // PreserveAspectFit scale factor
                readonly property real scaleFactor: Math.min(cw / iw, ch / ih)
                readonly property real dispW: iw * scaleFactor
                readonly property real dispH: ih * scaleFactor
                readonly property real dispX: (cw - dispW) / 2.0
                readonly property real dispY: (ch - dispH) / 2.0

                // Crop box in canvas display coordinates
                readonly property real boxX: dispX + cfg_CropX * dispW
                readonly property real boxY: dispY + cfg_CropY * dispH
                readonly property real boxW: cfg_CropWidth * dispW
                readonly property real boxH: cfg_CropHeight * dispH

                // Background Canvas Wheel Zoom Handler
                MouseArea {
                    anchors.fill: parent
                    z: -1
                    acceptedButtons: Qt.NoButton
                    onWheel: (wheel) => {
                        const zoomStep = wheel.angleDelta.y > 0 ? 0.94 : 1.06;
                        const mouseNormX = (wheel.x - viewport.dispX) / viewport.dispW;
                        const mouseNormY = (wheel.y - viewport.dispY) / viewport.dispH;
                        zoomCrop(zoomStep, mouseNormX, mouseNormY);
                    }
                }

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

                // ---------------------------------------------------------
                // Visual Crop Rectangle & Grid Overlay (Presentation Only)
                // ---------------------------------------------------------
                Rectangle {
                    id: cropBox
                    x: viewport.boxX
                    y: viewport.boxY
                    width: viewport.boxW
                    height: viewport.boxH
                    color: "transparent"
                    border.color: Kirigami.Theme.highlightColor ? Kirigami.Theme.highlightColor : "#3daee9"
                    border.width: 2

                    // Secondary contrast outer border
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: -1
                        color: "transparent"
                        border.color: Qt.rgba(0, 0, 0, 0.4)
                        border.width: 1
                        z: -1
                    }

                    // Rule-of-Thirds Grid: Horizontal 1
                    Rectangle {
                        x: 0
                        y: parent.height / 3.0
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }

                    // Rule-of-Thirds Grid: Horizontal 2
                    Rectangle {
                        x: 0
                        y: (parent.height * 2.0) / 3.0
                        width: parent.width
                        height: 1
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }

                    // Rule-of-Thirds Grid: Vertical 1
                    Rectangle {
                        x: parent.width / 3.0
                        y: 0
                        width: 1
                        height: parent.height
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }

                    // Rule-of-Thirds Grid: Vertical 2
                    Rectangle {
                        x: (parent.width * 2.0) / 3.0
                        y: 0
                        width: 1
                        height: parent.height
                        color: Qt.rgba(1, 1, 1, 0.3)
                    }

                    // Visual Corner Handles
                    CornerHandle {
                        anchors.horizontalCenter: parent.left
                        anchors.verticalCenter: parent.top
                    }
                    CornerHandle {
                        anchors.horizontalCenter: parent.right
                        anchors.verticalCenter: parent.top
                    }
                    CornerHandle {
                        anchors.horizontalCenter: parent.left
                        anchors.verticalCenter: parent.bottom
                    }
                    CornerHandle {
                        anchors.horizontalCenter: parent.right
                        anchors.verticalCenter: parent.bottom
                    }
                }

                // ---------------------------------------------------------
                // Master Interaction MouseArea
                // Handles all hover cursors, panning, and 4-corner resizing
                // with preventStealing: true to block Kirigami scroll-stealing
                // ---------------------------------------------------------
                MouseArea {
                    id: masterInteractionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    preventStealing: true

                    readonly property real hitRadius: Kirigami.Units.gridUnit * 1.5

                    property string activeMode: "NONE" // NONE, DRAG, TL, TR, BL, BR
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

                        // Check 4 Corner Hit Circles
                        if ((mx - bx) * (mx - bx) + (my - by) * (my - by) <= hr2) return "TL";
                        if ((mx - (bx + bw)) * (mx - (bx + bw)) + (my - by) * (my - by) <= hr2) return "TR";
                        if ((mx - bx) * (mx - bx) + (my - (by + bh)) * (my - (by + bh)) <= hr2) return "BL";
                        if ((mx - (bx + bw)) * (mx - (bx + bw)) + (my - (by + bh)) * (my - (by + bh)) <= hr2) return "BR";

                        // Check inside crop box
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
    // Metadata & Resolution Status Strip
    // -------------------------------------------------------------
    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.bottomMargin: isNonSrgbProfile ? Kirigami.Units.smallSpacing : Kirigami.Units.largeSpacing

        Item { Layout.fillWidth: true }

        QQC2.Label {
            Layout.alignment: Qt.AlignHCenter
            horizontalAlignment: Text.AlignHCenter
            text: {
                if (rawPreviewImage.status !== Image.Ready || rawPreviewImage.implicitWidth <= 0) {
                    return "";
                }
                const origW = rawPreviewImage.implicitWidth;
                const origH = rawPreviewImage.implicitHeight;
                const cropPixW = Math.round(cfg_CropWidth * origW);
                const cropPixH = Math.round(cfg_CropHeight * origH);
                const aspectStr = (cropPixW / Math.max(1, cropPixH)).toFixed(2);

                return (typeof i18nd !== "undefined")
                    ? i18nd("plasma_wallpaper_org.kde.cropwallpaper",
                        "Original: %1×%2 | Crop: %3×%4 (%5:1) | Screen: %6×%7",
                        origW, origH, cropPixW, cropPixH, aspectStr, Screen.width, Screen.height)
                    : `Original: ${origW}×${origH} | Crop: ${cropPixW}×${cropPixH} (${aspectStr}:1) | Screen: ${Screen.width}×${Screen.height}`;
            }
            font: Kirigami.Theme.smallFont ? Kirigami.Theme.smallFont : Qt.font({ pointSize: 9 })
            color: Kirigami.Theme.disabledTextColor ? Kirigami.Theme.disabledTextColor : "#888888"
        }

        Item { Layout.fillWidth: true }
    }

    Plasma5Support.DataSource {
        id: colorConvertSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            isConverting = false;
            const out = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            if (out.length > 0) {
                srgbImagePath = out;
                if (useSrgbFix) {
                    cfg_Image = out;
                }
            }
        }
    }

    Plasma5Support.DataSource {
        id: metadataSource
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, data) => {
            const out = (data["stdout"] || "").trim();
            disconnectSource(sourceName);
            try {
                const meta = JSON.parse(out);
                if (meta.profile_name) {
                    detectedProfileName = meta.profile_name;
                }
                if (meta.original_url) {
                    rawImagePath = meta.original_url;
                    if (!useSrgbFix && cfg_Image !== meta.original_url) {
                        cfg_Image = meta.original_url;
                    }
                }
            } catch (e) {}
        }
    }

    readonly property string backendBinPath: {
        const resolved = Qt.resolvedUrl("../../bin/set_wallpaper.py").toString();
        return resolved.startsWith("file://") ? resolved.slice(7) : resolved;
    }

    function queryImageMetadata(imagePath) {
        if (!imagePath) return;
        const cleanPath = imagePath.startsWith("file://") ? imagePath.slice(7) : imagePath;
        const cmd = `python3 "${backendBinPath}" --get-info "${cleanPath}"`;
        metadataSource.connectSource(cmd);
    }

    function convertImageToSrgb() {
        if (srgbImagePath && srgbImagePath.length > 0) {
            cfg_Image = srgbImagePath;
            return;
        }
        if (!rawImagePath) return;
        isConverting = true;
        const cleanPath = rawImagePath.startsWith("file://") ? rawImagePath.slice(7) : rawImagePath;
        const cmd = `python3 "${backendBinPath}" --convert-image "${cleanPath}"`;
        colorConvertSource.connectSource(cmd);
    }

    // Non-sRGB / Wide Gamut Color Space Warning Note & sRGB Switch
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: Kirigami.Units.largeSpacing
        visible: isNonSrgbProfile || (srgbImagePath.length > 0)
        spacing: Kirigami.Units.smallSpacing

        Item { Layout.fillWidth: true }

        Kirigami.Icon {
            source: "dialog-warning"
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
            color: Kirigami.Theme.neutralTextColor ? Kirigami.Theme.neutralTextColor : "#e5a50a"
        }

        QQC2.Label {
            text: (typeof i18nd !== "undefined")
                ? i18nd("plasma_wallpaper_org.kde.cropwallpaper",
                    "Note: Image uses %1 color profile. Colors may appear desaturated without sRGB conversion.", colorProfileName)
                : `Note: Image uses ${colorProfileName} color profile. Colors may appear desaturated without sRGB conversion.`
            font: Kirigami.Theme.smallFont ? Kirigami.Theme.smallFont : Qt.font({ pointSize: 9 })
            color: Kirigami.Theme.neutralTextColor ? Kirigami.Theme.neutralTextColor : "#e5a50a"
        }

        QQC2.BusyIndicator {
            running: isConverting
            visible: isConverting
            implicitWidth: Kirigami.Units.iconSizes.small
            implicitHeight: Kirigami.Units.iconSizes.small
        }

        QQC2.Switch {
            id: srgbSwitch
            text: "sRGB"
            checked: root.useSrgbFix
            onClicked: {
                root.useSrgbFix = checked;
                if (checked) {
                    convertImageToSrgb();
                } else {
                    if (root.rawImagePath && root.rawImagePath.length > 0) {
                        root.cfg_Image = root.rawImagePath;
                    }
                }
            }
        }

        Item { Layout.fillWidth: true }
    }

    // -------------------------------------------------------------
    // Math & Geometry Helper Functions
    // -------------------------------------------------------------

    // Fits crop rectangle to the image maximizing area while respecting target aspect ratio.
    // Preserves the current selection focus point by default, or centers if centerToImage is true.
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
            // Image is wider than target aspect ratio: take full height, scale width
            hn = 1.0;
            wn = (ih * ratio) / iw;
        } else {
            // Image is taller than target aspect ratio: take full width, scale height
            wn = 1.0;
            hn = (iw / ratio) / ih;
        }

        // Clamp to normalized [0, 1]
        wn = Math.max(0.01, Math.min(1.0, wn));
        hn = Math.max(0.01, Math.min(1.0, hn));

        let newU = (1.0 - wn) / 2.0;
        let newV = (1.0 - hn) / 2.0;

        // If not explicitly centering to whole image, maximize anchored around current selection position
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

    // Centers the current crop rectangle without altering dimensions
    function centerCurrentCrop() {
        cfg_CropX = Math.max(0.0, Math.min(1.0 - cfg_CropWidth, (1.0 - cfg_CropWidth) / 2.0));
        cfg_CropY = Math.max(0.0, Math.min(1.0 - cfg_CropHeight, (1.0 - cfg_CropHeight) / 2.0));
    }

    // Resets crop to Current Screen aspect ratio, fitted and centered
    function resetCrop() {
        cfg_AspectRatioMode = 0; // Current Screen
        fitToScreenCrop(true);
    }

    // Enforces the active aspect ratio on current crop box
    function enforceCurrentAspectRatio() {
        if (targetAspect <= 0.0 || rawPreviewImage.implicitWidth <= 0 || rawPreviewImage.implicitHeight <= 0) return;

        const iw = rawPreviewImage.implicitWidth;
        const ih = rawPreviewImage.implicitHeight;
        const ratio = targetAspect; // target pixel aspect ratio (w/h)

        // Desired normalized relation: (wn * iw) / (hn * ih) = ratio => wn = hn * ratio * (ih / iw)
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

        // Keep within bounds
        cfg_CropX = Math.max(0.0, Math.min(1.0 - wn, cfg_CropX));
        cfg_CropY = Math.max(0.0, Math.min(1.0 - hn, cfg_CropY));
    }

    // Interactive corner resizing logic with stable baseline geometry
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
        const ratio = targetAspect; // display aspect ratio equals screen aspect ratio

        let newX = curBoxX;
        let newY = curBoxY;
        let newW = curBoxW;
        let newH = curBoxH;

        if (corner === 'BR') {
            // Anchor is Top-Left (curBoxX, curBoxY)
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
            // Anchor is Top-Right (curBoxX + curBoxW, curBoxY)
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
            // Anchor is Bottom-Left (curBoxX, curBoxY + curBoxH)
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
            // Anchor is Bottom-Right (curBoxX + curBoxW, curBoxY + curBoxH)
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

        // Convert back to normalized coordinates
        cfg_CropX = Math.max(0.0, Math.min(1.0, (newX - dispX) / dispW));
        cfg_CropY = Math.max(0.0, Math.min(1.0, (newY - dispY) / dispH));
        cfg_CropWidth = Math.max(0.01, Math.min(1.0 - cfg_CropX, newW / dispW));
        cfg_CropHeight = Math.max(0.01, Math.min(1.0 - cfg_CropY, newH / dispH));
    }
}
