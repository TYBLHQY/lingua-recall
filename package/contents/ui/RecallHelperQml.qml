// ── Recall Helper QML Wrapper ─────────────────────────────
// Bridges C++ RecallHelper + ReviewDb to QML.
// Usage:
//   RecallHelperQml { id: helper }
//   helper.initReviewDb();
//   helper.getDueCards() → JSON array string
//   helper.reviewCard(cardId, rating) → JSON result
//
// License: GPL-2.0+

import QtQuick
import "../lib/LinguaRecallHelper"

QtObject {
    id: root

    property RecallHelper helper: RecallHelper {}

    // ── Initialization ──────────────────────────────────────
    function initReviewDb() {
        return helper.initReviewDb()
    }

    function closeReviewDb() {
        helper.closeReviewDb()
    }

    readonly property bool dbReady: helper.isReviewDbOpen()

    // ── Card operations (return JSON strings) ───────────────
    function createCard(translationId) {
        return helper.createCard(translationId)
    }

    function reviewCard(cardId, rating) {
        return helper.reviewCard(cardId, rating)
    }

    function getDueCards(limit) {
        return helper.getDueCards(limit || 50)
    }

    function getNewCards(limit) {
        return helper.getNewCards(limit || 20)
    }

    function getCard(cardId) {
        return helper.getCard(cardId)
    }

    function getCardHistory(cardId, limit) {
        return helper.getCardHistory(cardId, limit || 100)
    }

    function getStats() {
        return helper.getStats()
    }

    // ── FSRS params ─────────────────────────────────────────
    function loadFsrsParams() {
        return helper.loadFsrsParams()
    }

    function saveFsrsParams(json) {
        return helper.saveFsrsParams(json)
    }

    // ── Direct SQL ──────────────────────────────────────────
    function exec(sql, params) {
        return helper.exec(sql, params || "[]")
    }

    // ── JSON convenience parsers ────────────────────────────
    function parseArray(json) {
        return JSON.parse(json || "[]")
    }

    function parseObject(json) {
        return JSON.parse(json || "{}")
    }
}
