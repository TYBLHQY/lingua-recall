// ── Lingua Recall main.qml — Plasmoid scaffold ─────────────
import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// ── Custom QML plugin (placeholder C++ module) ─────────────
import "../lib/LinguaRecallHelper"

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    hideOnWindowDeactivate: !root.pinned

    // ── Font sizes (from config) ────────────────────────────
    readonly property int fontSizeBase: Plasmoid.configuration.fontSizeBase || 14

    // ── Pin state ──────────────────────────────────────────
    property bool pinned: false

    // ── Placeholder state ──────────────────────────────────
    property string placeholderText: ""
    property string statusMessage: ""

    // ── Compact: taskbar icon ───────────────────────────────
    compactRepresentation: Kirigami.Icon {
        source: "adjustcoloreffects"
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.expanded = !root.expanded
            }
        }
    }

    // ── Full: popup panel ───────────────────────────────────
    fullRepresentation: Item {
        Layout.minimumWidth: 380
        Layout.minimumHeight: 320
        Layout.preferredWidth: 440
        Layout.preferredHeight: 480

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            // ── Header ─────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents3.Heading {
                    text: i18n("Lingua Recall")
                    level: 2
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    icon.name: root.pinned ? "window-pin" : "window-unpin"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    onClicked: root.pinned = !root.pinned
                    Accessible.name: root.pinned ? i18n("Unpin") : i18n("Pin")
                    QQC2.ToolTip {
                        text: root.pinned ? i18n("Pinned: stay open when focus changes") : i18n("Pin to keep open when switching windows")
                        delay: Kirigami.Units.toolTipDelay
                        visible: hovered
                    }
                }
            }

            // ── Content placeholder ─────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Kirigami.Units.smallSpacing

                PlasmaComponents3.Label {
                    text: i18n("Content area — add your UI here")
                    color: Kirigami.Theme.disabledTextColor
                    font.italic: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                }

                Item { Layout.fillHeight: true }
            }

            // ── Status bar ──────────────────────────────────
            PlasmaComponents3.Label {
                id: statusLabel
                text: root.statusMessage.length > 0 ? root.statusMessage : i18n("Ready")
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Math.max(6, root.fontSizeBase - 2)
                Layout.fillWidth: true
            }
        }
    }

    // ── Tooltip ─────────────────────────────────────────────
    toolTipMainText: i18n("Lingua Recall")
    toolTipSubText: i18n("Framework scaffold — ready for development")
}
