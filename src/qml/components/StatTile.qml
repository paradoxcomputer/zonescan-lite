import QtQuick
import "../theme.js" as ZT
Rectangle {
    property string k: ""
    property string v: "-"
    property string sub: ""
    property bool muted: false          // render the value muted/normal (e.g. "no sequencer RPC")
    color: "#ffffff"
    implicitHeight: c.implicitHeight + 32
    Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: ZT.pal.line }
    Column { id: c; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 16 } spacing: 4
        Text { text: k.toUpperCase(); color: ZT.pal.soft; font.pixelSize: 11; font.letterSpacing: 0.5; width: parent.width; wrapMode: Text.WordWrap }
        Text { text: v; width: parent.width; wrapMode: Text.WrapAnywhere
            color: muted ? ZT.pal.muted : ZT.pal.navy
            font.pixelSize: muted ? 14 : 20; font.weight: muted ? Font.Normal : Font.DemiBold
            font.family: "ui-monospace, Menlo, Consolas, monospace" }
        Text { visible: sub.length > 0; text: sub; color: ZT.pal.muted; font.pixelSize: 11 }
    }
}
