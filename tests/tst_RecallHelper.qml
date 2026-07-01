// ── RecallHelper Unit Tests ──────────────────────────────
// Run: qml6 -I ../package/contents/lib tst_RecallHelper.qml
import QtQuick
import QtTest
import LinguaRecallHelper

TestCase {
    name: "RecallHelper"

    function test_hello_returnsString() {
        var rh = RecallHelper {}
        var result = rh.hello()
        compare(typeof result, "string")
        verify(result.length > 0)
    }

    function test_multipleInstances() {
        var rh1 = RecallHelper {}
        var rh2 = RecallHelper {}
        compare(typeof rh1.hello(), "string")
        compare(typeof rh2.hello(), "string")
    }
}
