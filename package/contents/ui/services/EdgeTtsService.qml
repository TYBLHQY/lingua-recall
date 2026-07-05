// Edge-TTS Text-to-Speech Service
// Calls the edge-tts CLI via RecallHelper for async command execution.
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

    property string _tempFilePath: ""
    property string _text: ""
    property bool _connected: false

    function synthesize(text) {
        if (!text || text.trim().length === 0) {
            root.error(qsTr("No text to synthesize"))
            return
        }
        root._ensureConnected()
        root._text = text.trim()
        root._tempFilePath = root.helper.cacheFilePath("tts", ".mp3")
        root.helper.runCommand("edge-tts", [
            "--text", root._text,
            "--voice", root.voice,
            "--rate", root.rate,
            "--volume", root.volume,
            "--pitch", root.pitch,
            "--write-media", root._tempFilePath
        ])
    }

    function cancel() {
        root.helper.cancelCommand()
    }

    function _ensureConnected() {
        if (root._connected) return
        root.helper.commandFinished.connect(root._onFinished)
        root.helper.commandError.connect(root._onError)
        root._connected = true
    }

    function _onFinished(exitCode, stdOut, stdErr) {
        if (exitCode === 0) {
            root.finished(root._tempFilePath)
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
        root.error(errorMessage)
    }
}
