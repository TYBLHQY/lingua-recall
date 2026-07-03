import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../lib/LinguaRecallHelper"

KCMUtils.SimpleKCM {
    id: page

    // KConfig XT bindings.
    property alias cfg_fontSizeBase: fontSizeSpin.value
    property int cfg_fontSizeBaseDefault: 14

    // DB bridge (for FSRS params).
    property RecallHelperQml recall: RecallHelperQml {}

    // FSRS params state.
    property double desiredRetention: 0.9
    property int maxInterval: 36500
    property var wParams: []

    // Load/save.
    function loadSettings() {
        if (!recall.initReviewDb()) return
        var p = recall.parseObject(recall.loadFsrsParams())
        if (p.desired_retention) {
            desiredRetention = p.desired_retention
            maxInterval = p.max_interval || 36500
            wParams = p.w || []
        }
    }

    function saveSettings() {
        if (!recall.dbReady) return
        var p = {
            desired_retention: desiredRetention,
            max_interval: maxInterval,
            enable_fuzzing: 1
        }
        if (wParams.length === 21) {
            p.w = wParams
        }
        recall.saveFsrsParams(JSON.stringify(p))
    }

    Component.onCompleted: loadSettings()

    // UI.
    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        // Display section.
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

        // FSRS Scheduling section.
        Kirigami.Heading {
            level: 3
            text: i18n("Spaced Repetition (FSRS-6)")
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.largeSpacing
        }

        GridLayout {
            columns: 3
            Layout.fillWidth: true
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.largeSpacing

            // Desired retention
            PlasmaComponents3.Label {
                text: i18n("Desired retention:")
            }
            QQC2.Slider {
                id: retentionSlider
                from: 0.80
                to: 0.97
                value: page.desiredRetention
                stepSize: 0.01
                Layout.fillWidth: true
                onMoved: {
                    page.desiredRetention = value
                    saveSettings()
                }
            }
            PlasmaComponents3.Label {
                text: "%1%".arg(Math.round(retentionSlider.value * 100))
                font.weight: Font.Bold
                Layout.minimumWidth: Kirigami.Units.gridUnit * 2
            }

            // Max interval
            PlasmaComponents3.Label {
                text: i18n("Max interval (days):")
            }
            QQC2.SpinBox {
                id: maxIntervalSpin
                from: 30
                to: 36500
                stepSize: 30
                editable: true
                value: page.maxInterval
                Layout.fillWidth: true
                onValueModified: {
                    page.maxInterval = value
                    saveSettings()
                }
            }
            Item { width: Kirigami.Units.gridUnit * 2 } // spacer
        }

        // Info.
        PlasmaComponents3.Label {
            text: i18n("Higher retention = more frequent reviews. "
                       + "Lower retention = less frequent, but higher risk of forgetting. "
                       + "Recommended range: 80%–95%.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.pixelSize: Math.max(6, page.cfg_fontSizeBase - 3)
        }

        Item { Layout.fillHeight: true }

        // About.
        Kirigami.Heading {
            level: 3
            text: i18n("About")
            Layout.fillWidth: true
        }

        PlasmaComponents3.Label {
            text: i18n("Lingua Recall v0.1.0 — FSRS-6 powered vocabulary review. "
                       + "Uses the Free Spaced Repetition Scheduler v6 with 21 "
                       + "trainable parameters.")
            color: Kirigami.Theme.disabledTextColor
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }
}
