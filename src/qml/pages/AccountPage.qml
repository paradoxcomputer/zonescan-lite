import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../theme"
import "../theme.js" as ZT

// Account / wallet (renderWallet): a 4-tile overview (L2/L1 balances, nonce, tx
// count) + address & cross-zone sequencer list, an optional token-holdings table,
// and the cursor-paginated tx feed (filter bar + infinite scroll + live prepend).
Item {
    id: page
    property var explorer: null
    property string channel: ""      // may be empty ⇒ global (all zones) view
    property string accId: ""
    readonly property var backend: explorer ? explorer.backend : null
    readonly property int rev: explorer ? explorer.rev : 0
    readonly property var state: backend ? backend.state : null

    property var acct: null
    property bool loaded: false
    property bool notFound: false
    // "the account does not exist" and "the request failed" are different answers and used to
    // be the same branch, so a network blip reported a factual claim about the chain.
    property string loadError: ""

    // ── feed controller (cursor pagination + live prepend) ──
    property var rows: []
    property var cursor: null
    property bool feedDone: false
    property bool feedLoading: false
    property string feedError: ""
    property var seen: ({})
    readonly property int pageSize: 50
    readonly property int maxRows: 600
    property int feedGen: 0

    function baseQuery() {
        var p = ({});
        if (channel) p.channel = channel;
        ZT.filterParams(p);
        return p;
    }
    function qstr(p) {
        var parts = []; for (var k in p) parts.push(k + "=" + encodeURIComponent(p[k]));
        return parts.join("&");
    }

    // See HomePage: a cached page can be re-shown after the shared filter changed elsewhere.
    property string fltSig: ""
    function pageShown() {
        if (filterBar) filterBar.sync();
        if (page.fltSig !== ZT.fltSig()) page.reload();
    }
    function reload() {
        if (!backend) return;
        feedGen++;
        fltSig = ZT.fltSig();
        loaded = false; notFound = false; loadError = ""; acct = null;
        rows = []; cursor = null; feedDone = false; feedLoading = false; feedError = ""; seen = ({});
        var gen = page.feedGen;
        explorer.watch(backend.getAccountQuery(accId, qstr(baseQuery())),
            function (a) {
                if (gen !== page.feedGen) return;
                page.loaded = true;
                if (!a || !a.ok) {
                    if (a && a.status === 404) page.notFound = true;
                    else page.loadError = (a && a.error) || "the request failed";
                    return;
                }
                page.acct = a;
                var txs = a.txs || [];
                var s = ({}); for (var i = 0; i < txs.length; i++) s[ZT.rowKey(txs[i])] = true;
                page.seen = s; page.rows = txs;
                if (txs.length) { var last = txs[txs.length - 1]; page.cursor = { ts: last.timestamp, block: last.block_id, hash: last.hash, channel: last.channel }; }
                page.feedDone = txs.length < page.pageSize;
            },
            function () {
                if (gen !== page.feedGen) return;
                page.loaded = true; page.loadError = "the request failed";
            });
    }
    function retry() { page.reload(); }
    function loadMore() {
        if (feedLoading || feedDone) return;
        feedLoading = true; feedError = "";
        var gen = page.feedGen;
        var p = baseQuery(); p.limit = pageSize;
        // before_channel is part of the cursor: a hash alone is not unique across zones, so
        // without it a page boundary can repeat or skip a row.
        if (cursor) { if (cursor.ts != null) p.before_ts = cursor.ts; p.before_block = cursor.block; p.before_hash = cursor.hash; if (cursor.channel) p.before_channel = cursor.channel; }
        explorer.watch(backend.getAccountQuery(accId, qstr(p)),
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
                if (list.length < page.pageSize) page.feedDone = true;
            },
            function () {
                if (gen !== page.feedGen) return;
                page.feedLoading = false; page.feedError = "the request failed";
            });
    }
    // live prepend from the polled backend.txs (mirrors feedMatches for a wallet:
    // same channel when scoped, tx touches this account, clock hidden unless chosen)
    function prependLive() {
        if (!backend || !backend.txs) return;
        if (ZT.fltSort() === "oldest") return;   // newest rows do not belong atop an oldest-first list
        var add = [];
        var txs = backend.txs;
        for (var i = 0; i < txs.length; i++) {
            var t = txs[i], key = ZT.rowKey(t);
            if (page.seen[key]) continue;
            if (channel && t.channel !== channel) continue;
            if (((t.accounts) || []).indexOf(accId) < 0) continue;
            // This page mounts a FilterBar and sends filterParams on its fetches, but live rows
            // were never gated by it - so with Visibility=Private set, public rows appeared at
            // the top within 2 s.
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
    // createObject applies initial properties BEFORE completion, so these fired ahead of
    // Component.onCompleted and each open issued several identical first-page fetches.
    property bool _started: false
    onRevChanged: prependLive()
    onAccIdChanged: if (_started) reload()
    onChannelChanged: if (_started) reload()
    Component.onCompleted: { _started = true; reload(); }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 40; clip: true
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: col
            x: 18; width: parent.width - 36; spacing: 0; topPadding: 10

            Crumb {
                items: page.channel
                    ? [ { label: "Home", action: function () { page.explorer.navHome(); } },
                        { label: "Zone " + ZT.sh(page.channel), action: function () { page.explorer.navZone(page.channel); } },
                        { label: "Wallet " + ZT.sh(page.accId) } ]
                    : [ { label: "Home", action: function () { page.explorer.navHome(); } },
                        { label: "Wallet " + ZT.sh(page.accId) } ]
            }
            Item { width: 1; height: 10 }

            // loading / not-found / failed
            Rectangle {
                visible: !page.loaded || page.notFound || page.loadError !== ""
                width: parent.width; height: 90; color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line
                Column {
                    anchors.centerIn: parent; spacing: 8
                    Text { anchors.horizontalCenter: parent.horizontalCenter; color: ZTheme.soft; font.pixelSize: 13
                        text: !page.loaded ? "loading account…"
                              : (page.notFound ? "account not found"
                                 : "couldn't load this account: " + page.loadError) }
                    Rectangle { visible: page.loadError !== ""; anchors.horizontalCenter: parent.horizontalCenter
                        width: 60; height: 24; radius: 6; color: ZTheme.panel; border.width: 1; border.color: ZTheme.line2
                        Text { anchors.centerIn: parent; text: "Retry"; color: ZTheme.fg; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.retry() } }
                }
            }

            // ── panel #1: overview ──
            Rectangle {
                visible: page.loaded && !page.notFound && page.acct
                width: parent.width; height: ovwCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: ovwCol; width: parent.width
                    Phead {
                        title: page.channel ? "Account on " + ZT.sh(page.channel) : "Account"
                        count: ZT.sh(page.accId, 10, 8)
                    }
                    // .ovw — 4 tiles over a pal.line bg (1px gaps)
                    Rectangle {
                        width: parent.width; color: ZTheme.line
                        implicitHeight: ovwGrid.implicitHeight
                        GridLayout {
                            id: ovwGrid
                            width: parent.width
                            columns: page.width < 700 ? 2 : 4
                            columnSpacing: 1; rowSpacing: 1
                            Repeater {
                                model: [
                                    { k: "Balance · L2 (sequencer)",
                                      v: page.acct && page.acct.l2_balance != null ? ZT.grp(page.acct.l2_balance)
                                         : (page.acct && page.acct.sequencer_rpc ? "RPC unavailable" : "no sequencer RPC"),
                                      sub: page.acct && page.acct.l2_balance != null ? "sequencer RPC" : "",
                                      muted: !(page.acct && page.acct.l2_balance != null) },
                                    { k: "Balance · L1 (settled)",
                                      v: page.acct && page.acct.l1_balance != null ? ZT.grp(page.acct.l1_balance) : "not settled / private",
                                      sub: page.acct && page.acct.l1_balance != null && page.acct.l1_balance_block ? "@ #" + ZT.num(page.acct.l1_balance_block) : "",
                                      muted: !(page.acct && page.acct.l1_balance != null) },
                                    { k: "Nonce",
                                      v: page.acct && page.acct.nonce != null ? ZT.num(page.acct.nonce) : "-", sub: "", muted: false },
                                    { k: "Transactions" + (page.channel ? " (here)" : ""),
                                      v: ZT.num(page.acct ? page.acct.tx_count : null), sub: "", muted: false }
                                ]
                                delegate: StatTile {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    k: modelData.k; v: modelData.v; sub: modelData.sub; muted: modelData.muted
                                }
                            }
                        }
                    }
                    // .kv — Address (+ Sequencers when global)
                    Column {
                        x: 18; topPadding: 14; bottomPadding: 16; width: parent.width - 36; spacing: 7
                        KvRow { width: parent.width; explorer: page.explorer; k: "Address"; v: page.acct ? (page.acct.id || page.accId) : page.accId }
                        KvRowRich {
                            width: parent.width; explorer: page.explorer; k: "Sequencers"
                            vHtml: {
                                if (page.channel || !page.acct) return "";
                                var chans = page.acct.channels || [];
                                if (!chans.length) return '<span style="color:' + ZTheme.muted + '">none</span>';
                                var parts = [];
                                for (var i = 0; i < chans.length; i++) {
                                    var c = chans[i];
                                    parts.push('<a href="wallet:' + ZT.u(c.channel) + ':' + ZT.u(page.accId) + '" style="color:' + ZTheme.link + '">'
                                        + ZT.chanLabel(c.channel, c.channel_short) + '</a> '
                                        + '<span style="color:' + ZTheme.muted + '">(' + ZT.num(c.tx_count) + ' tx)</span>');
                                }
                                return parts.join(" &nbsp; ");
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 16; visible: !!(page.acct && page.acct.holdings && page.acct.holdings.length) }

            // ── panel #2: token holdings ──
            Rectangle {
                visible: !!(page.acct && page.acct.holdings && page.acct.holdings.length)
                width: parent.width; height: holdCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: holdCol; width: parent.width
                    Phead { title: "Token holdings"; count: (page.acct && page.acct.holdings ? page.acct.holdings.length : 0) + "" }
                    // header row
                    Rectangle {
                        width: parent.width; height: 36; color: ZTheme.theadBg
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                        RowLayout { anchors { fill: parent; leftMargin: 16; rightMargin: 16 } spacing: 12
                            Text { Layout.fillWidth: true; text: "Token"; color: ZTheme.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                            Text { Layout.preferredWidth: 140; horizontalAlignment: Text.AlignRight; text: "Balance"; color: ZTheme.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                            Text { Layout.preferredWidth: 170; text: "Holding account (ATA)"; color: ZTheme.soft; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.4 }
                        }
                    }
                    Column {
                        width: parent.width
                        Repeater {
                            model: (page.acct && page.acct.holdings) ? page.acct.holdings : []
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width; height: 40; color: "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                                RowLayout { anchors { fill: parent; leftMargin: 16; rightMargin: 16 } spacing: 12
                                    // Token
                                    Text {
                                        Layout.fillWidth: true; elide: Text.ElideRight
                                        text: modelData.name ? modelData.name : ZT.sh(modelData.definition || "", 6, 4)
                                        color: modelData.name ? ZTheme.link : ZTheme.muted
                                        font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace"
                                        MouseArea { anchors.fill: parent; enabled: !!modelData.name && !!modelData.definition
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: page.explorer.navToken(page.channel || page.acct.channel, modelData.definition) }
                                    }
                                    // Balance
                                    Text {
                                        Layout.preferredWidth: 140; horizontalAlignment: Text.AlignRight
                                        text: modelData.balance != null ? ZT.grp(modelData.balance) : "-"
                                        color: modelData.balance != null ? ZTheme.fg : ZTheme.muted
                                        font.pixelSize: 13; font.weight: modelData.balance != null ? Font.DemiBold : Font.Normal
                                        font.family: "ui-monospace, Menlo, Consolas, monospace"
                                    }
                                    // Holding account (ATA)
                                    Text {
                                        Layout.preferredWidth: 170; elide: Text.ElideRight
                                        text: ZT.sh(modelData.account || "", 6, 4)
                                        color: ZTheme.link; font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace"
                                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: page.explorer.navWallet(modelData.account, page.channel || page.acct.channel) }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { width: 1; height: 16; visible: page.loaded && !page.notFound && page.acct }

            // ── panel #3: transactions ──
            Rectangle {
                visible: page.loaded && !page.notFound && page.acct
                width: parent.width
                height: Math.max(360, page.height - 240)
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    anchors.fill: parent
                    Phead { title: "Transactions"; count: ZT.num(page.acct ? page.acct.tx_count : null) }
                    FilterBar { id: filterBar; width: parent.width; onChanged: page.reload() }
                    TxTable {
                        width: parent.width; height: parent.height - 46 - 44
                        model: page.rows; explorer: page.explorer
                        // the global (all-zones) account view genuinely spans zones; a scoped one does not
                        showZone: page.channel === ""
                        loading: page.feedLoading; done: page.feedDone
                        doneNote: { page.rev; return ZT.fltSort() === "oldest" ? "oldest first — end of the loaded range" : ""; }
                        emptyText: page.feedError !== "" ? ("couldn't load transactions: " + page.feedError)
                                   : ((page.state && page.state.discovering) ? "⏳ scanning recent L1 blocks…" : "no transactions")
                        onAtEnd: page.loadMore()
                        onRowClicked: function (tx) { page.explorer.navTx(tx.channel, tx.hash); }
                    }
                }
            }
        }
    }
}
