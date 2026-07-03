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

    // State.
    property bool pinned: false

    // Tab navigation
    property int currentTab: 0  // 0=Review, 1=New, 2=Stats

    // Currently displayed card (from due list)
    property var currentCard: null
    property var dueCards: []
    property var newCards: []
    property int currentCardIndex: 0
    property bool answerRevealed: false

    // Stats cache
    property var statsCache: ({})

    // DB bridge.
    property RecallHelperQml recall: RecallHelperQml {}

    // Helpers.
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
        newCards = recall.parseArray(recall.getNewCards(20))
        refreshStats()
    }

    function refreshStats() {
        statsCache = recall.parseObject(recall.getStats())
    }

    function rateCard(rating) {
        if (!currentCard) return
        var result = recall.parseObject(
            recall.reviewCard(currentCard.id, rating))
        if (result.card_id) {
            // Remove the reviewed card from the due list
            dueCards.splice(currentCardIndex, 1)
            // Advance or loop
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

    function learnNewCard(translationId) {
        var cid = recall.createCard(translationId)
        if (cid && cid.length > 0) {
            // Switch to review tab and refresh
            currentTab = 0
            refreshDueCards()
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
        Layout.minimumWidth: 380
        Layout.minimumHeight: 400
        Layout.preferredWidth: 440
        Layout.preferredHeight: 520

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
                    QQC2.ToolTip.text: root.pinned ? i18n("Keep open when switching windows") : i18n("Pin panel open")
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

                // TAB 0: Review.
                ColumnLayout {
                    visible: currentTab === 0
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    // Card counter
                    PlasmaComponents3.Label {
                        text: currentCard
                              ? i18n("Card %1 of %2",
                                     currentCardIndex + 1, dueCards.length)
                              : ""
                        font.pixelSize: Math.max(6, root.fontSizeBase - 3)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                    }

                    // Flashcard
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
                            spacing: Kirigami.Units.largeSpacing

                            // Source text
                            Kirigami.Heading {
                                id: sourceText
                                text: currentCard ? currentCard.input_text : ""
                                level: 3
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.weight: Font.Bold
                                visible: currentCard !== null
                            }

                            // Separator
                            Kirigami.Separator {
                                Layout.fillWidth: true
                                visible: answerRevealed && currentCard !== null
                            }

                            // Translation (revealed)
                            PlasmaComponents3.Label {
                                id: targetText
                                text: {
                                    if (!currentCard || !answerRevealed) return ""
                                    if (!currentCard.result_json) return ""
                                    var j = JSON.parse(currentCard.result_json)
                                    if (j.translation) {
                                        try {
                                            var t = JSON.parse(j.translation)
                                            return t.translate || j.translation
                                        } catch(e) {
                                            return j.translation
                                        }
                                    }
                                    return ""
                                }
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                font.pixelSize: Math.max(8, root.fontSizeBase + 2)
                                visible: answerRevealed && currentCard !== null
                            }

                            // Retrievability indicator (when revealed)
                            PlasmaComponents3.Label {
                                visible: answerRevealed && currentCard !== null
                                text: currentCard && currentCard.stability > 0
                                      ? i18n("Recall probability: %1%",
                                             Math.round(
                                                 (1.0 - 0) * 100))
                                      : ""
                                font.pixelSize: Math.max(6, root.fontSizeBase - 4)
                                color: Kirigami.Theme.disabledTextColor
                                Layout.alignment: Qt.AlignHCenter
                            }

                            // Empty state
                            PlasmaComponents3.Label {
                                visible: currentCard === null
                                text: i18n("No cards due for review.\nAdd translations with Lingua Spanner, then come back!")
                                color: Kirigami.Theme.disabledTextColor
                                font.italic: true
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignCenter
                                horizontalAlignment: Text.AlignHCenter
                            }

                            Item { Layout.fillHeight: true }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                if (currentCard && !answerRevealed)
                                    answerRevealed = true
                            }
                        }
                    }

                    // Rating buttons (shown after reveal)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.smallSpacing
                        visible: answerRevealed && currentCard !== null

                        QQC2.Button {
                            text: i18n("Again")
                            icon.name: "edit-delete"
                            Layout.fillWidth: true
                            onClicked: rateCard(1)
                        }
                        QQC2.Button {
                            text: i18n("Hard")
                            icon.name: "arrow-down"
                            Layout.fillWidth: true
                            onClicked: rateCard(2)
                        }
                        QQC2.Button {
                            text: i18n("Good")
                            icon.name: "arrow-right"
                            Layout.fillWidth: true
                            onClicked: rateCard(3)
                        }
                        QQC2.Button {
                            text: i18n("Easy")
                            icon.name: "arrow-up"
                            Layout.fillWidth: true
                            onClicked: rateCard(4)
                        }
                    }

                    // Hint
                    PlasmaComponents3.Label {
                        visible: currentCard !== null && !answerRevealed
                        text: i18n("Tap card to reveal answer")
                        font.pixelSize: Math.max(6, root.fontSizeBase - 3)
                        color: Kirigami.Theme.disabledTextColor
                        Layout.alignment: Qt.AlignHCenter
                    }
                }

                // TAB 1: New Words.
                ColumnLayout {
                    visible: currentTab === 1
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: i18n("New Words Available")
                        level: 4
                    }

                    PlasmaComponents3.Label {
                        text: newCards.length === 0
                              ? i18n("No new words to learn")
                              : i18n("%1 words").arg(newCards.length) + " " + i18n("to learn")
                        color: Kirigami.Theme.disabledTextColor
                        visible: true
                    }

                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: newCards
                        clip: true
                        spacing: Kirigami.Units.smallSpacing

                        delegate: Rectangle {
                            width: parent.width
                            height: Kirigami.Units.gridUnit * 2.5
                            color: Kirigami.Theme.backgroundColor
                            radius: 4
                            border.color: Kirigami.Theme.alternateBackgroundColor
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Kirigami.Units.smallSpacing

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    PlasmaComponents3.Label {
                                        text: modelData.input_text
                                        font.weight: Font.Bold
                                        elide: Text.ElideRight
                                    }
                                    PlasmaComponents3.Label {
                                        text: {
                                            if (!modelData) return ""
                                            var src = modelData.source_lang || "?"
                                            var tgt = modelData.target_lang || "?"
                                            return src + " → " + tgt
                                        }
                                        font.pixelSize: Math.max(6, root.fontSizeBase - 4)
                                        color: Kirigami.Theme.disabledTextColor
                                    }
                                }

                                QQC2.Button {
                                    text: i18n("Learn")
                                    icon.name: "list-add"
                                    onClicked: learnNewCard(modelData.id)
                                }
                            }
                        }

                        PlasmaComponents3.Label {
                            anchors.centerIn: parent
                            text: i18n("Nothing new")
                            color: Kirigami.Theme.disabledTextColor
                            visible: parent.count === 0
                        }
                    }
                }

                // TAB 2: Stats.
                ColumnLayout {
                    visible: currentTab === 2
                    anchors.fill: parent
                    spacing: Kirigami.Units.smallSpacing

                    Kirigami.Heading {
                        text: i18n("Review Statistics")
                        level: 4
                    }

                    GridLayout {
                        columns: 2
                        Layout.fillWidth: true
                        rowSpacing: Kirigami.Units.smallSpacing
                        columnSpacing: Kirigami.Units.largeSpacing

                        PlasmaComponents3.Label { text: i18n("Total reviews:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.total_reviews || 0).toString()
                            font.weight: Font.Bold
                        }

                        PlasmaComponents3.Label { text: i18n("Due now:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.due_now || 0).toString()
                            font.weight: Font.Bold
                            color: statsCache.due_now > 0
                                   ? Kirigami.Theme.positiveTextColor
                                   : Kirigami.Theme.textColor
                        }

                        PlasmaComponents3.Label { text: i18n("New available:") }
                        PlasmaComponents3.Label {
                            text: (statsCache.new_available || 0).toString()
                            font.weight: Font.Bold
                        }
                    }

                    // Breakdown by state
                    Kirigami.Separator { Layout.fillWidth: true }

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
                            model: statsCache.by_state
                                     ? Object.keys(statsCache.by_state) : []

                            delegate: Item {
                                Layout.fillWidth: true
                                Layout.columnSpan: 2
                                height: Kirigami.Units.gridUnit
                                RowLayout {
                                    anchors.fill: parent
                                    PlasmaComponents3.Label {
                                        text: modelData
                                        Layout.fillWidth: true
                                    }
                                    PlasmaComponents3.Label {
                                        text: statsCache.by_state[modelData].toString()
                                        font.weight: Font.Bold
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
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            // STATUS BAR.
            PlasmaComponents3.Label {
                text: {
                    var parts = []
                    parts.push(i18n("Due: %1", statsCache.due_now || 0))
                    parts.push(i18n("New: %1", statsCache.new_available || 0))
                    parts.push(i18n("Total: %1", statsCache.total_reviews || 0))
                    return parts.join("  ·  ")
                }
                color: Kirigami.Theme.disabledTextColor
                font.pixelSize: Math.max(6, root.fontSizeBase - 2)
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
