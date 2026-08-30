import QtQuick
import "../theme"

// .chips a — a small mono pill for an account/id, optionally with a trailing
// muted annotation (e.g. token symbol + role), clickable to navigate.
Rectangle {
    id: root
    property string text: ""
    property string annotation: ""     // e.g. "· GOLD holder"
    property bool clickable: false
    signal clicked()

    implicitWidth: row.implicitWidth + 16
    implicitHeight: row.implicitHeight + 6
    radius: 6
    color: mouse.containsMouse && clickable ? ZTheme.chipHover : ZTheme.chipBg
    border.width: 1; border.color: ZTheme.line

    MouseArea { id: mouse; anchors.fill: parent; enabled: root.clickable
        hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.clicked() }

    Row {
        id: row
        anchors.centerIn: parent; spacing: 5
        Text { text: root.text; color: root.clickable ? ZTheme.link : ZTheme.fg
            font.pixelSize: 12; font.family: "ui-monospace, Menlo, Consolas, monospace" }
        Text { visible: root.annotation.length > 0; text: root.annotation; color: ZTheme.muted; font.pixelSize: 12 }
    }
}
