import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme.js" as ZT

// One row of the 7-col tx feed: Hash · Visibility · Type · Status · Block · Age · Zone.
// theme.js reads live state/PROGS/GUESS from module vars; `explorer.rev` bumps when
// those update, so state-dependent cells (Type guess, Status finality) re-evaluate.
//
// Column widths are handed down by TxTable so header and rows stay aligned; a width of 0
// means the column is dropped at this window size.
Rectangle {
    id: root
    property var tx: ({})
    property var explorer: null
    property bool showZone: true
    property int wHash: 150
    property int wVis: 74
    property int wType: 118
    property int wStatus: 120
    property int wBlock: 90
    property int wAge: 96
    readonly property int rev: explorer ? explorer.rev : 0
    signal clicked()

    implicitHeight: 42
    color: mouse.containsMouse || root.activeFocus ? ZT.pal.rowHover : "transparent"
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZT.pal.line }
    Rectangle { visible: root.activeFocus; anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 2; color: ZT.pal.link }
    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.clicked(); } }

    // Every control in the feed was a bare MouseArea, so none of it could be reached without
    // a pointer. Tab walks the rows; Enter/Space opens one; Ctrl+C copies its hash.
    activeFocusOnTab: true
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.clicked(); e.accepted = true; }
        else if (e.key === Qt.Key_C && (e.modifiers & Qt.ControlModifier)) {
            if (root.explorer) root.explorer.copyText(root.tx.hash, "Hash");
            e.accepted = true;
        }
    }

    readonly property var visB: { root.rev; return ZT.visBadgeFor(root.tx); }
    readonly property var tyB:  { root.rev; return ZT.typeBadgeFor(root.tx); }
    readonly property string finKey: { root.rev; return ZT.finTier(root.tx); }

    RowLayout {
        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
        spacing: 12

        // Hash (+ a copy affordance on hover — identifiers were previously uncopyable)
        Item {
            Layout.preferredWidth: root.wHash; Layout.fillHeight: true
            // Non-blocking, unlike the button's own MouseArea: binding copyBtn.visible to the
            // ROW's containsMouse made the button cancel the very hover that revealed it.
            HoverHandler { id: cellHover }
            Text {
                id: hashT
                anchors { left: parent.left; right: copyBtn.visible ? copyBtn.left : parent.right; verticalCenter: parent.verticalCenter }
                elide: Text.ElideMiddle
                text: ZT.sh(root.tx.hash || "", 12, 8); color: ZT.pal.link
                font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace"
            }
            Rectangle {
                id: copyBtn
                visible: (cellHover.hovered || copyMa.containsMouse) && !!root.tx.hash
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 18; height: 18; radius: 4
                color: copyMa.containsMouse ? ZT.pal.line : "transparent"
                Text { anchors.centerIn: parent; text: "⧉"; color: ZT.pal.soft; font.pixelSize: 11 }
                MouseArea {
                    id: copyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: { if (root.explorer) root.explorer.copyText(root.tx.hash, "Hash"); }
                    ToolTip.visible: containsMouse; ToolTip.text: "Copy hash"
                }
            }
        }
        // Visibility badge
        ZBadge {
            Layout.preferredWidth: root.wVis; visible: root.wVis > 0
            text: root.visB.text; bg: root.visB.bg; fg: root.visB.fg; bd: root.visB.bd
        }
        // Type badge (verified name or muted/italic ≈guess)
        ZBadge {
            Layout.preferredWidth: root.wType; visible: root.wType > 0
            text: root.tyB.text; italic: root.tyB.italic
            bg: root.tyB.bg; fg: root.tyB.fg; bd: root.tyB.bd
        }
        // Status (finality)
        Item {
            Layout.preferredWidth: root.wStatus; visible: root.wStatus > 0
            ZBadge {
                visible: !!root.finKey
                anchors.verticalCenter: parent.verticalCenter
                text: root.finKey ? ZT.finBadge[root.finKey].label : ""
                bg: root.finKey ? ZT.finBadge[root.finKey].bg : "transparent"
                fg: root.finKey ? ZT.finBadge[root.finKey].fg : ZT.pal.soft
                bd: "transparent"
            }
            Text { visible: !root.finKey; anchors.verticalCenter: parent.verticalCenter
                text: "-"; color: ZT.pal.soft; font.pixelSize: 12 }
        }
        // Block
        Text {
            Layout.preferredWidth: root.wBlock
            color: root.tx.kind === "raw" ? ZT.pal.soft : ZT.pal.fg
            font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace"
            text: root.tx.kind === "raw"
                ? ("L1 " + (root.tx.slot != null ? ZT.num(root.tx.slot) : "-"))
                : ("#" + ZT.num(root.tx.block_id))
        }
        // Age
        Text {
            Layout.preferredWidth: root.wAge; visible: root.wAge > 0
            text: ZT.ageOf(root.tx); color: ZT.pal.muted; font.pixelSize: 12
        }
        // Zone — the header cell honoured showZone but this one never did, so a zone,
        // program or token feed repeated one identical channel down its widest column.
        Text {
            Layout.fillWidth: true; elide: Text.ElideRight; visible: root.showZone
            // aliasOf reads a curated static map, so unlike the live-state helpers around it
            // this needs no `rev` dependency to stay correct.
            text: ZT.aliasOf(root.tx.channel) || root.tx.channel_short || ZT.sh(root.tx.channel || "", 8, 4)
            color: ZT.pal.link; font.pixelSize: 12
            font.family: "ui-monospace, Menlo, Consolas, monospace"
        }
        Item { Layout.fillWidth: !root.showZone; visible: !root.showZone }
    }
}
