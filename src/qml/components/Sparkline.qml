import QtQuick
import "../theme.js" as ZT

// Tiny finality-lag sparkline (mirrors the inline-SVG polyline): green when the
// lag is falling, red when rising. `series` is an array of [unix, lag] pairs.
Canvas {
    id: root
    property var series: []
    implicitWidth: 150
    implicitHeight: 26
    onSeriesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var sp = ZT.sparkPoints(series, width, height);
        if (!sp || !sp.pts.length) return;
        ctx.strokeStyle = sp.rising ? ZT.pal.red : ZT.pal.green;
        ctx.lineWidth = 1.5;
        ctx.lineJoin = "round";
        ctx.beginPath();
        for (var i = 0; i < sp.pts.length; i++) {
            if (i === 0) ctx.moveTo(sp.pts[i].x, sp.pts[i].y);
            else ctx.lineTo(sp.pts[i].x, sp.pts[i].y);
        }
        ctx.stroke();
    }
}
