// TTS Engine Configuration — Edge-TTS
// Per-language voice selection with list caching.
// Requires: pip install edge-tts

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.kcmutils as KCMUtils
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

import "../lib/LinguaRecallHelper"

KCMUtils.SimpleKCM {
    id: page

    // KConfig XT bindings — common settings
    property string cfg_edgeTtsRate: "+0%"
    property string cfg_edgeTtsRateDefault: "+0%"
    property string cfg_edgeTtsVolume: "+0%"
    property string cfg_edgeTtsVolumeDefault: "+0%"
    property string cfg_edgeTtsPitch: "+0Hz"
    property string cfg_edgeTtsPitchDefault: "+0Hz"

    // Per-language voice selection
    property alias cfg_edgeTtsVoiceZh: zhVoiceCombo.editText
    property string cfg_edgeTtsVoiceZhDefault: "zh-CN-XiaoxiaoNeural"
    property alias cfg_edgeTtsVoiceEn: enVoiceCombo.editText
    property string cfg_edgeTtsVoiceEnDefault: "en-US-EmmaMultilingualNeural"
    property alias cfg_edgeTtsVoiceDe: deVoiceCombo.editText
    property string cfg_edgeTtsVoiceDeDefault: "de-DE-KatjaNeural"
    property alias cfg_edgeTtsVoiceJa: jaVoiceCombo.editText
    property string cfg_edgeTtsVoiceJaDefault: "ja-JP-NanamiNeural"
    property alias cfg_edgeTtsVoiceFr: frVoiceCombo.editText
    property string cfg_edgeTtsVoiceFrDefault: "fr-FR-DeniseNeural"
    property alias cfg_edgeTtsVoiceEs: esVoiceCombo.editText
    property string cfg_edgeTtsVoiceEsDefault: "es-ES-ElviraNeural"

    // Cached voice lists
    property string cfg_edgeTtsVoiceLists: "{}"
    property string cfg_edgeTtsVoiceListsDefault: "{}"

    RecallHelper { id: _helper }

    property bool _fetchingVoices: false

    readonly property var _langMeta: [
        { id: "zh", label: i18n("简体中文"), prefix: "zh-" },
        { id: "en", label: i18n("English"),  prefix: "en-" },
        { id: "de", label: i18n("Deutsch"),  prefix: "de-" },
        { id: "ja", label: i18n("日本語"),   prefix: "ja-" },
        { id: "fr", label: i18n("Français"),  prefix: "fr-" },
        { id: "es", label: i18n("Español"),   prefix: "es-" }
    ]

    function _restoreVoiceLists() {
        var raw = page.cfg_edgeTtsVoiceLists
        if (!raw || raw === "{}") return false
        try {
            var lists = JSON.parse(raw)
            if (typeof lists !== "object") return false
            for (var i = 0; i < page._langMeta.length; i++) {
                var key = page._langMeta[i].id
                var list = lists[key]
                if (Array.isArray(list) && list.length > 0)
                    page._setComboModel(key, list)
            }
            return true
        } catch(e) { return false }
    }

    function _setComboModel(langId, voices) {
        var combo = page._getCombo(langId)
        if (!combo) return
        var saved = combo.editText
        combo.model = voices
        var idx = combo.find(saved)
        if (idx >= 0) combo.currentIndex = idx
        else combo.editText = saved
    }

    function _getCombo(langId) {
        if (langId === "zh") return zhVoiceCombo
        if (langId === "en") return enVoiceCombo
        if (langId === "de") return deVoiceCombo
        if (langId === "ja") return jaVoiceCombo
        if (langId === "fr") return frVoiceCombo
        if (langId === "es") return esVoiceCombo
        return null
    }

    function _parseVoiceList(exitCode, stdOut, stdErr) {
        _fetchingVoices = false
        if (exitCode !== 0) return

        var allVoices = []
        var lines = stdOut.split('\n')
        for (var i = 0; i < lines.length; i++) {
            var parts = lines[i].trim().split(/\s+/)
            var name = parts.length > 0 ? parts[0] : ""
            if (name.length > 0 && name !== "Name" && name.indexOf("-") >= 0)
                allVoices.push(name)
        }
        if (allVoices.length === 0) return

        var lists = {}
        for (var j = 0; j < page._langMeta.length; j++) {
            var prefix = page._langMeta[j].prefix
            var filtered = []
            for (var k = 0; k < allVoices.length; k++) {
                if (allVoices[k].indexOf(prefix) === 0)
                    filtered.push(allVoices[k])
            }
            if (filtered.length > 0)
                lists[page._langMeta[j].id] = filtered
        }

        for (var lid in lists) {
            if (lists.hasOwnProperty(lid))
                page._setComboModel(lid, lists[lid])
        }
        page.cfg_edgeTtsVoiceLists = JSON.stringify(lists)
    }

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing
        Layout.fillWidth: true

        Kirigami.Heading { level: 2; text: i18n("Edge-TTS"); Layout.fillWidth: true }

        PlasmaComponents3.Label {
            text: i18n("Lingua Recall uses edge-tts to read card content aloud.")
            wrapMode: Text.WordWrap; Layout.fillWidth: true; Layout.maximumWidth: Kirigami.Units.gridUnit * 30
        }

        // Common settings: sliders
        Kirigami.Heading { level: 3; text: i18n("Common Settings"); Layout.fillWidth: true }

        ColumnLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            // Rate
            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label { text: i18n("Rate (%):"); Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                QQC2.Slider { id: rateSlider; Layout.fillWidth: true; from: -50; to: 50; value: 0; stepSize: 1
                    Component.onCompleted: { var v=page.cfg_edgeTtsRate; if(v.length>0){var n=parseInt(v.replace(/[+%]/g,''));if(!isNaN(n))value=Math.max(-50,Math.min(50,n))} }
                    onMoved: { var s=value>=0?"+":""; page.cfg_edgeTtsRate=s+value+"%" }
                }
                PlasmaComponents3.Label { text:(rateSlider.value>=0?"+":"")+rateSlider.value+"%"; font.weight:Font.Medium; Layout.minimumWidth:Kirigami.Units.gridUnit*3; horizontalAlignment:Text.AlignRight }
            }
            // Volume
            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label { text: i18n("Volume (%):"); Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                QQC2.Slider { id: volSlider; Layout.fillWidth: true; from: -50; to: 50; value: 0; stepSize: 1
                    Component.onCompleted: { var v=page.cfg_edgeTtsVolume; if(v.length>0){var n=parseInt(v.replace(/[+%]/g,''));if(!isNaN(n))value=Math.max(-50,Math.min(50,n))} }
                    onMoved: { var s=value>=0?"+":""; page.cfg_edgeTtsVolume=s+value+"%" }
                }
                PlasmaComponents3.Label { text:(volSlider.value>=0?"+":"")+volSlider.value+"%"; font.weight:Font.Medium; Layout.minimumWidth:Kirigami.Units.gridUnit*3; horizontalAlignment:Text.AlignRight }
            }
            // Pitch
            RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label { text: i18n("Pitch (Hz):"); Layout.preferredWidth: Kirigami.Units.gridUnit * 6 }
                QQC2.Slider { id: pitchSlider; Layout.fillWidth: true; from: -50; to: 50; value: 0; stepSize: 1
                    Component.onCompleted: { var v=page.cfg_edgeTtsPitch; if(v.length>0){var n=parseInt(v.replace(/[+Hz]/g,''));if(!isNaN(n))value=Math.max(-50,Math.min(50,n))} }
                    onMoved: { var s=value>=0?"+":""; page.cfg_edgeTtsPitch=s+value+"Hz" }
                }
                PlasmaComponents3.Label { text:(pitchSlider.value>=0?"+":"")+pitchSlider.value+"Hz"; font.weight:Font.Medium; Layout.minimumWidth:Kirigami.Units.gridUnit*3; horizontalAlignment:Text.AlignRight }
            }
        }

        // Per-language voices
        Kirigami.Heading { level: 3; text: i18n("Voices (per language)"); Layout.fillWidth: true }

        GridLayout { columns: 2; Layout.fillWidth: true; rowSpacing: Kirigami.Units.smallSpacing; columnSpacing: Kirigami.Units.largeSpacing
            PlasmaComponents3.Label { text: page._langMeta[0].label }
            QQC2.ComboBox { id: zhVoiceCombo; editable: true; Layout.fillWidth: true; model: [page.cfg_edgeTtsVoiceZhDefault]
                property bool _ready: false
                Component.onCompleted: { var v=page.cfg_edgeTtsVoiceZh; var i=find(v); if(i>=0)currentIndex=i; else editText=v; _ready=true }
                onEditTextChanged: { if(_ready) page.cfg_edgeTtsVoiceZh=editText }
            }
            PlasmaComponents3.Label { text: page._langMeta[1].label }
            QQC2.ComboBox { id: enVoiceCombo; editable: true; Layout.fillWidth: true; model: [page.cfg_edgeTtsVoiceEnDefault]
                property bool _ready: false
                Component.onCompleted: { var v=page.cfg_edgeTtsVoiceEn; var i=find(v); if(i>=0)currentIndex=i; else editText=v; _ready=true }
                onEditTextChanged: { if(_ready) page.cfg_edgeTtsVoiceEn=editText }
            }
            PlasmaComponents3.Label { text: page._langMeta[2].label }
            QQC2.ComboBox { id: deVoiceCombo; editable: true; Layout.fillWidth: true; model: [page.cfg_edgeTtsVoiceDeDefault]
                property bool _ready: false
                Component.onCompleted: { var v=page.cfg_edgeTtsVoiceDe; var i=find(v); if(i>=0)currentIndex=i; else editText=v; _ready=true }
                onEditTextChanged: { if(_ready) page.cfg_edgeTtsVoiceDe=editText }
            }
            PlasmaComponents3.Label { text: page._langMeta[3].label }
            QQC2.ComboBox { id: jaVoiceCombo; editable: true; Layout.fillWidth: true; model: [page.cfg_edgeTtsVoiceJaDefault]
                property bool _ready: false
                Component.onCompleted: { var v=page.cfg_edgeTtsVoiceJa; var i=find(v); if(i>=0)currentIndex=i; else editText=v; _ready=true }
                onEditTextChanged: { if(_ready) page.cfg_edgeTtsVoiceJa=editText }
            }
            PlasmaComponents3.Label { text: page._langMeta[4].label }
            QQC2.ComboBox { id: frVoiceCombo; editable: true; Layout.fillWidth: true; model: [page.cfg_edgeTtsVoiceFrDefault]
                property bool _ready: false
                Component.onCompleted: { var v=page.cfg_edgeTtsVoiceFr; var i=find(v); if(i>=0)currentIndex=i; else editText=v; _ready=true }
                onEditTextChanged: { if(_ready) page.cfg_edgeTtsVoiceFr=editText }
            }
            PlasmaComponents3.Label { text: page._langMeta[5].label }
            QQC2.ComboBox { id: esVoiceCombo; editable: true; Layout.fillWidth: true; model: [page.cfg_edgeTtsVoiceEsDefault]
                property bool _ready: false
                Component.onCompleted: { var v=page.cfg_edgeTtsVoiceEs; var i=find(v); if(i>=0)currentIndex=i; else editText=v; _ready=true }
                onEditTextChanged: { if(_ready) page.cfg_edgeTtsVoiceEs=editText }
            }
        }

        // Refresh
        RowLayout { Layout.fillWidth: true; spacing: Kirigami.Units.smallSpacing
            QQC2.Button { icon.name:"view-refresh"; text:i18n("Refresh voice list"); enabled:!page._fetchingVoices
                Component.onCompleted: { _helper.commandFinished.connect(page._parseVoiceList) }
                onClicked: { page._fetchingVoices=true; _helper.runCommand("edge-tts",["--list-voices"]) }
            }
            PlasmaComponents3.Label { text:i18n("Auto-fetches on first load"); color:Kirigami.Theme.disabledTextColor; font.pixelSize:12; Layout.fillWidth:true }
        }

        PlasmaComponents3.Label {
            text: i18n("Requires pip install edge-tts · Voices provided by Microsoft Edge online TTS")
            color: Kirigami.Theme.disabledTextColor; wrapMode: Text.WordWrap; Layout.fillWidth: true; font.pixelSize: 12
        }

        Item { Layout.fillHeight: true }
    }

    Component.onCompleted: {
        if (!page._restoreVoiceLists()) {
            Qt.callLater(function() { page._fetchingVoices=true; _helper.runCommand("edge-tts",["--list-voices"]) })
        }
    }
}
