import QtQuick
import QtQuick.Controls   // ToolTip

// Small pill badge (mirrors .badge / .b-ty-* / .b-vis-* / .fbadge / .vbadge).
Rectangle {
    id: root
    property string text: ""
    property color bg: "#f1f1f3"
    property color fg: "#52525b"
    property color bd: "#e0e0e4"
    property bool italic: false          // for the ≈guess span
    property int fontPx: 11
    property string tip: ""              // hover text; the web renders this as title=

    implicitWidth: label.implicitWidth + 18
    implicitHeight: label.implicitHeight + 6
    radius: 6
    color: bg
    border.width: 1
    border.color: bd

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: root.fg
        font.pixelSize: root.fontPx
        font.weight: Font.DemiBold
        font.italic: root.italic
        font.family: "-apple-system, Segoe UI, Roboto, sans-serif"
    }

    ToolTip.visible: tip !== "" && hover.hovered
    ToolTip.text: tip
    ToolTip.delay: 400
    HoverHandler { id: hover }
}
