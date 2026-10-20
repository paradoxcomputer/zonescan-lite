import QtQuick
import "../theme"

// Renders an HTML fragment produced by theme.js (instrText / txAction / decode /
// chanLabel …) as QML rich text. Links use a compact scheme —
//   wallet:<channel>:<account>  token:<channel>:<def>
//   program:<channel>:<prog>    zone:<channel>
// — which onLinkActivated forwards to the router via `explorer.routeLink(url)`.
//
// routeLink also accepts `tx:<channel>:<hash>`. The one emitter is the program page's
// "Deployed in" row (LEZ v0.3), which links the deploy transaction; rows navigate to a
// transaction directly via navTx().
Text {
    id: root
    property var explorer: null
    textFormat: Text.RichText
    wrapMode: Text.WordWrap
    color: ZTheme.fg
    font.pixelSize: 13
    font.family: "-apple-system, Segoe UI, Roboto, sans-serif"
    linkColor: ZTheme.link
    onLinkActivated: function (url) { if (root.explorer) root.explorer.routeLink(url); }

    // show a pointing hand over links
    HoverHandler {
        enabled: root.hoveredLink.length > 0
        cursorShape: Qt.PointingHandCursor
    }
}
