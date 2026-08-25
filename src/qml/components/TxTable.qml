import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme.js" as ZT

// The shared 7-col tx feed: sticky column header + scrolling rows + infinite
// scroll. Used by every list view (home / zone / program / token / account).
//
// Column widths live HERE and are handed to each row, so the header and the rows cannot
// drift apart. Below `compactAt` the middle columns drop out rather than being clipped: the
// fixed widths summed to ~752px inside a clipping panel with no horizontal scroll, so on a
// narrow window AGE and ZONE were simply cut off.
Column {
    id: root
    property var model: []
    property var explorer: null
    property bool showZone: true
    property bool loading: false          // a page fetch is in flight
    property bool done: false             // no more pages
    property string emptyText: "no transactions"
    property string loadingText: "loading transactions…"
    property string doneNote: ""          // shown under the last row when the feed is exhausted
    readonly property int compactAt: 820
    readonly property bool compact: root.width > 0 && root.width < compactAt
    readonly property bool ultraCompact: root.width > 0 && root.width < 560

    readonly property int wHash:   root.ultraCompact ? 116 : 150
    readonly property int wVis:    root.ultraCompact ? 0 : 74
    readonly property int wType:   root.compact ? 0 : 118
    readonly property int wStatus: root.compact ? 0 : 120
    readonly property int wBlock:  root.ultraCompact ? 74 : 90
    readonly property int wAge:    root.ultraCompact ? 0 : 96

    signal atEnd()                        // scrolled near the bottom - fetch the next page
    signal rowClicked(var tx)

    Rectangle {
        width: parent.width; height: 36; color: ZT.pal.theadBg
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZT.pal.line }
        RowLayout { anchors { fill: parent; leftMargin: 16; rightMargin: 16 } spacing: 12
            Text { Layout.preferredWidth: root.wHash; text: "TXN HASH"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Text { Layout.preferredWidth: root.wVis; visible: root.wVis > 0; text: "VIS"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Text { Layout.preferredWidth: root.wType; visible: root.wType > 0; text: "TYPE"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Text { Layout.preferredWidth: root.wStatus; visible: root.wStatus > 0; text: "STATUS"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Text { Layout.preferredWidth: root.wBlock; text: "BLOCK"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Text { Layout.preferredWidth: root.wAge; visible: root.wAge > 0; text: "AGE"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Text { Layout.fillWidth: true; visible: root.showZone; text: "ZONE"; color: ZT.pal.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
            Item { Layout.fillWidth: !root.showZone; visible: !root.showZone }
        }
    }
    ListView {
        id: list
        width: parent.width; height: root.height - 36 - (footer.visible ? footer.height : 0); clip: true
        model: root.model
        boundsBehavior: Flickable.StopAtBounds
        delegate: TxFeedRow {
            required property var modelData
            width: ListView.view ? ListView.view.width : parent.width
            tx: modelData; explorer: root.explorer
            showZone: root.showZone
            wHash: root.wHash; wVis: root.wVis; wType: root.wType
            wStatus: root.wStatus; wBlock: root.wBlock; wAge: root.wAge
            onClicked: root.rowClicked(modelData)
        }
        ScrollBar.vertical: ScrollBar { }
        onContentYChanged: {
            if (!root.done && !root.loading && contentHeight > 0
                && contentY + height >= contentHeight - 300) root.atEnd();
        }
        Text { anchors.centerIn: parent; visible: list.count === 0 && !root.loading
            text: root.emptyText; color: ZT.pal.soft; font.pixelSize: 13 }
        // First fetch: the empty label was gated on !loading and the footer on count > 0, so
        // the whole body rendered blank for up to the 15s request ceiling and then flipped
        // straight to "no transactions".
        Column {
            anchors.centerIn: parent; spacing: 8; visible: list.count === 0 && root.loading
            BusyIndicator { running: parent.visible; anchors.horizontalCenter: parent.horizontalCenter; implicitWidth: 28; implicitHeight: 28 }
            Text { text: root.loadingText; color: ZT.pal.soft; font.pixelSize: 13; anchors.horizontalCenter: parent.horizontalCenter }
        }
    }
    // loading footer (pulsing dots) — while a page fetch is in flight
    Rectangle {
        id: footer
        width: parent.width; height: 34; color: "transparent"
        visible: (root.loading && list.count > 0) || (root.done && root.doneNote !== "" && list.count > 0)
        Text { visible: root.done && !root.loading; anchors.centerIn: parent
            text: root.doneNote; color: ZT.pal.soft; font.pixelSize: 11 }
        Row {
            anchors.centerIn: parent; spacing: 4; visible: root.loading
            Text { text: "loading"; color: ZT.pal.soft; font.pixelSize: 12 }
            Repeater { model: 3
                Rectangle { width: 6; height: 6; radius: 3; color: ZT.pal.soft; anchors.verticalCenter: parent.verticalCenter
                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        PauseAnimation { duration: index * 150 }
                        NumberAnimation { from: 0.25; to: 1; duration: 400 }
                        NumberAnimation { from: 1; to: 0.25; duration: 400 }
                        PauseAnimation { duration: (2 - index) * 150 }
                    }
                }
            }
        }
    }
}
