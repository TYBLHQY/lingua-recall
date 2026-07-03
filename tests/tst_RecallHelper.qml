// RecallHelper QML Integration Tests.
// Run: qml6 -platform offscreen -I ../package/contents/lib tst_RecallHelper.qml
// These tests verify the C++ plugin loads and the API surface
// is present. They self-terminate via Qt.quit().
//
// NOTE: Cannot use `var rh = RecallHelper {}` inside JS functions
// (QML parser limitation). Instead we create instances at the
// root level and pass them to test functions.
//
// License: GPL-2.0+

import QtQuick 2.15
import LinguaRecallHelper 0.1

Item {
    id: root

    // Pre-created instances for tests.
    // (QML can't create types inside JS; we must do it here)
    readonly property var rh1: RecallHelper {}
    readonly property var rh2: RecallHelper {}

    // Tests (each is a function reference).
    readonly property var tests: [
        function test_hello() {
            var h = root.rh1.hello()
            if (typeof h !== "string" || h.length === 0) {
                throw "FAIL: hello() returned " + JSON.stringify(h)
            }
            console.log("PASS: hello() =", h)
        },

        function test_multipleInstances() {
            if (root.rh1.hello() !== root.rh2.hello()) {
                throw "FAIL: instances diverge"
            }
            console.log("PASS: multiple instances consistent")
        },

        function test_newApi_exists() {
            var methods = [
                "initReviewDb", "isReviewDbOpen", "closeReviewDb",
                "getDueCards", "getNewCards", "reviewCard",
                "createCard", "getCard", "getCardHistory", "getStats",
                "loadFsrsParams", "saveFsrsParams", "exec"
            ]
            for (var i = 0; i < methods.length; ++i) {
                if (typeof root.rh1[methods[i]] !== "function") {
                    throw "FAIL: method " + methods[i] + " not found"
                }
            }
            console.log("PASS: all", methods.length, "API methods present")
        },

        function test_initReviewDb() {
            var ok = root.rh1.initReviewDb()
            if (typeof ok !== "boolean") {
                throw "FAIL: initReviewDb returned " + typeof ok
            }
            if (root.rh1.isReviewDbOpen()) {
                root.rh1.closeReviewDb()
            }
            console.log("PASS: initReviewDb() =", ok)
        },

        function test_getDueCards_returnsJson() {
            root.rh1.initReviewDb()
            var json = root.rh1.getDueCards(5)
            if (typeof json !== "string") {
                throw "FAIL: getDueCards returned " + typeof json
            }
            var arr = JSON.parse(json)
            if (!Array.isArray(arr)) {
                throw "FAIL: getDueCards did not return a JSON array"
            }
            root.rh1.closeReviewDb()
            console.log("PASS: getDueCards() = JSON array of length", arr.length)
        }
    ]

    property int testIndex: 0

    function runNext() {
        if (testIndex >= tests.length) {
            console.log("\nAll", tests.length, "tests passed!")
            Qt.quit()
            return
        }
        try {
            tests[testIndex]()
            console.log("  OK (" + (testIndex + 1) + "/" + tests.length + ")")
        } catch (e) {
            console.log("FAIL:", e)
            Qt.quit()
            return
        }
        testIndex++
        Qt.callLater(runNext)
    }

    Component.onCompleted: {
        console.log("=== LinguaRecallHelper QML Tests ===\n")
        runNext()
    }
}
