import QtQuick
import org.kde.plasma.configuration

ConfigModel {
    ConfigCategory {
        name: i18n("General")
        icon: "configure"
        source: "ConfigGeneral.qml"
    }
    ConfigCategory {
        name: i18n("TTS Engine")
        icon: "media-playback-start"
        source: "TtsConfigCategory.qml"
    }
}
