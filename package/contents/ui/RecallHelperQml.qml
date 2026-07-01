// ── Recall Helper QML wrapper — scaffold ──────────────────
import QtQuick
import "../lib/LinguaRecallHelper"

QtObject {
    id: root

    property RecallHelper helper: RecallHelper {}

    /// Verify the C++ module loads correctly.
    function checkReady() {
        return helper.hello()
    }
}
