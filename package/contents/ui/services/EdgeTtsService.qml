// Edge-TTS Text-to-Speech Service
// Calls the edge-tts CLI via RecallHelper for async command execution.
// Caches generated audio by text+voice hash to avoid repeated synthesis.
// Requires: pip install edge-tts

import QtQuick
import "../../lib/LinguaRecallHelper"

QtObject {
    id: root

    property RecallHelper helper: RecallHelper {}

    // TTS configuration parameters
    property string voice: "en-US-EmmaMultilingualNeural"
    property string rate: "+0%"
    property string volume: "+0%"
    property string pitch: "+0Hz"

    signal finished(string audioFilePath)
    signal error(string message)

    property string _text: ""
    property bool _connected: false

    // Shared TTS cache directory.
    readonly property string _cacheDir: root.helper.cacheDir("ttscache")

    readonly property int _maxCacheFiles: 100

    property Timer _timeoutTimer: Timer {
        interval: 40000
        onTriggered: root._onTimeout()
    }

    /// DJB2 hash of the TTS arguments for cache key.
    function _hashString(str) {
        var hash = 5381
        for (var i = 0; i < str.length; i++)
            hash = ((hash << 5) + hash) + str.charCodeAt(i)
        return (hash >>> 0).toString(16)
    }

    function _cacheKey(text) {
        var raw = text.trim() + "|" + root.voice + "|" + root.rate + "|" + root.volume + "|" + root.pitch
        return "tts_" + root._hashString(raw) + ".mp3"
    }

    function synthesize(text) {
        if (!text || text.trim().length === 0) {
            root.error(qsTr("No text to synthesize"))
            return
        }
        root._ensureConnected()

        var cachePath = root._cacheDir + "/" + root._cacheKey(text)
        if (root.helper.fileExists(cachePath)) {
            root.finished(cachePath)
            return
        }

        root._text = text.trim()
        root._timeoutTimer.start()
        root.helper.runCommand("edge-tts", [
            "--text", root._text,
            "--voice", root.voice,
            "--rate", root.rate,
            "--volume", root.volume,
            "--pitch", root.pitch,
            "--write-media", cachePath
        ])
    }

    function cancel() {
        root._timeoutTimer.stop()
        root.helper.cancelCommand()
    }

    function _ensureConnected() {
        if (root._connected) return
        root.helper.commandFinished.connect(root._onFinished)
        root.helper.commandError.connect(root._onError)
        root._connected = true
    }

    function _onFinished(exitCode, stdOut, stdErr) {
        root._timeoutTimer.stop()
        if (exitCode === 0) {
            root.helper.cleanTtsCache(root._cacheDir, root._maxCacheFiles)
            root.finished(root._cacheDir + "/" + root._cacheKey(root._text))
        } else {
            var lowerErr = (stdErr + " " + stdOut).toLowerCase()
            if (lowerErr.indexOf("not found") >= 0
                || lowerErr.indexOf("command not found") >= 0
                || lowerErr.indexOf("no such file") >= 0) {
                root.error(qsTr("edge-tts not found.\nPlease install: pip install edge-tts"))
            } else {
                root.error(qsTr("Edge-TTS error (exit %1): %2").arg(exitCode).arg(stdErr || stdOut))
            }
        }
    }

    function _onError(errorMessage) {
        root._timeoutTimer.stop()
        root.error(errorMessage)
    }

    function _onTimeout() {
        root.helper.cancelCommand()
        root.error(qsTr("Edge-TTS timed out (40s)"))
    }
}
