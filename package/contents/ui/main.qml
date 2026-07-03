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

    // Config.
    readonly property int fontSizeBase: Plasmoid.configuration.fontSizeBase || 14
    readonly property int fs: fontSizeBase

    // State.
    property bool pinned: false

    // Tab navigation.
    property int currentTab: 0  // 0=Review, 1=New, 2=Stats

    // Currently displayed card (from due list).
    property var currentCard: null
    property var dueCards: []
    property var newCards: []
    property int currentCardIndex: 0
    property bool answerRevealed: false

    // New Words tab: single-word "next" mode.
    property var currentNewWord: null
    property int newWordIndex: 0
    property bool newWordRevealed: false

    // Stats cache.
    property var statsCache: ({})

    // DB bridge.
    property RecallHelperQml recall: RecallHelperQml {}

    // Translation extraction helpers.
    // result_json can be flat (AI engines: {translate, words, ...}) or
    // nested (Youdao/dict: {translation: "...", exp: [...], ...}).

    /// Main translation text (from any engine).
    function extractTranslation(resultJson) {
        if (!resultJson) return ""
        try {
            var j = JSON.parse(resultJson)
            // AI engines: flat "translate" field
            if (j.translate) return j.translate
            // Youdao/dict: "translation" may be plain text or nested JSON
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    return t.translate || j.translation
                } catch(e) {
                    return j.translation
                }
            }
        } catch(e) {}
        return ""
    }

    /// Phonetic transcription.
    function extractPhonetic(resultJson) {
        if (!resultJson) return ""
        try {
            var j = JSON.parse(resultJson)
            if (j.phonetic) return j.phonetic
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    if (t.phonetic) return t.phonetic
                } catch(e) {}
            }
        } catch(e) {}
        return ""
    }

    /// Example sentences (array of strings).
    function extractExamples(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.examples && Array.isArray(j.examples)) return j.examples
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    if (t.examples && Array.isArray(t.examples)) return t.examples
                } catch(e) {}
            }
        } catch(e) {}
        return []
    }

    /// AI word analysis — array of {word, pos, meaning}.
    function extractAiWords(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.words && Array.isArray(j.words)) return j.words
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    if (t.words && Array.isArray(t.words)) return t.words
                } catch(e) {}
            }
        } catch(e) {}
        return []
    }

    /// AI collocations — array of {phrase, translation}.
    function extractCollocations(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.frequently && Array.isArray(j.frequently)) return j.frequently
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    if (t.frequently && Array.isArray(t.frequently)) return t.frequently
                } catch(e) {}
            }
        } catch(e) {}
        return []
    }

    /// Youdao/dict definitions — array of {po, tr}.
    function extractDefinitions(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.exp && Array.isArray(j.exp)) return j.exp
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    if (t.exp && Array.isArray(t.exp)) return t.exp
                } catch(e) {}
            }
        } catch(e) {}
        return []
    }

    /// Youdao exam type tags — array of strings.
    function extractExamTypes(resultJson) {
        if (!resultJson) return []
        try {
            var j = JSON.parse(resultJson)
            if (j.examType && Array.isArray(j.examType)) return j.examType
            if (j.translation) {
                try {
                    var t = JSON.parse(j.translation)
                    if (t.examType && Array.isArray(t.examType)) return t.examType
                } catch(e) {}
            }
        } catch(e) {}
        return []
    }

    function refreshDueCards() {
        dueCards = recall.parseArray(recall.getDueCards(50))
        if (dueCards.length > 0) {
            currentCardIndex = 0
            currentCard = dueCards[0]
        } else {
            currentCard = null
        }
        answerRevealed = false
        refreshStats()
    }

    function refreshNewCards() {
        newCards = recall.parseArray(recall.getNewCards(999))
        newWordIndex = 0
        currentNewWord = newCards.length > 0 ? newCards[0] : null
        newWordRevealed = false
        refreshStats()
    }

    function nextNewWord() {
        if (newWordIndex + 1 < newCards.length) {
            newWordIndex++
            currentNewWord = newCards[newWordIndex]
            newWordRevealed = false
        }
    }

    function previousNewWord() {
        if (newWordIndex - 1 >= 0) {
            newWordIndex--
            currentNewWord = newCards[newWordIndex]
            newWordRevealed = false
        }
    }

    function learnCurrentNewWord() {
        if (!currentNewWord) return
        var cid = recall.createCard(currentNewWord.id)
        if (cid && cid.length > 0) {
            // Remove from list and advance.
            newCards.splice(newWordIndex, 1)
            if (newWordIndex < newCards.length) {
                currentNewWord = newCards[newWordIndex]
            } else if (newCards.length > 0) {
                newWordIndex = 0
                currentNewWord = newCards[0]
            } else {
                currentNewWord = null
                // Auto-switch to review tab when all learned.
                currentTab = 0
                refreshDueCards()
                return
            }
            newWordRevealed = false
            refreshStats()
        }
    }

    function refreshStats() {
        statsCache = recall.parseObject(recall.getStats())
    }

    function rateCard(rating) {
        if (!currentCard) return
        var result = recall.parseObject(
            recall.reviewCard(currentCard.id, rating))
        if (result.card_id) {
            // Remove the reviewed card from the due list.
            dueCards.splice(currentCardIndex, 1)
            // Advance or loop.
            if (currentCardIndex < dueCards.length) {
                currentCard = dueCards[currentCardIndex]
            } else if (dueCards.length > 0) {
                currentCardIndex = 0
                currentCard = dueCards[0]
            } else {
                currentCard = null
            }
            answerRevealed = false
        }
        refreshStats()
    }

    // Human-readable retelling of the card state.
    function stateLabel(state) {
        switch (state) {
        case "new":         return i18n("New")
        case "learning":    return i18n("Learning")
        case "review":      return i18n("Review")
        case "relearning":  return i18n("Relearning")
        default:            return state
        }
    }

    // Init DB on load.
    Component.onCompleted: {
        if (recall.initReviewDb()) {
            refreshDueCards()
            refreshNewCards()
        }
    }

    // Compact: taskbar icon.
    compactRepresentation: Kirigami.Icon {
        source: "dialog-ok"
        implicitWidth: Kirigami.Units.iconSizes.small
        implicitHeight: Kirigami.Units.iconSizes.small

        MouseArea {
            anchors.fill: parent
            onClicked: {
                root.expanded = !root.expanded
                if (root.expanded) {
                    refreshDueCards()
                    refreshNewCards()
                }
            }
        }
    }

    // Full: popup panel.
    fullRepresentation: Item {
        id: panelRoot
        focus: true
        clip: true

        Layout.minimumWidth: 380
        Layout.minimumHeight: 400
        Layout.preferredWidth: 440
        Layout.preferredHeight: 520

        // Keyboard shortcuts for review.
        Keys.onPressed: function (event) {
            if (currentTab === 0 && answerRevealed && currentCard) {
                switch (event.key) {
                case Qt.Key_1: rateCard(1); event.accepted = true; break
                case Qt.Key_2: rateCard(2); event.accepted = true; break
                case Qt.Key_3: rateCard(3); event.accepted = true; break
                case Qt.Key_4: rateCard(4); event.accepted = true; break
                }
            }
            // Tab switching.
            if (event.key >= Qt.Key_1 && event.key <= Qt.Key_3) {
                if (!currentCard || !answerRevealed) {
                    var tab = event.key - Qt.Key_1
                    if (tab >= 0 && tab <= 2) {
                        currentTab = tab
                        event.accepted = true
                    }
                }
            }
            // Space to reveal.
            if (event.key === Qt.Key_Space && currentTab === 0 && currentCard && !answerRevealed) {
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

            // TAB BAR.
            RowLayout {
                Layout.fillWidth: true

                Repeater {
                    model: [i18n("Review"), i18n("New Words"), i18n("Stats")]

                    delegate: PlasmaComponents3.Button {
                        text: modelData
                        checked: currentTab === index
                        flat: !checked
                        Layout.fillWidth: true
                        onClicked: {
                            currentTab = index
                            if (index === 0) refreshDueCards()
                            if (index === 1) refreshNewCards()
                            if (index === 2) refreshStats()
                        }
                    }
                }
            }

            // CONTENT AREA.
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ===== TAB 0: Review =====
                ColumnLayout {
                    visible: currentTab === 0
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    // Card counter + FSRS state badge.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing

                        PlasmaComponents3.Label {
                            text: currentCard
                                  ? i18n("Card %1 of %2",
                                         currentCardIndex + 1, dueCards.length)
                                  : ""
                            font.pixelSize: Math.max(6, root.fs - 3)
                            color: Kirigami.Theme.disabledTextColor
                            Layout.fillWidth: true
                        }

                        PlasmaComponents3.Label {
                            text: currentCard
                                  ? root.stateLabel(currentCard.state)
                                  : ""
                            font.pixelSize: Math.max(6, root.fs - 4)
                            font.weight: Font.Bold
                            color: {
                                switch (currentCard ? currentCard.state : "") {
                                case "learning":    return Kirigami.Theme.neutralTextColor
                                case "review":      return Kirigami.Theme.positiveTextColor
                                case "relearning":  return Kirigami.Theme.negativeTextColor
                                default:            return Kirigami.Theme.disabledTextColor
                                }
                            }
                            visible: currentCard !== null
                        }
                    }

                    // Flashcard.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Kirigami.Theme.backgroundColor
                        border.color: answerRevealed
                                      ? Kirigami.Theme.focusColor
                                      : Kirigami.Theme.alternateBackgroundColor
                        border.width: 1
                        radius: 4

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing

                            // Source text (word/phrase being reviewed).
                            Kirigami.Heading {
                                id: sourceHeading
                                text: currentCard ? currentCard.input_text : ""
                                level: 3
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.weight: Font.Bold
                                visible: currentCard !== null
                            }

                            // Cleaned input (shown as subtitle if different).
                            PlasmaComponents3.Label {
                                text: {
                                    if (!currentCard) return ""
                                    if (!currentCard.cleaned_input) return ""
                                    if (currentCard.cleaned_input === currentCard.input_text) return ""
                                    return currentCard.cleaned_input
                                }
                                font.pixelSize: Math.max(6, root.fs - 3)
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Separator before answer.
                            Kirigami.Separator {
                                Layout.fillWidth: true
                                visible: answerRevealed && currentCard !== null
                                Layout.topMargin: Kirigami.Units.smallSpacing
                            }

                            // Translation text (revealed).
                            PlasmaComponents3.Label {
                                id: translationLabel
                                text: answerRevealed && currentCard
                                      ? root.extractTranslation(currentCard.result_json)
                                      : ""
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: Math.max(8, root.fs + 2)
                                font.weight: Font.Bold
                                color: Kirigami.Theme.linkColor
                                visible: answerRevealed && currentCard !== null
                            }

                            // Example sentences (revealed).
                            ColumnLayout {
                                visible: answerRevealed && currentCard !== null
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: answerRevealed && currentCard
                                           ? root.extractExamples(currentCard.result_json)
                                           : []

                                    delegate: PlasmaComponents3.Label {
                                        text: "• " + modelData
                                        font.pixelSize: Math.max(6, root.fs - 2)
                                        font.italic: true
                                        color: Kirigami.Theme.disabledTextColor
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                    }
                                }
                            }

                            // FSRS Metrics Grid (revealed, after first review).
                            GridLayout {
                                visible: answerRevealed && currentCard !== null
                                         && currentCard.stability > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                columns: 4
                                columnSpacing: Kirigami.Units.largeSpacing
                                rowSpacing: Kirigami.Units.smallSpacing

                                // Stability.
                                PlasmaComponents3.Label {
                                    text: i18n("Stability:")
                                    font.pixelSize: Math.max(6, root.fs - 4)
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? currentCard.stability.toFixed(1) + " d"
                                          : ""
                                    font.pixelSize: Math.max(6, root.fs - 3)
                                    font.weight: Font.Bold
                                    Layout.alignment: Qt.AlignLeft
                                }

                                // Retrievability.
                                PlasmaComponents3.Label {
                                    text: i18n("Recall:")
                                    font.pixelSize: Math.max(6, root.fs - 4)
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? Math.round(1e3
                                              * (currentCard.retrievability || 0)) / 10 + "%"
                                          : ""
                                    font.pixelSize: Math.max(6, root.fs - 3)
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

                                // Difficulty.
                                PlasmaComponents3.Label {
                                    text: i18n("Difficulty:")
                                    font.pixelSize: Math.max(6, root.fs - 4)
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? currentCard.difficulty.toFixed(1)
                                          : ""
                                    font.pixelSize: Math.max(6, root.fs - 3)
                                    font.weight: Font.Bold
                                    Layout.alignment: Qt.AlignLeft
                                }

                                // Next interval.
                                PlasmaComponents3.Label {
                                    text: i18n("Next:")
                                    font.pixelSize: Math.max(6, root.fs - 4)
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignRight
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? i18np("1 day", "%1 days",
                                                  currentCard.scheduled_days)
                                          : ""
                                    font.pixelSize: Math.max(6, root.fs - 3)
                                    font.weight: Font.Bold
                                    Layout.alignment: Qt.AlignLeft
                                }
                            }

                            // reps/lapses line (revealed).
                            RowLayout {
                                visible: answerRevealed && currentCard !== null
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.largeSpacing

                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? i18n("Reviews: %1", currentCard.reps || 0)
                                          : ""
                                    font.pixelSize: Math.max(6, root.fs - 5)
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                                PlasmaComponents3.Label {
                                    text: currentCard
                                          ? i18n("Lapses: %1", currentCard.lapses || 0)
                                          : ""
                                    font.pixelSize: Math.max(6, root.fs - 5)
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
                                    font.pixelSize: Math.max(6, root.fs - 5)
                                    color: Kirigami.Theme.disabledTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            // Empty state (no cards due).
                            ColumnLayout {
                                visible: currentCard === null
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: "dialog-ok"
                                    implicitWidth: Kirigami.Units.iconSizes.large
                                    implicitHeight: Kirigami.Units.iconSizes.large
                                    Layout.alignment: Qt.AlignHCenter
                                    opacity: 0.4
                                }

                                PlasmaComponents3.Label {
                                    text: i18n("All caught up!")
                                    font.pixelSize: Math.max(8, root.fs + 2)
                                    font.weight: Font.Bold
                                    color: Kirigami.Theme.positiveTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                }

                                PlasmaComponents3.Label {
                                    text: i18n("No cards due for review right now.\n"
                                             + "Add translations with Lingua Spanner,\n"
                                             + "or check New Words to start learning.")
                                    color: Kirigami.Theme.disabledTextColor
                                    font.italic: true
                                    wrapMode: Text.WordWrap
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignHCenter
                                    horizontalAlignment: Text.AlignHCenter
                                    font.pixelSize: Math.max(6, root.fs - 2)
                                }

                                // Quick-link to New Words tab.
                                PlasmaComponents3.Button {
                                    text: i18n("Go to New Words")
                                    icon.name: "list-add"
                                    flat: true
                                    Layout.alignment: Qt.AlignHCenter
                                    visible: statsCache.new_available > 0
                                    onClicked: {
                                        currentTab = 1
                                        refreshNewCards()
                                    }
                                }
                            }

                            Item { Layout.fillHeight: true; visible: currentCard !== null }
                        }

                        // Tap to reveal.
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (currentCard && !answerRevealed)
                                    answerRevealed = true
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
                                onClicked: rateCard(1)
                            }
                            QQC2.Button {
                                text: i18n("2  Hard")
                                icon.name: "arrow-down"
                                Layout.fillWidth: true
                                onClicked: rateCard(2)
                            }
                            QQC2.Button {
                                text: i18n("3  Good")
                                icon.name: "arrow-right"
                                Layout.fillWidth: true
                                onClicked: rateCard(3)
                            }
                            QQC2.Button {
                                text: i18n("4  Easy")
                                icon.name: "arrow-up"
                                Layout.fillWidth: true
                                onClicked: rateCard(4)
                            }
                        }

                        // Keyboard shortcut hint.
                        PlasmaComponents3.Label {
                            text: i18n("Press 1–4 on keyboard")
                            font.pixelSize: Math.max(6, root.fs - 4)
                            color: Kirigami.Theme.disabledTextColor
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    // Tap hint.
                    PlasmaComponents3.Label {
                        visible: currentCard !== null && !answerRevealed
                        text: i18n("Tap card or press Space to reveal answer")
                        font.pixelSize: Math.max(6, root.fs - 3)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                // ===== TAB 1: New Words (single-card next mode) =====
                ColumnLayout {
                    visible: currentTab === 1
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    // Header: title + progress.
                    RowLayout {
                        Layout.fillWidth: true

                        Kirigami.Heading {
                            text: i18n("New Words")
                            level: 4
                            Layout.fillWidth: true
                        }

                        PlasmaComponents3.Label {
                            text: newCards.length > 0
                                  ? i18n("%1 of %2",
                                         newWordIndex + 1, newCards.length)
                                  : i18n("Done")
                            color: Kirigami.Theme.disabledTextColor
                            font.pixelSize: Math.max(6, root.fs - 2)
                        }
                    }

                    // Prev / Next row ABOVE the card.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: currentNewWord !== null

                        QQC2.Button {
                            icon.name: "go-previous"
                            text: i18n("Previous")
                            enabled: newWordIndex > 0
                            onClicked: previousNewWord()
                            flat: true
                        }

                        Item { Layout.fillWidth: true }

                        QQC2.Button {
                            text: i18n("Learn")
                            icon.name: "list-add"
                            highlighted: true
                            visible: newWordRevealed
                            onClicked: learnCurrentNewWord()
                        }

                        Item { Layout.fillWidth: true }

                        QQC2.Button {
                            icon.name: "go-next"
                            text: i18n("Next")
                            enabled: newWordIndex < newCards.length - 1
                            onClicked: nextNewWord()
                            flat: true
                        }
                    }

                    // Single-word card.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: Kirigami.Theme.backgroundColor
                        border.color: newWordRevealed
                                      ? Kirigami.Theme.focusColor
                                      : Kirigami.Theme.alternateBackgroundColor
                        border.width: 1
                        radius: 4

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Kirigami.Units.largeSpacing
                            spacing: Kirigami.Units.smallSpacing

                            // Top spacer (pushes word down).
                            Item { Layout.fillHeight: true; visible: currentNewWord }

                            // Word/phrase.
                            Kirigami.Heading {
                                text: currentNewWord ? currentNewWord.input_text : ""
                                level: 2
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.weight: Font.Bold
                                visible: currentNewWord !== null
                            }

                            // Phonetic (before reveal).
                            PlasmaComponents3.Label {
                                text: currentNewWord && !newWordRevealed
                                      ? root.extractPhonetic(currentNewWord.result_json)
                                      : ""
                                font.pixelSize: Math.max(7, root.fs - 1)
                                font.italic: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Cleaned input (subtitle when different).
                            PlasmaComponents3.Label {
                                text: {
                                    if (!currentNewWord) return ""
                                    if (!currentNewWord.cleaned_input) return ""
                                    if (currentNewWord.cleaned_input === currentNewWord.input_text) return ""
                                    return currentNewWord.cleaned_input
                                }
                                font.pixelSize: Math.max(6, root.fs - 3)
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // Language direction.
                            PlasmaComponents3.Label {
                                text: currentNewWord
                                    ? (currentNewWord.source_lang || "?")
                                      + " → " + (currentNewWord.target_lang || "?")
                                    : ""
                                font.pixelSize: Math.max(6, root.fs - 4)
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: currentNewWord !== null
                            }

                            // --- Revealed content (tap to show) ---

                            Kirigami.Separator {
                                Layout.fillWidth: true
                                visible: newWordRevealed && currentNewWord !== null
                                Layout.topMargin: Kirigami.Units.smallSpacing
                            }

                            // Translation.
                            PlasmaComponents3.Label {
                                text: newWordRevealed && currentNewWord
                                      ? root.extractTranslation(currentNewWord.result_json)
                                      : ""
                                font.pixelSize: Math.max(8, root.fs + 1)
                                font.weight: Font.Bold
                                color: Kirigami.Theme.linkColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                visible: text.length > 0
                            }

                            // Phonetic (after reveal, if not already shown).
                            PlasmaComponents3.Label {
                                text: currentNewWord && newWordRevealed
                                      ? root.extractPhonetic(currentNewWord.result_json)
                                      : ""
                                font.pixelSize: Math.max(7, root.fs - 1)
                                font.italic: true
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                            }

                            // --- AI Word Analysis (AI engines only) ---
                            ColumnLayout {
                                visible: newWordRevealed && currentNewWord !== null
                                         && root.extractAiWords(
                                                currentNewWord.result_json).length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: i18n("Word Analysis")
                                    font.bold: true
                                    font.pixelSize: Math.max(6, root.fs - 3)
                                    color: Kirigami.Theme.neutralTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                }

                                // 3-column grid: Word | POS | Meaning
                                GridLayout {
                                    columns: 3
                                    columnSpacing: Kirigami.Units.largeSpacing
                                    rowSpacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    // Headers.
                                    PlasmaComponents3.Label {
                                        text: i18n("Word")
                                        font.bold: true
                                        font.pixelSize: Math.max(6, root.fs - 4)
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("POS")
                                        font.bold: true
                                        font.pixelSize: Math.max(6, root.fs - 4)
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("Meaning")
                                        font.bold: true
                                        font.pixelSize: Math.max(6, root.fs - 4)
                                        color: Kirigami.Theme.disabledTextColor
                                    }

                                    // Separator.
                                    Rectangle {
                                        Layout.columnSpan: 3
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Kirigami.Theme.disabledTextColor
                                        opacity: 0.2
                                    }

                                    // Data rows.
                                    Repeater {
                                        model: root.extractAiWords(
                                            currentNewWord.result_json)

                                        delegate: Item {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: Math.max(
                                                wordLabel.implicitHeight,
                                                posLabel.implicitHeight,
                                                meaningLabel.implicitHeight)

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: Kirigami.Units.largeSpacing

                                                PlasmaComponents3.Label {
                                                    id: wordLabel
                                                    text: modelData.word || ""
                                                    font.bold: true
                                                    font.pixelSize: Math.max(6, root.fs - 2)
                                                    Layout.preferredWidth: parent.width * 0.25
                                                }
                                                PlasmaComponents3.Label {
                                                    id: posLabel
                                                    text: modelData.pos || ""
                                                    color: Kirigami.Theme.neutralTextColor
                                                    font.pixelSize: Math.max(6, root.fs - 2)
                                                    Layout.preferredWidth: parent.width * 0.15
                                                }
                                                PlasmaComponents3.Label {
                                                    id: meaningLabel
                                                    text: modelData.meaning || ""
                                                    font.pixelSize: Math.max(6, root.fs - 2)
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // --- AI Collocations (AI engines only) ---
                            ColumnLayout {
                                visible: newWordRevealed && currentNewWord !== null
                                         && root.extractCollocations(
                                                currentNewWord.result_json).length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: i18n("Collocations")
                                    font.bold: true
                                    font.pixelSize: Math.max(6, root.fs - 3)
                                    color: Kirigami.Theme.neutralTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                }

                                // 2-column grid: Phrase | Translation
                                GridLayout {
                                    columns: 2
                                    columnSpacing: Kirigami.Units.largeSpacing
                                    rowSpacing: Kirigami.Units.smallSpacing
                                    Layout.fillWidth: true

                                    // Headers.
                                    PlasmaComponents3.Label {
                                        text: i18n("Phrase")
                                        font.bold: true
                                        font.pixelSize: Math.max(6, root.fs - 4)
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                    PlasmaComponents3.Label {
                                        text: i18n("Translation")
                                        font.bold: true
                                        font.pixelSize: Math.max(6, root.fs - 4)
                                        color: Kirigami.Theme.disabledTextColor
                                    }

                                    // Separator.
                                    Rectangle {
                                        Layout.columnSpan: 2
                                        Layout.fillWidth: true
                                        height: 1
                                        color: Kirigami.Theme.disabledTextColor
                                        opacity: 0.2
                                    }

                                    // Data rows.
                                    Repeater {
                                        model: root.extractCollocations(
                                            currentNewWord.result_json)

                                        delegate: Item {
                                            required property var modelData
                                            Layout.fillWidth: true
                                            height: phraseLabel.implicitHeight

                                            RowLayout {
                                                anchors.fill: parent
                                                spacing: Kirigami.Units.largeSpacing

                                                PlasmaComponents3.Label {
                                                    id: phraseLabel
                                                    text: modelData.phrase || ""
                                                    font.bold: true
                                                    font.pixelSize: Math.max(6, root.fs - 2)
                                                    Layout.preferredWidth: parent.width * 0.4
                                                }
                                                PlasmaComponents3.Label {
                                                    text: modelData.translation || ""
                                                    font.pixelSize: Math.max(6, root.fs - 2)
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Youdao/dict Definitions ---
                            ColumnLayout {
                                visible: newWordRevealed && currentNewWord !== null
                                         && root.extractDefinitions(
                                                currentNewWord.result_json).length > 0
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                PlasmaComponents3.Label {
                                    text: i18n("Definitions")
                                    font.bold: true
                                    font.pixelSize: Math.max(6, root.fs - 3)
                                    color: Kirigami.Theme.neutralTextColor
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.bottomMargin: Kirigami.Units.smallSpacing
                                }

                                // Each definition item: {po, tr} → [POS] tr1, tr2...
                                Repeater {
                                    model: root.extractDefinitions(
                                        currentNewWord.result_json)

                                    delegate: ColumnLayout {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        spacing: 2

                                        PlasmaComponents3.Label {
                                            text: modelData.po || ""
                                            font.bold: true
                                            color: Kirigami.Theme.neutralTextColor
                                            font.pixelSize: Math.max(6, root.fs - 2)
                                            visible: text.length > 0
                                        }

                                        Repeater {
                                            model: modelData.tr || []

                                            delegate: RowLayout {
                                                required property string modelData
                                                Layout.fillWidth: true
                                                spacing: Kirigami.Units.smallSpacing

                                                Rectangle {
                                                    width: 3; height: parent.height
                                                    radius: 1.5
                                                    color: Kirigami.Theme.neutralTextColor
                                                }
                                                PlasmaComponents3.Label {
                                                    text: modelData
                                                    font.pixelSize: Math.max(6, root.fs - 2)
                                                    wrapMode: Text.WordWrap
                                                    Layout.fillWidth: true
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // --- Youdao exam type tags ---
                            Flow {
                                visible: newWordRevealed && currentNewWord !== null
                                         && root.extractExamTypes(
                                                currentNewWord.result_json).length > 0
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Layout.topMargin: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: root.extractExamTypes(
                                        currentNewWord.result_json)

                                    delegate: PlasmaComponents3.Label {
                                        required property string modelData
                                        text: modelData
                                        color: Kirigami.Theme.linkColor
                                        font.pixelSize: Math.max(6, root.fs - 4)
                                    }
                                }
                            }

                            // --- Example sentences ---
                            ColumnLayout {
                                visible: newWordRevealed && currentNewWord !== null
                                Layout.fillWidth: true
                                Layout.topMargin: Kirigami.Units.smallSpacing
                                spacing: Kirigami.Units.smallSpacing

                                Repeater {
                                    model: newWordRevealed && currentNewWord
                                           ? root.extractExamples(
                                                 currentNewWord.result_json)
                                           : []

                                    delegate: PlasmaComponents3.Label {
                                        text: "• " + modelData
                                        font.pixelSize: Math.max(6, root.fs - 2)
                                        font.italic: true
                                        color: Kirigami.Theme.disabledTextColor
                                        wrapMode: Text.WordWrap
                                        Layout.fillWidth: true
                                    }
                                }
                            }

                            // Engine attribution.
                            PlasmaComponents3.Label {
                                text: currentNewWord && newWordRevealed
                                      && currentNewWord.engine
                                      ? i18n("via %1", currentNewWord.engine)
                                      : ""
                                font.pixelSize: Math.max(5, root.fs - 5)
                                color: Kirigami.Theme.disabledTextColor
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                visible: text.length > 0
                                Layout.topMargin: Kirigami.Units.smallSpacing
                            }

                            // Empty state (no cards).
                            ColumnLayout {
                                visible: currentNewWord === null
                                anchors.centerIn: parent
                                spacing: Kirigami.Units.smallSpacing

                                Kirigami.Icon {
                                    source: "list-add"
                                    implicitWidth: Kirigami.Units.iconSizes.large
                                    implicitHeight: Kirigami.Units.iconSizes.large
                                    Layout.alignment: Qt.AlignHCenter
                                    opacity: 0.4
                                }

                                PlasmaComponents3.Label {
                                    text: i18n("All new words learned!")
                                    font.pixelSize: Math.max(8, root.fs + 2)
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
                                    font.pixelSize: Math.max(6, root.fs - 2)
                                }
                            }

                            Item { Layout.fillHeight: true; visible: currentNewWord !== null }
                        }

                        // Tap to reveal.
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (currentNewWord && !newWordRevealed)
                                    newWordRevealed = true
                            }
                        }
                    }

                    // Tap hint (before reveal).
                    PlasmaComponents3.Label {
                        text: i18n("Tap card to reveal")
                        font.pixelSize: Math.max(6, root.fs - 3)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                        visible: currentNewWord !== null && !newWordRevealed
                    }
                }

                // ===== TAB 2: Stats =====
                ColumnLayout {
                    visible: currentTab === 2
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    // Section heading.
                    RowLayout {
                        Layout.fillWidth: true

                        Kirigami.Heading {
                            text: i18n("Review Statistics")
                            level: 4
                            Layout.fillWidth: true
                        }

                        // Quick refresh button.
                        QQC2.Button {
                            icon.name: "view-refresh"
                            implicitWidth: Kirigami.Units.iconSizes.medium
                            implicitHeight: Kirigami.Units.iconSizes.medium
                            onClicked: refreshStats()
                            QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay
                            QQC2.ToolTip.text: i18n("Refresh")
                            QQC2.ToolTip.visible: hovered
                        }
                    }

                    // Overview metrics — left/right aligned grid.
                    GridLayout {
                        columns: 2
                        Layout.fillWidth: true
                        rowSpacing: Kirigami.Units.smallSpacing
                        columnSpacing: Kirigami.Units.largeSpacing

                        // Left label — right value pattern.

                        PlasmaComponents3.Label { text: i18n("Total reviews:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.total_reviews || 0).toString()
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignRight
                        }

                        PlasmaComponents3.Label { text: i18n("Reviews today:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.reviews_today || 0).toString()
                            font.weight: Font.Bold
                            color: statsCache.reviews_today > 0
                                   ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.textColor
                            Layout.alignment: Qt.AlignRight
                        }

                        PlasmaComponents3.Label { text: i18n("Total cards:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.total_cards || 0).toString()
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignRight
                        }

                        Kirigami.Separator {
                            Layout.fillWidth: true; Layout.columnSpan: 2
                        }

                        PlasmaComponents3.Label {
                            text: i18n("Due now:")
                            font.weight: statsCache.due_now > 0
                                        ? Font.Bold : Font.Normal
                        }
                        PlasmaComponents3.Label {
                            text: (statsCache.due_now || 0).toString()
                            font.weight: Font.Bold
                            color: statsCache.due_now > 0
                                   ? Kirigami.Theme.negativeTextColor
                                   : Kirigami.Theme.textColor
                            Layout.alignment: Qt.AlignRight
                        }

                        PlasmaComponents3.Label { text: i18n("Due this week:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.due_this_week || 0).toString()
                            font.weight: Font.Bold
                            color: statsCache.due_this_week > 0
                                   ? Kirigami.Theme.neutralTextColor
                                   : Kirigami.Theme.textColor
                            Layout.alignment: Qt.AlignRight
                        }

                        PlasmaComponents3.Label { text: i18n("New available:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.new_available || 0).toString()
                            font.weight: Font.Bold
                            color: statsCache.new_available > 0
                                   ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.textColor
                            Layout.alignment: Qt.AlignRight
                        }

                        Kirigami.Separator {
                            Layout.fillWidth: true; Layout.columnSpan: 2
                        }

                        PlasmaComponents3.Label { text: i18n("Avg stability:") }
                        PlasmaComponents3.Label {
                            text: statsCache.avg_stability
                                  ? Number(statsCache.avg_stability).toFixed(1) + " d"
                                  : i18n("—")
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignRight
                        }

                        PlasmaComponents3.Label { text: i18n("Avg difficulty:") }
                        PlasmaComponents3.Label {
                            text: statsCache.avg_difficulty
                                  ? Number(statsCache.avg_difficulty).toFixed(2)
                                  : i18n("—")
                            font.weight: Font.Bold
                            Layout.alignment: Qt.AlignRight
                        }
                    }

                    // Cards by State.
                    Item { Layout.fillHeight: true; visible: statsCache.by_state === undefined }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: statsCache.by_state !== undefined

                        Kirigami.Heading {
                            text: i18n("Cards by State")
                            level: 5
                        }

                        GridLayout {
                            columns: 2
                            Layout.fillWidth: true
                            rowSpacing: Kirigami.Units.smallSpacing
                            columnSpacing: Kirigami.Units.largeSpacing

                            Repeater {
                                model: {
                                    if (!statsCache.by_state) return []
                                    // Sort keys for deterministic order.
                                    var order = ["new", "learning", "review", "relearning"]
                                    var keys = Object.keys(statsCache.by_state)
                                    keys.sort(function (a, b) {
                                        return order.indexOf(a) - order.indexOf(b)
                                    })
                                    return keys
                                }

                                delegate: Item {
                                    Layout.fillWidth: true
                                    Layout.columnSpan: 2
                                    height: Kirigami.Units.gridUnit

                                    RowLayout {
                                        anchors.fill: parent
                                        spacing: Kirigami.Units.largeSpacing

                                        PlasmaComponents3.Label {
                                            text: root.stateLabel(modelData)
                                            Layout.fillWidth: true
                                            color: Kirigami.Theme.disabledTextColor
                                            font.pixelSize: Math.max(6, root.fs - 2)
                                        }

                                        // Progress bar background.
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 6
                                            Layout.alignment: Qt.AlignVCenter
                                            radius: 3
                                            color: Kirigami.Theme.alternateBackgroundColor

                                            Rectangle {
                                                id: stateBar
                                                width: parent.width
                                                       * (statsCache.by_state[modelData]
                                                           / Math.max(1,
                                                               statsCache.total_cards
                                                               || 1))
                                                height: parent.height
                                                radius: 3
                                                color: {
                                                    switch (modelData) {
                                                    case "new":         return Kirigami.Theme.neutralTextColor
                                                    case "learning":    return Kirigami.Theme.neutralTextColor
                                                    case "review":      return Kirigami.Theme.positiveTextColor
                                                    case "relearning":  return Kirigami.Theme.negativeTextColor
                                                    default:            return Kirigami.Theme.disabledTextColor
                                                    }
                                                }
                                            }
                                        }

                                        PlasmaComponents3.Label {
                                            text: statsCache.by_state[modelData].toString()
                                            font.weight: Font.Bold
                                            font.pixelSize: Math.max(6, root.fs - 2)
                                            Layout.minimumWidth: Kirigami.Units.gridUnit * 1.5
                                            horizontalAlignment: Text.AlignRight
                                        }
                                    }
                                }
                            }

                            PlasmaComponents3.Label {
                                visible: !statsCache.by_state
                                         || Object.keys(statsCache.by_state).length === 0
                                text: i18n("No cards yet")
                                color: Kirigami.Theme.disabledTextColor
                                Layout.columnSpan: 2
                                Layout.alignment: Qt.AlignHCenter
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
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
                font.pixelSize: Math.max(6, root.fs - 2)
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
