import QtQuick
import "../theme.js" as ZT

// .card — white→#f6f6f8 gradient card with .k label / .v mono value / .s sublabel.
Rectangle {
    id: root
    property string k: ""
    property string v: "-"
    property string s: ""
    property var series: null          // when set, draws a finality-lag sparkline

    implicitHeight: col.implicitHeight + 32
    radius: 12
    border.width: 1
    border.color: ZT.pal.line
    gradient: Gradient {
        GradientStop { position: 0.0; color: "#ffffff" }
        GradientStop { position: 1.0; color: "#f6f6f8" }
    }

    Column {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top
                  leftMargin: 18; rightMargin: 18; topMargin: 16 }
        spacing: 3
        Text {
            text: root.k.toUpperCase(); color: ZT.pal.soft
            font.pixelSize: 10; font.letterSpacing: 0.7; font.weight: Font.DemiBold
            font.family: "-apple-system, Segoe UI, Roboto, sans-serif"
        }
        Text {
            text: root.v; color: ZT.pal.navy
            font.pixelSize: 21; font.weight: Font.DemiBold
            font.family: "ui-monospace, Menlo, Consolas, monospace"
        }
        Text {
            visible: root.s.length > 0
            text: root.s; color: ZT.pal.muted; font.pixelSize: 12
            font.family: "-apple-system, Segoe UI, Roboto, sans-serif"
        }
        Sparkline {
            visible: root.series && root.series.length > 1
            width: 150; height: 26
            series: root.series || []
        }
    }
}
