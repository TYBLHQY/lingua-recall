import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

KCMUtils.SimpleKCM {
    id: page

    // ── KConfig XT bindings ───────────────────────────────────
    property alias cfg_fontSizeBase: fontSizeSpin.value
    property int cfg_fontSizeBaseDefault: 14

    // ── UI ────────────────────────────────────────────────────
    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        Kirigami.Heading {
            level: 3
            text: i18n("Display")
            Layout.fillWidth: true
        }

        GridLayout {
            columns: 2
            Layout.fillWidth: true
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            PlasmaComponents3.Label {
                text: i18n("Base Font Size (px):")
            }
            QQC2.SpinBox {
                id: fontSizeSpin
                from: 8
                to: 24
                stepSize: 1
                editable: true
                Layout.preferredWidth: Kirigami.Units.gridUnit * 6
            }
        }

        Kirigami.Heading {
            level: 3
            text: i18n("About")
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
        }

        PlasmaComponents3.Label {
            text: i18n("Lingua Recall v0.1.0 — Framework scaffold.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        Item { Layout.fillHeight: true }
    }
}
