import QtQuick

// Renders an HTML fragment produced by theme.js (instrText / txAction / decode /
// chanLabel …) as QML rich text. Links use a compact scheme —
//   wallet:<channel>:<account>  token:<channel>:<def>
//   program:<channel>:<prog>    zone:<channel>
// — which onLinkActivated forwards to the router via `explorer.routeLink(url)`.
//
// routeLink also accepts `tx:<channel>:<hash>` for completeness, but nothing here emits one:
// no zonescan transaction field references another transaction, so there is nothing for such
// a link to point at. Rows navigate to a transaction directly via navTx() instead.
Text {
    id: root
    property var explorer: null
    textFormat: Text.RichText
    wrapMode: Text.WordWrap
    color: "#18181b"
    font.pixelSize: 13
    font.family: "-apple-system, Segoe UI, Roboto, sans-serif"
    linkColor: "#27272a"
    onLinkActivated: function (url) { if (root.explorer) root.explorer.routeLink(url); }

    // show a pointing hand over links
    HoverHandler {
        enabled: root.hoveredLink.length > 0
        cursorShape: Qt.PointingHandCursor
    }
}
