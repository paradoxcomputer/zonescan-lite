import QtQuick
import "../theme"
import "../theme.js" as ZT

// Tiny finality-lag sparkline (mirrors the inline-SVG polyline): green when the
// lag is falling, red when rising. `series` is an array of [unix, lag] pairs.
Canvas {
    id: root
    property var series: []
    implicitWidth: 150
    implicitHeight: 26

    // HAZARD: onPaint is a SIGNAL HANDLER, not a binding - the engine records no dependency
    // on ZTheme, and requestPaint() only fired on onSeriesChanged/onWidthChanged. A chart
    // whose series is idle (a settled chain updates every few minutes) therefore kept
    // stroking the OLD theme's colour long after the flip. Naming the two colours as real
    // properties gives them change signals; repainting on those signals is the whole fix,
    // and it lives inside this file - no plumbing through ZStatCard or HomePage.
    readonly property color okC:  ZTheme.green
    readonly property color badC: ZTheme.red

    onSeriesChanged: requestPaint()
    onWidthChanged: requestPaint()
    onOkCChanged: requestPaint()
    onBadCChanged: requestPaint()
    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        var sp = ZT.sparkPoints(series, width, height);
        if (!sp || !sp.pts.length) return;
        ctx.strokeStyle = sp.rising ? root.badC : root.okC;
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
