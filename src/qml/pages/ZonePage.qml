import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../theme.js" as ZT

// Zone / channel detail (renderZone): a header panel (Sequencer|Channel title +
// chanLabel + data/version/consistency badges) with a 4-tile overview grid and a
// kv detail grid, the honest "Channel activity" explainer (self-hides), and the
// channel-scoped transaction feed (filter bar + cursor pagination + live prepend).
Item {
    id: page
    property var explorer: null
    property string channel: ""
    readonly property var backend: explorer ? explorer.backend : null
    readonly property int rev: explorer ? explorer.rev : 0
    readonly property var state: backend ? backend.state : null

    // s = explorer.seqs.find(x=>x.channel===channel) || {channel, channel_short: sh(channel)}
    readonly property var seq: {
        page.rev;
        var arr = explorer ? explorer.seqs : [];
        for (var i = 0; i < arr.length; i++) if (arr[i].channel === channel) return arr[i];
        return { channel: channel, channel_short: ZT.sh(channel) };
    }

    // ── feed controller (cursor pagination + live prepend), scoped to this channel ──
    property var rows: []
    property var cursor: null
    property bool feedDone: false
    property bool feedLoading: false
    property string feedError: ""
    property var seen: ({})
    readonly property int pageSize: 50
    readonly property int maxRows: 600
    property int feedGen: 0

    function buildQuery(cur) {
        var p = { channel: channel, limit: pageSize };
        ZT.filterParams(p);
        // before_channel is part of the cursor: a hash alone is not unique across zones, so
        // without it a page boundary can repeat or skip a row.
        if (cur) { if (cur.ts != null) p.before_ts = cur.ts; p.before_block = cur.block; p.before_hash = cur.hash; if (cur.channel) p.before_channel = cur.channel; }
        var parts = []; for (var k in p) parts.push(k + "=" + encodeURIComponent(p[k]));
        return parts.join("&");
    }
    // See HomePage: a cached page can be re-shown after the shared filter changed elsewhere.
    property string fltSig: ""
    function pageShown() {
        if (filterBar) filterBar.sync();
        if (page.fltSig !== ZT.fltSig()) page.resetFeed();
    }
    function resetFeed() {
        feedGen++;
        fltSig = ZT.fltSig();
        rows = []; cursor = null; feedDone = false; feedLoading = false; feedError = ""; seen = ({});
        loadMore(true);
    }
    function retryFeed() { feedError = ""; loadMore(true); }
    function loadMore(first) {
        if (!backend || feedLoading || (feedDone && !first)) return;
        feedLoading = true; feedError = "";
        var gen = page.feedGen;
        explorer.watch(backend.getTxsQuery(buildQuery(cursor)),
            function (r) {
                if (gen !== page.feedGen) return;
                page.feedLoading = false;
                if (!r || !r.ok) { page.feedError = (r && r.error) || "the request failed"; return; }
                var list = r.items || [];
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
    // live prepend from the polled backend.txs, gated to this channel
    function prependLive() {
        if (!backend || !backend.txs) return;
        if (ZT.fltSort() === "oldest") return;   // newest rows do not belong atop an oldest-first list
        var add = [];
        var txs = backend.txs;
        for (var i = 0; i < txs.length; i++) {
            var t = txs[i], key = ZT.rowKey(t);
            if (page.seen[key]) continue;
            if (t.channel !== channel) continue;
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
    property bool _started: false
    onRevChanged: prependLive()
    onChannelChanged: if (_started) resetFeed()
    Component.onCompleted: { _started = true; resetFeed(); }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 40; clip: true
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: col
            x: 18; width: parent.width - 36; spacing: 16; topPadding: 10

            Crumb {
                items: [
                    { label: "Home", action: function () { page.explorer.navHome(); } },
                    { label: "Zone " + ZT.sh(page.channel) }
                ]
            }

            // ── header panel: title + chanLabel + badges, overview grid, kv grid ──
            Rectangle {
                width: parent.width; implicitHeight: body.implicitHeight
                color: ZT.pal.panel; radius: 12; border.width: 1; border.color: ZT.pal.line; clip: true
                Column {
                    id: body; width: parent.width
                    Phead {
                        title: page.seq && page.seq.data_channel ? "Channel" : "Sequencer"
                        RichLabel { explorer: page.explorer; text: ZT.chanLabel(page.seq.channel, page.seq.channel_short); font.pixelSize: 13 }
                        ZBadge { visible: ZT.dataBadge(page.seq); fontPx: 10; text: "DATA"
                            bg: ZT.verBadge.data.bg; fg: ZT.verBadge.data.fg; bd: ZT.verBadge.data.bg }
                        ZBadge { visible: !!page.seq.version; fontPx: 10
                            property var vc: ZT.verBadge[page.seq.version] || { bg: "#eef0f4", fg: ZT.pal.soft }
                            text: (page.seq.version || "").toUpperCase(); bg: vc.bg; fg: vc.fg; bd: vc.bg }
                        Text { property var cb: (page.rev, ZT.consBadge(page.seq)); visible: !!cb
                            text: cb ? cb.text : ""; color: cb && cb.ok ? ZT.pal.green : ZT.pal.red
                            font.pixelSize: 11; font.weight: Font.Bold }
                    }

                    // .ovw overview grid (repeat(3,1fr) — Status wraps to its own row)
                    GridLayout {
                        width: parent.width; columns: page.width < 700 ? 2 : 3; columnSpacing: 1; rowSpacing: 1
                        StatTile { Layout.fillWidth: true; k: "Latest L2 Block"; v: ZT.l2Tip(page.seq) }
                        StatTile { Layout.fillWidth: true; k: "L1 Channel Balance"
                            v: page.seq.l1_balance != null ? ZT.num(page.seq.l1_balance) : "-" }
                        StatTile { Layout.fillWidth: true; k: "Throughput"; v: ZT.bpmStr(page.seq) || "-" }
                        // Status — value coloured green (alive) / soft (idle), so a custom cell
                        Rectangle {
                            Layout.fillWidth: true; color: "#ffffff"; implicitHeight: stc.implicitHeight + 32
                            Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: ZT.pal.line }
                            Column { id: stc; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 16 } spacing: 4
                                Text { text: "STATUS"; color: ZT.pal.soft; font.pixelSize: 11; font.letterSpacing: 0.5 }
                                Text { text: page.seq.alive ? "ALIVE" : "IDLE"; color: page.seq.alive ? ZT.pal.green : ZT.pal.soft
                                    font.pixelSize: 20; font.weight: Font.DemiBold; font.family: "ui-monospace, Menlo, Consolas, monospace" }
                            }
                        }
                    }

                    // .kv detail grid (padding:16px)
                    Column {
                        x: 16; topPadding: 16; bottomPadding: 16; width: parent.width - 32; spacing: 7
                        KvRow { width: parent.width; explorer: page.explorer; k: "Channel id"; v: page.channel }
                        KvRow { width: parent.width; explorer: page.explorer; k: "Tx mix"; v: ZT.txMixStr(page.seq) }
                        KvRow { width: parent.width; explorer: page.explorer; k: "LEZ Version"; v: page.seq.version ? page.seq.version : "-" }
                        KvRow { width: parent.width; explorer: page.explorer; k: "Last settled"
                            v: (page.seq.tip_change_unix ? ZT.fmtAge(page.seq.tip_change_unix) : "-") + " (channel tip)" }
                        // `settling` is published on every sequencer and was never rendered
                        // anywhere in the port; three-state, so "unknown" is a real answer.
                        KvRow { width: parent.width; explorer: page.explorer; k: "Settling"; mono: false
                            v: (page.rev, ZT.settleText(page.seq)) }
                        KvRow { width: parent.width; explorer: page.explorer; k: "Signer keys"; v: ZT.num(page.seq.l1_signers) }
                        KvRow { width: parent.width; explorer: page.explorer; k: "Sequencer tip (RPC)"
                            v: page.seq.seq_tip != null ? ("#" + ZT.num(page.seq.seq_tip) + (page.seq.seq_tip < page.seq.latest_block_id ? " ⚠ below L1" : "")) : "-" }
                        KvRow { width: parent.width; explorer: page.explorer; k: "Chain check"; v: ZT.chainCheckText(page.seq) }
                        KvRow { width: parent.width; explorer: page.explorer; k: "Inscriptions seen"; v: ZT.num(page.seq.inscriptions_seen) }
                    }
                }
            }

            // ── channel activity explainer (self-hides unless seq.activity_state) ──
            ActivityPanel { width: parent.width; seq: page.seq; state: page.explorer ? page.explorer.state : null }

            // ── transactions feed (channel-scoped) ──
            Rectangle {
                width: parent.width; height: Math.max(460, page.height - 240)
                color: ZT.pal.panel; radius: 12; border.width: 1; border.color: ZT.pal.line; clip: true
                Column {
                    anchors.fill: parent
                    Phead {
                        title: "Transactions"
                        Text { visible: !!(page.state && page.state.skip_clock); text: "clock ticks not indexed"
                            color: ZT.pal.muted; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }
                    FilterBar { id: filterBar; width: parent.width; onChanged: page.resetFeed() }
                    Rectangle {
                        width: parent.width; height: page.feedError !== "" ? 34 : 0
                        visible: height > 0; color: "#fdece8"
                        Row {
                            anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                      leftMargin: 16; rightMargin: 16 }
                            spacing: 10
                            Text { text: "Couldn't load transactions: " + page.feedError
                                color: "#8c2d1c"; font.pixelSize: 11; elide: Text.ElideRight
                                width: parent.width - 70; anchors.verticalCenter: parent.verticalCenter }
                            Rectangle { width: 56; height: 22; radius: 6; color: "#ffffff"; border.width: 1; border.color: "#e0b4a8"
                                anchors.verticalCenter: parent.verticalCenter
                                Text { anchors.centerIn: parent; text: "Retry"; color: "#8c2d1c"; font.pixelSize: 11; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.retryFeed() } }
                        }
                    }
                    TxTable {
                        width: parent.width; height: parent.height - 46 - 44 - (page.feedError !== "" ? 34 : 0)
                        model: page.rows; explorer: page.explorer
                        // every row here is this channel — the column would repeat one value
                        showZone: false
                        loading: page.feedLoading; done: page.feedDone
                        doneNote: { page.rev; return ZT.fltSort() === "oldest" ? "oldest first — end of the loaded range" : ""; }
                        emptyText: "no transactions"
                        onAtEnd: page.loadMore(false)
                        onRowClicked: function (tx) { page.explorer.navTx(tx.channel, tx.hash); }
                    }
                }
            }
        }
    }
}
