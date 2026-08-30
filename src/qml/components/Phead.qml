import QtQuick
import "../theme"
Rectangle {
    property string title: ""
    property string count: ""
    default property alias extra: extraSlot.data
    width: parent ? parent.width : 0; height: 46
    gradient: Gradient { GradientStop { position: 0; color: ZTheme.pheadA } GradientStop { position: 1; color: ZTheme.pheadB } }
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
    Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
        text: title; color: ZTheme.navy; font.pixelSize: 14; font.weight: Font.DemiBold }
    Row { id: extraSlot; anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 } spacing: 8
        Text { visible: count.length > 0; text: count; color: ZTheme.soft; font.pixelSize: 12
            font.family: "ui-monospace, Menlo, Consolas, monospace" } }
}
