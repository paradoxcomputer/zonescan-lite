import QtQuick
import QtQuick.Controls   // ToolTip
import "../theme"

// Small pill badge (mirrors .badge / .b-ty-* / .b-vis-* / .fbadge / .vbadge).
Rectangle {
    id: root
    property string text: ""
    property color bg: ZTheme.bdgGreyBg
    property color fg: ZTheme.bdgGreyFg
    property color bd: ZTheme.bdgGreyBd
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
