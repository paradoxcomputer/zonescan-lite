import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme.js" as ZT

// .kv row: 150px soft key + mono break-all value.
//
// The value is a TextEdit, not a Text, so it can be selected and copied. Every identifier in
// this app used to be an unselectable Text: the explorer accepted a pasted hash but offered
// no way to get one out of it. `copyable` adds an explicit button for the same reason.
RowLayout {
    id: row
    property string k: ""
    property string v: ""
    property bool mono: true
    property bool copyable: true
    property var explorer: null
    property string copyLabel: ""          // defaults to the key
    visible: v.length > 0
    spacing: 18
    Text { Layout.preferredWidth: 150; Layout.alignment: Qt.AlignTop
        text: row.k; color: ZT.pal.soft; font.pixelSize: 12 }
    TextEdit {
        Layout.fillWidth: true
        text: row.v; color: ZT.pal.fg; font.pixelSize: 13
        readOnly: true
        selectByMouse: true
        wrapMode: TextEdit.WrapAnywhere
        textFormat: TextEdit.PlainText
        font.family: row.mono ? "ui-monospace, Menlo, Consolas, monospace" : "-apple-system, Segoe UI, sans-serif"
    }
    Rectangle {
        Layout.alignment: Qt.AlignTop
        visible: row.copyable && !!row.explorer && row.v.length > 0
        implicitWidth: 20; implicitHeight: 18; radius: 4
        color: copyMa.containsMouse ? ZT.pal.line : "transparent"
        Text { anchors.centerIn: parent; text: "⧉"; color: ZT.pal.soft; font.pixelSize: 11 }
        MouseArea {
            id: copyMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: row.explorer.copyText(row.v, row.copyLabel || row.k || "Value")
            ToolTip.visible: containsMouse; ToolTip.text: "Copy"
        }
    }
}
