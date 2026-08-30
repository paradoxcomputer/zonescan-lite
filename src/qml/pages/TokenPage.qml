import QtQuick
import QtQuick.Controls
import "../components"
import "../theme"
import "../theme.js" as ZT

// Token detail (renderToken): overview (name/type/supply) + definition/sequencer kv,
// a paginated Holders list (its own scrollable region), and the filtered tx feed.
Item {
    id: page
    property var explorer: null
    property string channel: ""
    property string tokenId: ""
    readonly property var backend: explorer ? explorer.backend : null
    readonly property int rev: explorer ? explorer.rev : 0

    property var a: null
    property bool loaded: false
    property bool notFound: false
    property string loadError: ""     // a failed request is not the same answer as "no such token"
    property bool _started: false

    // ── tx feed controller (cursor pagination + live prepend) ──
    property var rows: []
    property var cursor: null
    property bool feedDone: false
    property bool feedLoading: false
    property string feedError: ""
    property var seen: ({})
    readonly property int pageSize: 50
    readonly property int maxRows: 600
    property int feedGen: 0

    // ── holders list (own paginated scroll region) ──
    property var holders: []
    property var holdNext: null      // null=fresh, false=exhausted, else = after-cursor
    property bool holdLoading: false
    property bool holdersLoadedOnce: false

    function qstr(o) { var parts = []; for (var k in o) parts.push(k + "=" + encodeURIComponent(o[k])); return parts.join("&"); }
    function initQuery() { var p = { channel: page.channel }; ZT.filterParams(p); return qstr(p); }
    function pageQuery(cur) {
        var p = { channel: page.channel, limit: pageSize }; ZT.filterParams(p);
        // before_channel is part of the cursor: a hash alone is not unique across zones, so
        // without it a page boundary can repeat or skip a row.
        if (cur) { if (cur.ts != null) p.before_ts = cur.ts; p.before_block = cur.block; p.before_hash = cur.hash; if (cur.channel) p.before_channel = cur.channel; }
        return qstr(p);
    }

    Component.onCompleted: { _started = true; load(); }
    onChannelChanged: if (_started) load()
    onTokenIdChanged: if (_started) load()
    onRevChanged: prependLive()

    // See HomePage: a cached page can be re-shown after the shared filter changed elsewhere.
    property string fltSig: ""
    function pageShown() {
        if (filterBar) filterBar.sync();
        if (page.fltSig !== ZT.fltSig()) page.load();
    }
    function load() {
        if (!backend) return;
        feedGen++;
        fltSig = ZT.fltSig();
        page.loaded = false; page.notFound = false; page.loadError = ""; page.a = null;
        page.rows = []; page.cursor = null; page.feedDone = false; page.feedLoading = false;
        page.feedError = ""; page.seen = ({});
        page.holders = []; page.holdNext = null; page.holdLoading = false; page.holdersLoadedOnce = false;
        var gen = page.feedGen;
        explorer.watch(backend.getTokenQuery(tokenId, initQuery()),
            function (a) {
                if (gen !== page.feedGen) return;
                page.loaded = true;
                if (!a || !a.ok) {
                    if (a && a.status === 404) page.notFound = true;
                    else page.loadError = (a && a.error) || "the request failed";
                    return;
                }
                page.a = a;
                var txs = a.txs || [];
                var s = ({}); for (var i = 0; i < txs.length; i++) s[ZT.rowKey(txs[i])] = true;
                page.seen = s; page.rows = txs;
                if (txs.length) { var last = txs[txs.length - 1]; page.cursor = { ts: last.timestamp, block: last.block_id, hash: last.hash, channel: last.channel }; }
                page.feedDone = txs.length < pageSize;
                page.initHolders();
            },
            function () {
                if (gen !== page.feedGen) return;
                page.loaded = true; page.loadError = "the request failed";
            });
    }
    function retry() { page.load(); }

    function loadMore(first) {
        if (feedLoading || (feedDone && !first)) return;
        feedLoading = true; feedError = "";
        var gen = page.feedGen;
        explorer.watch(backend.getTokenQuery(tokenId, pageQuery(cursor)),
            function (r) {
                if (gen !== page.feedGen) return;
                page.feedLoading = false;
                if (!r || !r.ok) { page.feedError = (r && r.error) || "the request failed"; return; }
                var list = r.txs || [];
                var add = [];
                for (var i = 0; i < list.length; i++) {
                    var t = list[i], key = ZT.rowKey(t);
                    if (!page.seen[key]) { page.seen[key] = true; add.push(t); }
                }
                page.rows = page.rows.concat(add);
                if (list.length) { var last = list[list.length - 1]; page.cursor = { ts: last.timestamp, block: last.block_id, hash: last.hash, channel: last.channel }; }
                if (list.length < pageSize) page.feedDone = true;
            },
            function () {
                if (gen !== page.feedGen) return;
                page.feedLoading = false; page.feedError = "the request failed";
            });
    }

    // live prepend: same channel AND (accounts include the def account OR the tx carries
    // this token's ticker), then the SAME filter the fetch below sends to the server. The
    // comment here used to claim detail feeds have no type chips - contradicted by this page's
    // own FilterBar - and the missing gate let filtered-out rows appear live.
    function prependLive() {
        if (!backend || !backend.txs || !page.a) return;
        if (ZT.fltSort() === "oldest") return;   // newest rows do not belong atop an oldest-first list
        var add = [];
        var txs = backend.txs;
        for (var i = 0; i < txs.length; i++) {
            var t = txs[i], key = ZT.rowKey(t);
            if (page.seen[key]) continue;
            if (t.channel !== page.channel) continue;
            var accs = t.accounts || [];
            if (!(accs.indexOf(page.tokenId) >= 0 || (page.a.name && t.token === page.a.name))) continue;
            if (!ZT.filterMatches(t)) continue;
            if (!ZT.clockOk(t)) continue;
            page.seen[key] = true; add.push(t);
        }
        if (add.length) {
            var next = add.concat(page.rows);
            if (next.length > page.maxRows) {
                // Trimming the tail without moving the cursor would leave an unrecoverable hole:
                // the next page resumes below rows that are no longer in the list. Rewind the
                // cursor and `seen` to the new tail so paging continues from what is shown.
                next = next.slice(0, page.maxRows);
                var tail = next[next.length - 1];
                page.cursor = { ts: tail.timestamp, block: tail.block_id, hash: tail.hash, channel: tail.channel };
                page.feedDone = false;
                var reseen = ({});
                for (var n = 0; n < next.length; n++) reseen[ZT.rowKey(next[n])] = true;
                page.seen = reseen;
            }
            page.rows = next;
        }
    }

    function initHolders() {
        page.holders = []; page.holdNext = null; page.holdLoading = false; page.holdersLoadedOnce = false;
        loadHolders();
    }
    property string holdError: ""
    function loadHolders() {
        if (holdLoading || holdNext === false) return;
        holdLoading = true; holdError = "";
        var gen = page.feedGen;
        var q = "channel=" + encodeURIComponent(page.channel) + "&limit=50" + (holdNext ? "&after=" + encodeURIComponent(holdNext) : "");
        explorer.watch(backend.getTokenHolders(tokenId, q),
            function (r) {
                if (gen !== page.feedGen) return;
                page.holdLoading = false;
                // A failed holders page used to arrive as [] and permanently exhaust the list.
                if (!r || !r.ok) { page.holdError = (r && r.error) || "the request failed"; return; }
                var hs = r.holders || [];
                page.holders = page.holders.concat(hs);
                page.holdNext = (hs.length >= 50 && r.next) ? r.next : false;
                page.holdersLoadedOnce = true;
            },
            function () {
                if (gen !== page.feedGen) return;
                page.holdLoading = false; page.holdError = "the request failed";
            });
    }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 40; clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: col
            x: 18; width: parent.width - 36; spacing: 16; topPadding: 10

            Crumb {
                items: [
                    { label: "Home", action: function () { page.explorer.navHome(); } },
                    { label: "Zone " + ZT.sh(page.channel), action: function () { page.explorer.navZone(page.channel); } },
                    { label: "Token " + ZT.sh(page.tokenId) }
                ]
            }

            // loading / not-found
            Rectangle {
                visible: !page.loaded || page.notFound || page.loadError !== ""
                width: parent.width; height: 90; color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line
                Column {
                    anchors.centerIn: parent; spacing: 8
                    Text { anchors.horizontalCenter: parent.horizontalCenter; color: ZTheme.soft; font.pixelSize: 13
                        text: !page.loaded ? "loading token…"
                              : (page.notFound ? "token not found"
                                 : "couldn't load this token: " + page.loadError) }
                    Rectangle { visible: page.loadError !== ""; anchors.horizontalCenter: parent.horizontalCenter
                        width: 60; height: 24; radius: 6; color: ZTheme.panel; border.width: 1; border.color: ZTheme.line2
                        Text { anchors.centerIn: parent; text: "Retry"; color: ZTheme.fg; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.retry() } }
                }
            }

            // ── Panel 1: Token overview ──
            Rectangle {
                visible: page.loaded && !page.notFound && !!page.a
                width: parent.width; height: ovwCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: ovwCol; width: parent.width
                    Phead { title: "Token"; count: page.a ? (page.a.name || ZT.sh(page.tokenId)) : "" }
                    // .ovw 3-tile grid: white cells with 1px gaps over a pal.line bg
                    Rectangle {
                        width: parent.width; color: ZTheme.line
                        implicitHeight: ovwGrid.implicitHeight
                        Grid {
                            id: ovwGrid; width: parent.width; columns: 3; columnSpacing: 1; rowSpacing: 1
                            property real cw: (width - 2) / 3
                            StatTile { width: ovwGrid.cw; k: "Name"; v: page.a ? (page.a.name || "-") : "-" }
                            StatTile { width: ovwGrid.cw; k: "Type"; v: page.a ? (page.a.kind || "-") : "-" }
                            StatTile { width: ovwGrid.cw; k: "Total supply"
                                v: (page.a && page.a.supply && page.a.supply !== "0") ? ZT.grp(page.a.supply) : "-" }
                        }
                    }
                    Column {
                        x: 16; topPadding: 16; bottomPadding: 16; width: parent.width - 32; spacing: 7
                        KvRow { width: parent.width; explorer: page.explorer; k: "Definition account"; v: page.tokenId }
                        KvRowRich { width: parent.width; k: "Sequencer"; explorer: page.explorer
                            vHtml: page.a ? ('<a href="zone:' + ZT.u(page.channel) + '" style="color:' + ZTheme.link + '">' + ZT.esc(ZT.sh(page.channel)) + "</a>") : "" }
                    }
                }
            }

            // ── Panel 2: Holders ──
            Rectangle {
                visible: page.loaded && !page.notFound && !!page.a
                width: parent.width; height: holdCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: holdCol; width: parent.width
                    Phead { title: "Holders"; count: page.holdersLoadedOnce ? ("" + page.holders.length) : "" }
                    // column header
                    Rectangle {
                        width: parent.width; height: 36; color: ZTheme.theadBg
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                        Text { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                            text: "HOLDER ACCOUNT"; color: ZTheme.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                        Text { anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 }
                            text: "BALANCE"; color: ZTheme.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                    }
                    // scrollable region (max-height:440 → 404 for the list under the 36px header)
                    Rectangle {
                        width: parent.width
                        height: Math.min(404, Math.max(1, page.holders.length) * 40)
                        color: "transparent"; clip: true
                        ListView {
                            id: holdList
                            anchors.fill: parent
                            model: page.holders
                            boundsBehavior: Flickable.StopAtBounds
                            ScrollBar.vertical: ScrollBar { }
                            onContentYChanged: {
                                if (page.holdNext !== false && !page.holdLoading && contentHeight > 0
                                    && contentY + height >= contentHeight - 100) page.loadHolders();
                            }
                            delegate: Item {
                                required property var modelData
                                width: ListView.view ? ListView.view.width : 0
                                height: 40
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                                Text {
                                    anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                                    text: ZT.sh(modelData.account, 8, 6); color: ZTheme.link
                                    font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace"
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: page.explorer.navWallet(modelData.account, page.channel) }
                                }
                                Text {
                                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 16 }
                                    text: modelData.balance != null ? ZT.grp(modelData.balance) : "-"
                                    color: modelData.balance != null ? ZTheme.fg : ZTheme.muted
                                    font.pixelSize: 13; font.weight: modelData.balance != null ? Font.DemiBold : Font.Normal
                                    font.family: "ui-monospace, Menlo, Consolas, monospace"
                                }
                            }
                            Text { anchors.centerIn: parent; width: parent.width - 32; horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                visible: page.holders.length === 0 && !page.holdLoading
                                text: page.holdError !== "" ? ("couldn't load holders: " + page.holdError) : "no holders indexed yet"
                                color: ZTheme.soft; font.pixelSize: 13 }
                        }
                    }
                }
            }

            // ── Panel 3: Transactions ──
            Rectangle {
                visible: page.loaded && !page.notFound && !!page.a
                width: parent.width
                height: 46 + 44 + Math.max(160, Math.min(600, page.rows.length * 42 + 40))
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    anchors.fill: parent
                    Phead { title: "Transactions"; count: page.a ? ZT.num(page.a.tx_count) : "" }
                    FilterBar { id: filterBar; width: parent.width; onChanged: page.load() }
                    TxTable {
                        width: parent.width; height: parent.height - 46 - 44
                        model: page.rows; explorer: page.explorer
                        showZone: false          // this feed is scoped to one channel
                        loading: page.feedLoading; done: page.feedDone
                        doneNote: { page.rev; return ZT.fltSort() === "oldest" ? "oldest first — end of the loaded range" : ""; }
                        emptyText: page.feedError !== "" ? ("couldn't load transactions: " + page.feedError) : "no transactions"
                        onAtEnd: page.loadMore(false)
                        onRowClicked: function (tx) { page.explorer.navTx(tx.channel, tx.hash); }
                    }
                }
            }
        }
    }
}
