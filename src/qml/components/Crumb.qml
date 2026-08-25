import QtQuick
import QtQuick.Layouts
import "../theme.js" as ZT
RowLayout {
    property var items: []   // [{label, action}] - action() called on click; last = current (no link)
    spacing: 6
    Repeater { model: items
        delegate: RowLayout { required property var modelData; required property int index; spacing: 6
            Text { text: modelData.label; font.pixelSize: 12
                color: (index < items.length - 1 && modelData.action) ? ZT.pal.link : ZT.pal.soft
                MouseArea { anchors.fill: parent; enabled: index < items.length - 1 && !!modelData.action
                    cursorShape: Qt.PointingHandCursor; onClicked: if (modelData.action) modelData.action() } }
            Text { visible: index < items.length - 1; text: "/"; color: ZT.pal.soft; font.pixelSize: 12 }
        }
    }
}
