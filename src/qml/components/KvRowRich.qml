import QtQuick
import QtQuick.Layouts
import "../theme"

// .kv row with a rich-HTML value (instrText / guess / decoded output). The value
// is an HTML fragment from theme.js; links route via explorer.routeLink.
RowLayout {
    property string k: ""
    property string vHtml: ""
    property var explorer: null
    visible: vHtml.length > 0
    spacing: 18
    Text { Layout.preferredWidth: 150; Layout.alignment: Qt.AlignTop
        text: k; color: ZTheme.soft; font.pixelSize: 12 }
    RichLabel {
        Layout.fillWidth: true
        explorer: parent.explorer
        text: vHtml
        font.pixelSize: 13
    }
}
