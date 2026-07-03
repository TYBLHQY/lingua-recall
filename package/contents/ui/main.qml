// Lingua Recall — Spaced Repetition Review Panel.
// KDE Plasma 6 Plasmoid — FSRS-6 powered vocabulary review.
//
// License: GPL-2.0+

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts

import org.kde.plasma.plasmoid
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

import "../lib/LinguaRecallHelper"

PlasmoidItem {
    id: root

    Plasmoid.backgroundHints: PlasmaCore.Types.NoBackground
    hideOnWindowDeactivate: !root.pinned

    // Refresh on expand (covers keyboard shortcut and any non-click open).
    onExpandedChanged: {
        if (expanded)
            refreshMergedCards()
    }

    // Config.
    readonly property int fontSizeBase: Plasmoid.configuration.fontSizeBase || 14
    readonly property int fontSizeLarge: fontSizeBase + 1
    readonly property int fontSizeSmall: Math.max(6, fontSizeBase - 2)
    readonly property int fontSizeSecondary: Math.max(6, fontSizeBase - 1)
    readonly property string fontFamily: Plasmoid.configuration.fontFamily || ""

    // State.
    property bool pinned: false

    // Merged card queue: new words first, then due cards.
    property var currentCard: null
    property var cardQueue: []
    property int currentCardIndex: 0
    property bool answerRevealed: false

    // Stats cache.
    property var statsCache: ({})

    // DB bridge.
    property RecallHelperQml recall: RecallHelperQml {}

    // Extraction helpers — AI result_json is flat {translate, words, ...}.

    /// Main translation text (from any engine).
    function extractTranslation(resultJson) {
        if (!resultJson) return ""
        try {
            var j = JSON.parse(resultJson)
            if (j.translate) return j.translate
        } catch(e) {}
        return ""
    }

    /// Phonetic transcription.
    function extractPhonetic(resultJson) {
        if (!resultJson) return ""
        try {
            var j = JSON.parse(resultJson)
            if (j.phonetic) return j.phonetic
        } catch(e) {}
        return ""
    }

    /// Example sentences (array of strings).
    function extractExamples(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.examples && Array.isArray(j.examples)) return j.examples
        } catch(e) {}
        return []
    }

    /// AI word analysis — array of {word, pos, meaning}.
    function extractAiWords(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.words && Array.isArray(j.words)) return j.words
        } catch(e) {}
        return []
    }

    /// AI collocations — array of {phrase, translation}.
    function extractCollocations(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.frequently && Array.isArray(j.frequently)) return j.frequently
        } catch(e) {}
        return []
    }

    // Flat grid models for column-aligned display (spanner pattern).
    readonly property var _flatWordModel: {
        var words = currentCard
            ? root.extractAiWords(currentCard.result_json)
            : []
        var m = []
        for (var i = 0; i < words.length; i++) {
            m.push({ text: words[i].word || "", bold: true, fillWidth: false, color: "" })
            m.push({ text: words[i].pos || "", bold: false, fillWidth: false, color: Kirigami.Theme.neutralTextColor })
            m.push({ text: words[i].meaning || "", bold: false, fillWidth: true, color: "" })
        }
        return m
    }

    readonly property var _flatCollocationModel: {
        var colls = currentCard
            ? root.extractCollocations(currentCard.result_json)
            : []
        var m = []
        for (var i = 0; i < colls.length; i++) {
            m.push({ text: colls[i].phrase || "", bold: true, fillWidth: false, color: "" })
            m.push({ text: colls[i].translation || "", bold: false, fillWidth: true, color: "" })
        }
        return m
    }


    // === Merged card queue management ===

    function refreshMergedCards() {
        // All active review cards (learning/review/relearning), ordered by due.
        // Uses exec() to bypass the due<=now filter in getDueCards().
        var reviewCards = recall.parseArray(recall.exec(
            "SELECT rc.id, rc.translation_id, rc.stability, rc.difficulty,"
            + " rc.state, rc.due, rc.last_review_at, rc.elapsed_days,"
            + " rc.scheduled_days, rc.reps, rc.lapses,"
            + " t.input_text, t.cleaned_input, t.source_lang, t.target_lang,"
            + " t.result_json, t.engine"
            + " FROM review_cards rc"
            + " JOIN translations t ON t.id = rc.translation_id"
            + " WHERE rc.state IN ('learning','review','relearning')"
            + " AND rc.due <= (strftime('%Y-%m-%dT%H:%M:%S','now') || 'Z')"
            + " ORDER BY rc.due ASC"
            + " LIMIT 999"))

        // Compute retrievability for each review card.
        for (var j = 0; j < reviewCards.length; j++) {
            var c = reviewCards[j]
            c.isNew = false
            var elapsed = 0
            if (c.last_review_at) {
                var last = new Date(c.last_review_at)
                var diffMs = new Date() - last
                elapsed = diffMs / 86400000 // ms → days
                if (elapsed < 0) elapsed = 0
            }
            c.retrievability = _calcRetrievability(c.stability, elapsed)
        }

        // New words (translations without review cards).
        var newWords = recall.parseArray(recall.getNewCards(999))
        for (var i = 0; i < newWords.length; i++)
            newWords[i].isNew = true

        // Review cards first, then new words.
        cardQueue = reviewCards.concat(newWords)
        currentCardIndex = 0
        currentCard = cardQueue.length > 0 ? cardQueue[0] : null
        answerRevealed = false
        refreshStats()
    }

    /// FSRS-6 retrievability formula: R(t,S) = (1 + factor·t/S)^(-w[20])
    function _calcRetrievability(stability, elapsedDays) {
        if (!stability || stability <= 0 || elapsedDays === undefined) return 0
        // Default w[20] = 0.1542 (may differ if user loaded custom params,
        // but close enough for display purposes).
        var w20 = 0.1542
        var factor = Math.pow(0.9, -1 / w20) - 1
        return Math.pow(1 + factor * elapsedDays / stability, -w20)
    }

    function rateCurrentCard(rating) {
        if (!currentCard) return

        if (currentCard.isNew) {
            // New word: create card then review.
            var cid = recall.createCard(currentCard.id)
            if (cid && cid.length > 0)
                recall.reviewCard(cid, rating)
        } else {
            // Existing review card.
            var result = recall.parseObject(
                recall.reviewCard(currentCard.id, rating))
            if (!result.card_id) return
        }

        // Advance to next card.
        cardQueue.splice(currentCardIndex, 1)
        if (currentCardIndex < cardQueue.length) {
            currentCard = cardQueue[currentCardIndex]
        } else if (cardQueue.length > 0) {
            currentCardIndex = 0
            currentCard = cardQueue[0]
        } else {
            currentCard = null
        }
        answerRevealed = false
        refreshStats()
    }

    // Human-readable label for card state.
    function stateLabel(state) {
        switch (state) {
        case "new":         return i18n("New")
        case "learning":    return i18n("Learning")
        case "review":      return i18n("Review")
        case "relearning":  return i18n("Relearning")
        default:            return state
        }
    }

    // Refresh stats cache from DB.
    function refreshStats() {
        statsCache = recall.parseObject(recall.getStats())
    }

    // Init DB on load.
    Component.onCompleted: {
        if (recall.initReviewDb())
            refreshMergedCards()
    }

    // Compact: taskbar icon.
    compactRepresentation: Kirigami.Icon {
        source: "dialog-ok"
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small

        MouseArea {
            anchors.fill: parent
            onClicked: root.expanded = !root.expanded
        }
    }

    // Full: popup panel — single merged view for new + review cards.
    fullRepresentation: Item {
        id: panelRoot
        focus: true
        clip: true

        Layout.minimumWidth: 380
        Layout.minimumHeight: 400
        Layout.preferredWidth: 440
        Layout.preferredHeight: 520

        // Keyboard shortcuts.
        Keys.onPressed: function (event) {
            if (answerRevealed && currentCard) {
                switch (event.key) {
                case Qt.Key_1: rateCurrentCard(1); event.accepted = true; break
                case Qt.Key_2: rateCurrentCard(2); event.accepted = true; break
                case Qt.Key_3: rateCurrentCard(3); event.accepted = true; break
                case Qt.Key_4: rateCurrentCard(4); event.accepted = true; break
                }
            }
            if (event.key === Qt.Key_Space && currentCard && !answerRevealed) {
                answerRevealed = true
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.smallSpacing

            // HEADER.
            RowLayout {
                Layout.fillWidth: true

                Kirigami.Heading {
                    text: i18n("Lingua Recall")
                    level: 2
                    Layout.fillWidth: true
                }

                QQC2.Button {
                    id: pinBtn
                    icon.name: root.pinned ? "window-pin" : "window-unpin"
                    implicitWidth: Kirigami.Units.iconSizes.medium
                    implicitHeight: Kirigami.Units.iconSizes.medium
                    onClicked: root.pinned = !root.pinned
                    Accessible.name: root.pinned ? i18n("Unpin") : i18n("Pin")
                    QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                    QQC2.ToolTip.text: root.pinned
                        ? i18n("Keep open when switching windows")
                        : i18n("Pin panel open")
                    QQC2.ToolTip.visible: hovered
                }
            }

            // CONTENT — scrollable card area.
            QQC2.ScrollView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                padding: 0
                clip: true
                contentWidth: width
                QQC2.ScrollBar.vertical.policy: QQC2.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: Kirigami.Units.smallSpacing

                    // Progress header.
                    RowLayout {
                        Layout.fillWidth: true
                        visible: currentCard !== null

                        PlasmaComponents3.Label {
                            text: currentCard
                                  ? i18n("Card %1 of %2",
                                         currentCardIndex + 1, cardQueue.length)
                                  : ""
                            font.pixelSize: root.fontSizeSmall
                            font.family: root.fontFamily || undefined
                            color: Kirigami.Theme.disabledTextColor
                            Layout.fillWidth: true
                        }

                        // FSRS state badge (review cards only).
                        PlasmaComponents3.Label {
                            text: currentCard && !currentCard.isNew
                                  ? root.stateLabel(currentCard.state)
                                  : ""
                            font.pixelSize: root.fontSizeSmall
                            font.family: root.fontFamily || undefined
                            font.weight: Font.Bold
                            color: {
                                var s = currentCard && !currentCard.isNew
                                        ? currentCard.state : ""
                                switch (s) {
                                case "learning":    return Kirigami.Theme.neutralTextColor
                                case "review":      return Kirigami.Theme.positiveTextColor
                                case "relearning":  return Kirigami.Theme.negativeTextColor
                                default:            return Kirigami.Theme.disabledTextColor
                                }
                            }
                            visible: currentCard !== null && !currentCard.isNew
                        }
                    }

                    // Card frame (spanner-style implicitHeight).
                    Rectangle {
                        visible: currentCard !== null
                        Layout.fillWidth: true
                        color: Kirigami.Theme.backgroundColor
                        border.color: answerRevealed
                                      ? Kirigami.Theme.focusColor
                                      : Kirigami.Theme.alternateBackgroundColor
                        border.width: 1
                        radius: 4
                        clip: true

                        implicitHeight: !answerRevealed
                            ? Math.max(Kirigami.Units.gridUnit * 6,
                                beforeContent.implicitHeight
                                + Kirigami.Units.largeSpacing * 2)
                            : afterContent.implicitHeight
                              + Kirigami.Units.largeSpacing * 2

                        // Tap to reveal (before reveal only).
                        MouseArea {
                            anchors.fill: parent
                            enabled: !answerRevealed && currentCard !== null
                            onClicked: {
                                if (currentCard && !answerRevealed)
                                    answerRevealed = true
                            }
                        }

                        // === Before reveal: centered ===
                        ColumnLayout {
                            id: beforeContent
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            visible: currentCard !== null && !answerRevealed

                            Item { Layout.fillHeight: true }

                            Kirigami.Heading {
                                text: currentCard ? currentCard.input_text : ""
                                level: 2
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.weight: Font.Bold
                            }

                            // Phonetic.
                            PlasmaComponents3.Label {
                                text: currentCard
                                      ? root.extractPhonetic(currentCard.result_json)
                                      : ""
                                font.pixelSize: root.fontSizeSecondary
                                font.family: root.fontFamily || undefined
                                font.italic: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Cleaned input (if differs).
                            PlasmaComponents3.Label {
                                text: {
                                    if (!currentCard) return ""
                                    if (!currentCard.cleaned_input) return ""
                                    if (currentCard.cleaned_input === currentCard.input_text) return ""
                                    return currentCard.cleaned_input
                                }
                                font.pixelSize: root.fontSizeSmall
                                font.family: root.fontFamily || undefined
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Language direction.
                            PlasmaComponents3.Label {
                                text: currentCard
                                    ? (currentCard.source_lang || "?")
                                      + " → " + (currentCard.target_lang || "?")
                                    : ""
                                font.pixelSize: root.fontSizeSmall
                                font.family: root.fontFamily || undefined
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Item { Layout.fillHeight: true }
                        }

                        // === After reveal: full content ===
                        ColumnLayout {
                            id: afterContent
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing
                            visible: currentCard !== null && answerRevealed

                            // Word/phrase.
                            Kirigami.Heading {
                                text: currentCard ? currentCard.input_text : ""
                                level: 2
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.weight: Font.Bold
                            }

                            // Phonetic.
                            PlasmaComponents3.Label {
                                text: currentCard
                                      ? root.extractPhonetic(currentCard.result_json)
                                      : ""
                                font.pixelSize: root.fontSizeSecondary
                                font.family: root.fontFamily || undefined
                                font.italic: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Cleaned input.
                            PlasmaComponents3.Label {
                                text: {
                                    if (!currentCard) return ""
                                    if (!currentCard.cleaned_input) return ""
                                    if (currentCard.cleaned_input === currentCard.input_text) return ""
                                    return currentCard.cleaned_input
                                }
                                font.pixelSize: root.fontSizeSmall
                                font.family: root.fontFamily || undefined
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Language direction.
                            PlasmaComponents3.Label {
                                text: currentCard
                                    ? (currentCard.source_lang || "?")
                                      + " → " + (currentCard.target_lang || "?")
                                    : ""
                                font.pixelSize: root.fontSizeSmall
                                font.family: root.fontFamily || undefined
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                            }

                            // Translation.
                            PlasmaComponents3.Label {
                                text: root.extractTranslation(currentCard.result_json)
                                font.pixelSize: root.fontSizeLarge
                                font.family: root.fontFamily || undefined
                                font.weight: Font.Bold
                                color: Kirigami.Theme.linkColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                visible: text.length > 0
                            }

                            // --- AI Word Analysis ---
                            ColumnLayout {
                                visible: root.extractAiWords(
                                             currentCard.result_json).length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: i18n("Word Analysis")
                                    font.bold: true
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.neutralTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                }

                                GridLayout {
                                    columns: 3
                                    columnSpacing: Kirigami.Units.largeSpacing
                                    rowSpacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    PlasmaComponents3.Label {
                                        text: i18n("Word")
                                        font.bold: true
                                        font.pixelSize: root.fontSizeSmall
                                        font.family: root.fontFamily || undefined
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("POS")
                                        font.bold: true
                                        font.pixelSize: root.fontSizeSmall
                                        font.family: root.fontFamily || undefined
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("Meaning")
                                        font.bold: true
                                        font.pixelSize: root.fontSizeSmall
                                        font.family: root.fontFamily || undefined
                                        color: Kirigami.Theme.disabledTextColor
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        Layout.columnSpan: 3
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Kirigami.Theme.disabledTextColor
                                        opacity: 0.2
                                    }

                                    Repeater {
                                        model: root._flatWordModel

                                        delegate: Text {
                                            required property var modelData
                                            text: modelData.text
                                            font.bold: modelData.bold
                                            font.pixelSize: root.fontSizeSmall
                                            font.family: root.fontFamily || undefined
                                            color: modelData.color || Kirigami.Theme.textColor
                                            wrapMode: modelData.fillWidth ? Text.WordWrap : Text.NoWrap
                                            Layout.fillWidth: modelData.fillWidth || false
                                            Layout.alignment: Qt.AlignTop
                                        }
                                    }
                                }
                            }

                            // --- AI Collocations ---
                            ColumnLayout {
                                visible: root.extractCollocations(
                                             currentCard.result_json).length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: i18n("Collocations")
                                    font.bold: true
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.neutralTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                }

                                GridLayout {
                                    columns: 2
                                    columnSpacing: Kirigami.Units.largeSpacing
                                    rowSpacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    PlasmaComponents3.Label {
                                        text: i18n("Phrase")
                                        font.bold: true
                                        font.pixelSize: root.fontSizeSmall
                                        font.family: root.fontFamily || undefined
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("Translation")
                                        font.bold: true
                                        font.pixelSize: root.fontSizeSmall
                                        font.family: root.fontFamily || undefined
                                        color: Kirigami.Theme.disabledTextColor
                                        Layout.fillWidth: true
                                    }

                                    Rectangle {
                                        Layout.columnSpan: 2
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Kirigami.Theme.disabledTextColor
                                        opacity: 0.2
                                    }

                                    Repeater {
                                        model: root._flatCollocationModel

                                        delegate: Text {
                                            required property var modelData
                                            text: modelData.text
                                            font.bold: modelData.bold
                                            font.pixelSize: root.fontSizeSmall
                                            font.family: root.fontFamily || undefined
                                            color: modelData.color || Kirigami.Theme.textColor
                                            wrapMode: modelData.fillWidth ? Text.WordWrap : Text.NoWrap
                                            Layout.fillWidth: modelData.fillWidth || false
                                            Layout.alignment: Qt.AlignTop
                                        }
                                    }
                                }
                            }

                            // --- Example sentences ---
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: root.extractExamples(
                                        currentCard.result_json)

                                    delegate: PlasmaComponents3.Label {
                                        text: "• " + modelData
                                        font.pixelSize: root.fontSizeSmall
                                        font.family: root.fontFamily || undefined
                                        font.italic: true
                                        color: Kirigami.Theme.disabledTextColor
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // --- FSRS Metrics (review cards only) ---
                            GridLayout {
                                visible: !currentCard.isNew
                                         && currentCard.stability > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                columns: 4
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: i18n("Stability:")
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? currentCard.stability.toFixed(1) + " d"
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    font.weight: Font.Bold
                                    Layout.alignment: Qt.AlignLeft
                                }

                                PlasmaComponents3.Label {
                                    text: i18n("Recall:")
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? Math.round(1e3
                                              * (currentCard.retrievability || 0)) / 10 + "%"
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    font.weight: Font.Bold
                                    color: {
                                        if (!currentCard) return Kirigami.Theme.textColor
                                        var r = currentCard.retrievability || 0
                                        return r < 0.5
                                            ? Kirigami.Theme.negativeTextColor
                                            : r < 0.8
                                                ? Kirigami.Theme.neutralTextColor
                                                : Kirigami.Theme.positiveTextColor
                                    }
                                    Layout.alignment: Qt.AlignLeft
                                }

                                PlasmaComponents3.Label {
                                    text: i18n("Difficulty:")
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? currentCard.difficulty.toFixed(1)
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    font.weight: Font.Bold
                                    Layout.alignment: Qt.AlignLeft
                                }

                                PlasmaComponents3.Label {
                                    text: i18n("Next:")
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? i18np("1 day", "%1 days",
                                                  currentCard.scheduled_days)
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    font.weight: Font.Bold
                                    Layout.alignment: Qt.AlignLeft
                                }
                            }

                            // reps/lapses line (review cards only).
                            RowLayout {
                                visible: !currentCard.isNew
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.largeSpacing

                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? i18n("Reviews: %1", currentCard.reps || 0)
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? i18n("Lapses: %1", currentCard.lapses || 0)
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: currentCard && currentCard.lapses > 0
                                           ? Kirigami.Theme.negativeTextColor
                                           : Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard && currentCard.elapsed_days > 0
                                          ? i18n("Ago: %1 d", currentCard.elapsed_days)
                                          : ""
                                    font.pixelSize: root.fontSizeSmall
                                    font.family: root.fontFamily || undefined
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            // Engine attribution (new words only).
                            PlasmaComponents3.Label {
                                text: currentCard && currentCard.isNew
                                      && currentCard.engine
                                      ? i18n("via %1", currentCard.engine)
                                      : ""
                                font.pixelSize: root.fontSizeSmall
                                font.family: root.fontFamily || undefined
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                                Layout.topMargin: Kirigami.Units.smallSpacing
                            }
                        }
                    }

                    // Rating buttons (shown after reveal).
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: answerRevealed && currentCard !== null

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Kirigami.Units.smallSpacing

                            QQC2.Button {
                                text: i18n("1  Again")
                                icon.name: "edit-delete"
                                Layout.fillWidth: true
                                onClicked: rateCurrentCard(1)
                            }
                            QQC2.Button {
                                text: i18n("2  Hard")
                                icon.name: "arrow-down"
                                Layout.fillWidth: true
                                onClicked: rateCurrentCard(2)
                            }
                            QQC2.Button {
                                text: i18n("3  Good")
                                icon.name: "arrow-right"
                                Layout.fillWidth: true
                                onClicked: rateCurrentCard(3)
                            }
                            QQC2.Button {
                                text: i18n("4  Easy")
                                icon.name: "arrow-up"
                                Layout.fillWidth: true
                                onClicked: rateCurrentCard(4)
                            }
                        }

                        PlasmaComponents3.Label {
                            text: i18n("Press 1–4 on keyboard")
                            font.pixelSize: root.fontSizeSmall
                            font.family: root.fontFamily || undefined
                            color: Kirigami.Theme.disabledTextColor
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // Tap hint (before reveal).
                    PlasmaComponents3.Label {
                        visible: currentCard !== null && !answerRevealed
                        text: i18n("Tap card or press Space to reveal answer")
                        font.pixelSize: root.fontSizeSmall
                        font.family: root.fontFamily || undefined
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Empty state.
                    ColumnLayout {
                        visible: currentCard === null
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Kirigami.Units.smallSpacing

                        Item { Layout.fillHeight: true }

                        Kirigami.Icon {
                            source: "dialog-ok"
                            implicitWidth: Kirigami.Units.iconSizes.large
                            implicitHeight: Kirigami.Units.iconSizes.large
                            Layout.alignment: Qt.AlignHCenter
                            opacity: 0.4
                        }

                        PlasmaComponents3.Label {
                            text: i18n("All caught up!")
                            font.pixelSize: root.fontSizeLarge
                            font.family: root.fontFamily || undefined
                            font.weight: Font.Bold
                            color: Kirigami.Theme.positiveTextColor
                            Layout.alignment: Qt.AlignHCenter
                        }

                        PlasmaComponents3.Label {
                            text: i18n("Add more translations\nwith Lingua Spanner")
                            color: Kirigami.Theme.disabledTextColor
                            font.italic: true
                            wrapMode: Text.WordWrap
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            font.pixelSize: root.fontSizeSmall
                            font.family: root.fontFamily || undefined
                        }

                        Item { Layout.fillHeight: true }
                    }

                    // Bottom spacer.
                    Item { Layout.fillHeight: true; visible: currentCard !== null }
                }
            }

            // STATUS BAR.
            PlasmaComponents3.Label {
                text: {
                    var parts = []
                    if (statsCache.reviews_today > 0)
                        parts.push(i18n("Today: %1", statsCache.reviews_today))
                    parts.push(i18n("Due: %1", statsCache.due_now || 0))
                    parts.push(i18n("New: %1", statsCache.new_available || 0))
                    if (statsCache.total_cards > 0)
                        parts.push(i18n("Total: %1", statsCache.total_cards))
                    return parts.join("  ·  ")
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: root.fontSizeSmall
                font.family: root.fontFamily || undefined
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
            }
        }
    }

    // Tooltip.
    toolTipMainText: i18n("Lingua Recall")
    toolTipSubText: {
        if (statsCache.due_now > 0)
            return i18n("Cards due for review: %1", statsCache.due_now)
        if (statsCache.new_available > 0)
            return i18n("New words available: %1", statsCache.new_available)
        return i18n("All caught up!")
    }
}
