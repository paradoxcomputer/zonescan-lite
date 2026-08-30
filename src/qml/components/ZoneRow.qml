import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme"
import "../theme.js" as ZT

// .srow — one zone/sequencer row (mirrors renderSeqs): status dot, title
// (short hex + data/version/consistency badges), Channel ID, metrics
// (L2 tip · L1 bal · keys · blk/min + seq-tip note + activity chip), ALIVE/IDLE.
//
// Laid out with Layouts rather than hand-computed widths. The previous version sized the
// middle column as `parent.width - 8 - 10 - stStatus.width - 10` and then put an UNCONSTRAINED
// Row inside it ("CHANNEL ID <hex>  SEQUENCER VERSION <badge>"), which is ~300px of content in
// a 340px panel: it overflowed the column, escaped the panel and was clipped mid-word. The
// title also reserved a hardcoded 130px for badges that are usually absent, so it truncated
// even with room to spare. Every flexible cell now elides inside a real layout instead.
Rectangle {
    id: root
    property var seq: ({})
    property bool selected: false
    signal clicked()

    implicitHeight: body.implicitHeight + 22
    height: implicitHeight
    color: mouse.containsMouse || root.activeFocus ? ZTheme.rowHover : (root.selected ? ZTheme.rowSel : "transparent")
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }

    readonly property bool alive: !!root.seq.alive
    readonly property string shortHex: root.seq.channel_short || ZT.sh(root.seq.channel || "", 8, 4)
    readonly property var cons: ZT.consBadge(root.seq)
    readonly property var act: ZT.activityChip(root.seq)
    readonly property var settle: ZT.settleBadge(root.seq)
    readonly property var verC: ZTheme.verBadge[root.seq.version] || ZTheme.verUnknown

    MouseArea { id: mouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: { root.forceActiveFocus(); root.clicked(); } }

    // Tab-reachable: the zone list was pointer-only, like every other MouseArea control.
    activeFocusOnTab: true
    Keys.onPressed: function (e) {
        if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter || e.key === Qt.Key_Space) { root.clicked(); e.accepted = true; }
    }
    Rectangle { visible: root.activeFocus; anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: 2; color: ZTheme.link }

    RowLayout {
        id: body
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: 16; rightMargin: 16; topMargin: 11 }
        spacing: 10

        Rectangle { Layout.alignment: Qt.AlignVCenter
            implicitWidth: 8; implicitHeight: 8; radius: 4
            color: root.alive ? ZTheme.green : ZTheme.silver }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 3

            // title + data / version / consistency badges
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Text {
                    Layout.fillWidth: true                    // takes what the badges leave
                    elide: Text.ElideRight
                    text: ZT.zoneTitle(root.seq)
                    color: ZTheme.link; font.pixelSize: 13
                    font.family: "ui-monospace, Menlo, Consolas, monospace"
                }
                Rectangle {                                    // .v-data
                    visible: ZT.dataBadge(root.seq)
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: dl.implicitWidth + 12; implicitHeight: dl.implicitHeight + 2; radius: 5
                    color: ZTheme.verBadge.data.bg
                    Text { id: dl; anchors.centerIn: parent; text: "DATA"; color: ZTheme.verBadge.data.fg
                        font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.3 }
                }
                Rectangle {                                    // version, badge only
                    visible: !!root.seq.version
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: verL.implicitWidth + 12; implicitHeight: verL.implicitHeight + 3; radius: 5
                    color: root.verC.bg
                    Text { id: verL; anchors.centerIn: parent; text: (root.seq.version || "").toUpperCase()
                        color: root.verC.fg; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.3 }
                }
            }

            // consistency (✓ links ok · 420 gaps / ⚠ inconsistent) + settling — their own line,
            // because the consistency text is long enough to squeeze the title out of
            // existence when placed beside it.
            RowLayout {
                visible: !!root.cons || !!root.settle
                Layout.fillWidth: true
                spacing: 6
                Text {
                    visible: !!root.cons
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: root.cons ? root.cons.text : ""
                    color: root.cons && root.cons.ok ? ZTheme.green : ZTheme.red
                    font.pixelSize: 11; font.weight: Font.Bold
                    ToolTip.visible: hh.hovered && !!root.cons
                    ToolTip.text: root.cons ? root.cons.title : ""
                    HoverHandler { id: hh }
                }
                Item { Layout.fillWidth: !root.cons; visible: !root.cons }
                // settling / not settling — the field exists on every sequencer and was never
                // rendered, so a zone that had stopped settling looked exactly like one that
                // had not.
                Rectangle {
                    id: setChip
                    visible: !!root.settle
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: setL.implicitWidth + 12; implicitHeight: setL.implicitHeight + 3; radius: 5
                    color: root.settle ? root.settle.bg : "transparent"
                    Text { id: setL; anchors.centerIn: parent
                        text: root.settle ? root.settle.text : ""
                        color: root.settle ? root.settle.fg : ZTheme.soft
                        font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.2 }
                    ToolTip.visible: sh2.hovered && !!root.settle
                    ToolTip.text: root.settle ? root.settle.title : ""
                    HoverHandler { id: sh2 }
                }
            }

            // channel id
            RowLayout {
                Layout.fillWidth: true; spacing: 5
                Text { text: "CHANNEL ID"; color: ZTheme.soft
                    font.pixelSize: 10; font.weight: Font.DemiBold; font.letterSpacing: 0.3 }
                Text { Layout.fillWidth: true; elide: Text.ElideRight
                    text: root.shortHex; color: ZTheme.soft; font.pixelSize: 11
                    font.family: "ui-monospace, Menlo, Consolas, monospace" }
            }

            // metrics + activity chip
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Text {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: ZTheme.muted; font.pixelSize: 11
                    text: {
                        var s = root.seq;
                        var line = "L2 " + ZT.l2Tip(s) + " · L1 bal " + (s.l1_balance != null ? ZT.num(s.l1_balance) : "-")
                                 + " · " + (s.l1_signers || 0) + " key(s)";
                        var bpm = ZT.bpmStr(s); if (bpm) line += " · " + bpm;
                        line += ZT.tipNote(s);
                        return line;
                    }
                }
                Rectangle {
                    id: actChip
                    visible: !!root.act
                    Layout.alignment: Qt.AlignVCenter
                    property var fc: root.act ? ZTheme.finBadge[root.act.tier] : ZTheme.finBadge.pend
                    implicitWidth: acl.implicitWidth + 10; implicitHeight: acl.implicitHeight + 2; radius: 4
                    color: fc.bg
                    Text { id: acl; anchors.centerIn: parent; text: root.act ? root.act.text : ""
                        color: actChip.fc.fg; font.pixelSize: 9; font.weight: Font.DemiBold }
                    ToolTip.visible: ah.hovered && !!root.act
                    ToolTip.text: root.act ? root.act.title : ""
                    HoverHandler { id: ah }
                }
            }
        }

        Rectangle {
            id: stStatus
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: stLabel.implicitWidth + 14; implicitHeight: stLabel.implicitHeight + 4; radius: 6
            color: root.alive ? ZTheme.aliveChip : ZTheme.idleBg
            Text { id: stLabel; anchors.centerIn: parent
                text: root.alive ? "ALIVE" : "IDLE"
                color: root.alive ? ZTheme.green : ZTheme.soft
                font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.4 }
        }
    }
}
