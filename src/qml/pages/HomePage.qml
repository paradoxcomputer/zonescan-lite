import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../theme.js" as ZT

// Home dashboard (renderHome): 4 stat cards (finality-lag sparkline) + a two-panel
// grid — Zones sidebar (renderSeqs) and the Latest Transactions feed (filter bar +
// cursor-paginated infinite scroll + live prepend).
Item {
    id: page
    property var explorer: null
    readonly property var backend: explorer ? explorer.backend : null
    readonly property int rev: explorer ? explorer.rev : 0
    readonly property var state: backend ? backend.state : null
    readonly property var l1: state && state.l1 ? state.l1 : ({})
    readonly property var seqs: state && state.sequencers ? state.sequencers : []
    readonly property int alive: { var n = 0; for (var i = 0; i < seqs.length; i++) if (seqs[i].alive) n++; return n; }
    // zones filter segment: all | rc (sequencers) | data (data channels)
    property string zoneFilter: "all"
    // local zone: whether the connect panel is open, and which source the feed shows
    property bool showLocal: false
    property string feedTab: "network"
    // Local rows pass through the SAME predicate the network feed sends to the server, so the
    // Visibility/Type controls keep meaning what they say. Clock ticks follow the server's
    // rule too: hidden unless the Clock type is explicitly selected.
    readonly property var localRows: {
        page.rev;
        var out = [], src = localPanelTxs;
        for (var i = 0; i < src.length; i++) {
            var t = src[i];
            if (!ZT.fltTypeList().length && ZT.progName(t.program) === "clock") continue;
            if (ZT.filterMatches(t)) out.push(t);
        }
        return out;
    }
    // mirrored out of the panel so the binding above re-evaluates when a walk completes
    property var localPanelTxs: []
    readonly property var filteredSeqs: {
        if (zoneFilter === "all") return seqs;
        var out = [];
        for (var i = 0; i < seqs.length; i++) {
            var isData = !!seqs[i].data_channel;
            if ((zoneFilter === "data") === isData) out.push(seqs[i]);
        }
        return out;
    }

    // ── feed controller (cursor pagination + live prepend) ──
    property var rows: []
    property var cursor: null
    property bool feedDone: false
    property bool feedLoading: false
    property string feedError: ""
    property var seen: ({})
    readonly property int pageSize: 50
    // A page kept alive in the router's cache keeps prepending live rows while hidden, so the
    // list needs a ceiling. Oldest rows go first; the cursor is untouched, so paging still works.
    readonly property int maxRows: 600
    // Bumped by every resetFeed(). An in-flight page carries the value it started with and
    // drops itself if it no longer matches, so a reply for the PREVIOUS filter cannot land in
    // the list the new filter just emptied.
    property int feedGen: 0
    readonly property bool narrow: page.width > 0 && page.width < 900

    function buildQuery(cur) {
        var p = { limit: pageSize };
        var solo = explorer.soloChannel(); if (solo) p.channel = solo;
        ZT.filterParams(p);
        // before_channel is part of the cursor: a hash alone is not unique across zones, so
        // without it a page boundary can repeat or skip a row.
        if (cur) { if (cur.ts != null) p.before_ts = cur.ts; p.before_block = cur.block; p.before_hash = cur.hash; if (cur.channel) p.before_channel = cur.channel; }
        var parts = []; for (var k in p) parts.push(k + "=" + encodeURIComponent(p[k]));
        return parts.join("&");
    }
    // The router keeps pages alive and re-shows them, so a page can come back with rows
    // fetched under a filter that has since changed on another page (ZT.FLT is engine-wide).
    // fltSig records what the current rows were actually fetched under.
    property string fltSig: ""
    function pageShown() {
        if (filterBar) filterBar.sync();
        if (page.fltSig !== ZT.fltSig()) page.resetFeed();
    }
    function resetFeed() {
        // feedLoading was NOT cleared here, and loadMore() returns early while it is set - so
        // changing a filter mid-fetch emptied the list and then issued no request at all.
        feedGen++;
        fltSig = ZT.fltSig();
        rows = []; cursor = null; feedDone = false; feedLoading = false; feedError = ""; seen = ({});
        loadMore(true);
    }
    function retryFeed() { feedError = ""; loadMore(true); }
    function loadMore(first) {
        if (!backend) return;
        if (feedLoading || (feedDone && !first)) return;
        feedLoading = true; feedError = "";
        var gen = page.feedGen;
        explorer.watch(backend.getTxsQuery(buildQuery(cursor)),
            function (r) {
                if (gen !== page.feedGen) return;
                page.feedLoading = false;
                // A failed request used to arrive here as a bare [], which every feed reads as
                // "the last page" - one dropped request showed an empty chain and switched
                // pagination off for good.
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
    // live prepend from the polled backend.txs (mirrors SSE prependTxs + feedMatches)
    function prependLive() {
        if (!backend || !backend.txs) return;
        // Newly polled rows are the NEWEST ones. Sorted oldest-first they do not belong at the
        // top of this list - they belong thousands of rows past its end - so nothing is
        // prepended in that mode.
        if (ZT.fltSort() === "oldest") return;
        var solo = explorer.soloChannel();
        var add = [];
        var txs = backend.txs;
        for (var i = 0; i < txs.length; i++) {
            var t = txs[i], key = ZT.rowKey(t);
            if (page.seen[key]) continue;
            if (solo && t.channel !== solo) continue;
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
    onRevChanged: prependLive()
    Component.onCompleted: resetFeed()

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: colWrap.implicitHeight
        clip: true
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: colWrap
            x: 18; width: parent.width - 36
            spacing: 16

            // stat cards (overlap the hero by 22px)
            Grid {
                y: -22
                width: parent.width; columns: page.width < 720 ? 2 : 4; columnSpacing: 16; rowSpacing: 16
                property real cw: (width - (columns - 1) * 16) / columns
                ZStatCard { width: parent.cw; k: "L1 Block Height"; v: ZT.num(page.l1.height)
                    s: page.l1.advancing === false ? "not advancing" : (page.l1.reachable ? "advancing" : "-") }
                ZStatCard { width: parent.cw; k: "Finality Lag"; v: ZT.num(page.l1.finality_lag)
                    s: "tip slot " + ZT.num(page.l1.tip_slot); series: page.l1.finality_series || null }
                ZStatCard { width: parent.cw; k: "Transactions"; v: ZT.num(page.state ? page.state.tx_total : null)
                    s: page.state && page.state.decode_feature ? "decode on" : "decode off" }
                ZStatCard { width: parent.cw; k: "Zones"; v: ZT.num(page.seqs.length); s: page.alive + " active" }
            }

            // grid: Zones sidebar + Latest Transactions. Below `narrow` they stack, because a
            // fixed 340px sidebar subtracted from the window left the feed panel with a
            // negative width on a small one.
            Grid {
                id: panels
                width: parent.width; columns: page.narrow ? 1 : 2
                columnSpacing: 16; rowSpacing: 16
                property real panelH: Math.max(420, page.height - 210)
                property real zonesW: page.narrow ? width : 340
                property real feedW: page.narrow ? width : (width - 340 - 16)
                // Zones panel
                Rectangle {
                    width: panels.zonesW; height: page.narrow ? 420 : panels.panelH
                    color: ZT.pal.panel; radius: 12; border.width: 1; border.color: ZT.pal.line; clip: true
                    Column {
                        anchors.fill: parent
                        Phead {
                            title: "Zones"
                            // All | rc | data segment (zoneSeg)
                            Repeater {
                                model: [ {t:"All",v:"all"}, {t:"rc",v:"rc"}, {t:"data",v:"data"} ]
                                delegate: Rectangle {
                                    required property var modelData
                                    height: 24; width: segTxt.implicitWidth + 18; radius: 7
                                    color: page.zoneFilter === modelData.v ? "#ececef" : "#ffffff"
                                    border.width: 1; border.color: page.zoneFilter === modelData.v ? ZT.pal.fg : ZT.pal.line2
                                    Text { id: segTxt; anchors.centerIn: parent; text: modelData.t; font.pixelSize: 12
                                        color: page.zoneFilter === modelData.v ? ZT.pal.fg : ZT.pal.muted }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.zoneFilter = modelData.v }
                                }
                            }
                        }
                        // The local zone is a different KIND of thing from the All/rc/data
                        // filters: those narrow the tracked list, this adds a zone only you
                        // can see. So it gets its own row beneath them, not a fourth segment.
                        Rectangle {
                            width: parent.width; height: 38; color: "transparent"
                            Rectangle {
                                x: 12; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24; height: 28; radius: 7
                                color: page.showLocal ? ZT.pal.fg : "transparent"
                                border.width: 1
                                border.color: page.showLocal ? ZT.pal.fg
                                              : (local.status === "ok" ? ZT.pal.green : ZT.pal.line2)
                                Text {
                                    anchors.centerIn: parent; font.pixelSize: 12; font.bold: true
                                    color: page.showLocal ? ZT.pal.panel
                                           : (local.status === "ok" ? ZT.pal.green : ZT.pal.muted)
                                    text: local.status === "ok" ? "Local sequencer · connected"
                                                                : "Add your local sequencer"
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: page.showLocal = !page.showLocal }
                            }
                        }
                        LocalZonePanel {
                            id: local
                            visible: page.showLocal
                            width: parent.width
                            explorer: page.explorer; backend: page.backend
                            onTxsUpdated: {
                                page.localPanelTxs = local.txs;
                                if (local.status === "ok") page.feedTab = "local";
                            }
                            // Leaving "ok" (Disconnect, or a reconnect that finds nothing) hides
                            // the source switch below, so a feedTab still pinned to "local" would
                            // strand the feed on an empty list with no control to get back to the
                            // network. Release the pin whenever the local zone stops being live.
                            onStatusChanged: {
                                if (local.status !== "ok" && page.feedTab === "local")
                                    page.feedTab = "network";
                            }
                        }
                        ListView {
                            width: parent.width
                            height: parent.height - 46 - 38 - (page.showLocal ? local.implicitHeight : 0)
                            clip: true
                            model: page.filteredSeqs
                            boundsBehavior: Flickable.StopAtBounds
                            delegate: ZoneRow {
                                required property var modelData
                                width: ListView.view ? ListView.view.width : 0
                                seq: modelData
                                // `selected` and the pal.rowSel colour it alone uses were never
                                // assigned by anything. Marking the zone you last opened is what
                                // it is for, and matters more now that Home survives a Back.
                                selected: !!page.explorer && page.explorer.lastZoneChannel === modelData.channel
                                onClicked: page.explorer.navZone(modelData.channel)
                            }
                            Text { anchors.centerIn: parent; visible: page.filteredSeqs.length === 0
                                text: (page.state && page.state.discovering) ? "scanning the L1 for sequencers…"
                                      : (page.zoneFilter === "data" ? "no data channels found"
                                         : (page.zoneFilter === "rc" ? "no sequencer zones found" : "no sequencers found"))
                                color: ZT.pal.soft; font.pixelSize: 13 }
                        }
                    }
                }
                // Latest Transactions panel
                Rectangle {
                    width: panels.feedW; height: panels.panelH
                    color: ZT.pal.panel; radius: 12; border.width: 1; border.color: ZT.pal.line; clip: true
                    Column {
                        anchors.fill: parent
                        Phead {
                            title: "Latest Transactions"
                            Text { visible: !!(page.state && page.state.skip_clock); text: "clock ticks not indexed"
                                color: ZT.pal.muted; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                        // source switch: the tracked network, or the local zone. Only shown
                        // once a local zone is connected, since an empty tab is a dead end.
                        Row {
                            visible: local.status === "ok"
                            x: 12; height: 34; spacing: 6
                            Repeater {
                                model: [ {t:"Network",v:"network"}, {t:"Local sequencer",v:"local"} ]
                                delegate: Rectangle {
                                    required property var modelData
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 24; width: ftTxt.implicitWidth + 20; radius: 6
                                    color: page.feedTab === modelData.v ? ZT.pal.fg : ZT.pal.panel
                                    border.width: 1
                                    border.color: page.feedTab === modelData.v ? ZT.pal.fg : ZT.pal.line
                                    Text { id: ftTxt; anchors.centerIn: parent; text: modelData.t
                                        font.pixelSize: 12; font.bold: true
                                        color: page.feedTab === modelData.v ? ZT.pal.panel : ZT.pal.muted }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: page.feedTab = modelData.v }
                                }
                            }
                        }
                FilterBar { id: filterBar; width: parent.width; onChanged: page.resetFeed() }
                        // feed-level failure + retry. A failed page used to be indistinguishable
                        // from an empty chain, with no way to ask again.
                        Rectangle {
                            width: parent.width; height: page.feedError !== "" && page.feedTab !== "local" ? 34 : 0
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
                            width: parent.width
                            height: parent.height - 46 - 44 - (local.status === "ok" ? 34 : 0)
                                    - (page.feedError !== "" && page.feedTab !== "local" ? 34 : 0)
                            model: page.feedTab === "local" ? page.localRows : page.rows
                            explorer: page.explorer
                            // Every row in a solo-zone or local feed carries the same channel, so
                            // the widest column would just repeat it.
                            showZone: page.feedTab !== "local" && !page.explorer.soloChannel()
                            loading: page.feedTab === "local" ? false : page.feedLoading
                            done: page.feedTab === "local" ? true : page.feedDone
                            doneNote: { page.rev;
                                return (page.feedTab !== "local" && ZT.fltSort() === "oldest")
                                       ? "oldest first — end of the loaded range" : ""; }
                            emptyText: (page.state && page.state.discovering) ? "⏳ scanning recent L1 blocks…" : "no transactions"
                            onAtEnd: page.loadMore(false)
                            onRowClicked: function (tx) { page.explorer.navTx(tx.channel, tx.hash); }
                        }
                    }
                }
            }
        }
    }
}
