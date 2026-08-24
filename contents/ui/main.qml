/*
    SPDX-FileCopyrightText: 2026 DZO <dragozeroone@hotmail.com>
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import org.kde.plasma.plasmoid
import org.kde.kirigami as Kirigami

WallpaperItem {
    id: root

    // Notify Plasma session startup that wallpaper is ready/loading
    Component.onCompleted: {
        root.loading = true;
    }

    // Support drag and drop image URLs directly onto desktop
    onOpenUrlRequested: (url) => {
        if (url && url.toString().length > 0 && root.configuration) {
            root.configuration.Image = url.toString();
            // Reset crop coordinates to full frame on newly dropped image
            root.configuration.CropX = 0.0;
            root.configuration.CropY = 0.0;
            root.configuration.CropWidth = 1.0;
            root.configuration.CropHeight = 1.0;
            root.configuration.writeConfig();
        }
    }

    // Fallback background color matte
    Rectangle {
        id: bgMatte
        anchors.fill: parent
        color: root.configuration?.Color ? root.configuration.Color : "#000000"

        Behavior on color {
            ColorAnimation {
                duration: Kirigami.Units.longDuration
            }
        }
    }

    // Invisible probe Image item to asynchronously detect the original unclipped pixel dimensions.
    // This avoids binding loops since setting sourceClipRect on the main Image mutates its implicitWidth/Height.
    Image {
        id: imageProbe
        source: root.configuration?.Image ? root.configuration.Image : ""
        visible: false
        asynchronous: true
        cache: true

        onStatusChanged: {
            if (status === Image.Ready) {
                root.loading = false;
            } else if (status === Image.Error) {
                root.loading = false;
            }
        }
    }

    // High-performance Desktop Wallpaper Renderer
    Image {
        id: wallpaperImage
        anchors.fill: parent
        source: imageProbe.source
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true

        // 1 = PreserveAspectCrop (default, prevents distortion), 2 = Stretch
        fillMode: (root.configuration?.FillMode === 2) ? Image.Stretch : Image.PreserveAspectCrop

        // Compute pixel crop coordinates in raw source image space
        sourceClipRect: {
            if (imageProbe.status === Image.Ready && imageProbe.implicitWidth > 0 && imageProbe.implicitHeight > 0) {
                const origW = imageProbe.implicitWidth;
                const origH = imageProbe.implicitHeight;

                const rawCropX = (root.configuration?.CropX !== undefined) ? root.configuration.CropX : 0.0;
                const rawCropY = (root.configuration?.CropY !== undefined) ? root.configuration.CropY : 0.0;
                const rawCropW = (root.configuration?.CropWidth !== undefined) ? root.configuration.CropWidth : 1.0;
                const rawCropH = (root.configuration?.CropHeight !== undefined) ? root.configuration.CropHeight : 1.0;

                // Clamp normalized parameters to [0, 1]
                const u = Math.max(0.0, Math.min(1.0, rawCropX));
                const v = Math.max(0.0, Math.min(1.0, rawCropY));
                const wn = Math.max(0.001, Math.min(1.0 - u, rawCropW));
                const hn = Math.max(0.001, Math.min(1.0 - v, rawCropH));

                // Scale normalized values to natural image pixel dimensions
                const px = Math.round(u * origW);
                const py = Math.round(v * origH);
                const pw = Math.round(wn * origW);
                const ph = Math.round(hn * origH);

                return Qt.rect(px, py, pw, ph);
            }
            return Qt.rect(0, 0, 0, 0);
        }

        // Smooth fade-in transition when switching wallpapers
        opacity: (status === Image.Ready && imageProbe.status === Image.Ready) ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: Kirigami.Units.longDuration
                easing.type: Easing.InOutQuad
            }
        }
    }
}
