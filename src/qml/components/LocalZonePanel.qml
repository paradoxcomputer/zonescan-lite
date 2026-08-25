import QtQuick
import QtQuick.Controls
import "../theme.js" as ZT

// "Add your local sequencer": reads a sequencer running on the USER's machine and shows it
// alongside the tracked zones. Mirrors the web dashboard's local zone, minus its transport
// workaround: a browser must tunnel JSON-RPC over a WebSocket because a cross-origin HTTP POST
// to loopback is blocked, whereas a desktop module has no same-origin policy and can simply
// POST. Blocks are Borsh, so they are decoded by the zonescan server, which stores nothing.
Rectangle {
    id: root

    property var explorer: null
    property var backend: null

    // idle | reading | ok | error
    property string status: "idle"
    property string url: ZT.LOCAL_DEFAULT_URL
    property string channel: ""
    property int tip: 0
    property int scanned: 0
    property bool reachedGenesis: false
    property var txs: []
    property string errorText: ""
    // Set when zonescan's /api/decode could not be reached, as opposed to reaching it and
    // being told the batch held no LEZ blocks. Those are different failures with different
    // fixes, and collapsing them blamed the user's chain for a zonescan outage.
    property bool decodeFailed: false
    property string decodeError: ""
    // Established from a full first batch; see ZT.clockOnlyIsSkippable.
    property bool skipClockOnly: false

    signal txsUpdated()

    implicitHeight: col.implicitHeight + 20
    color: "transparent"

    // Bumped on every reset/connect. A walk carries the value it started with and abandons
    // itself the moment it stops matching, so a Disconnect (or a second Connect) cannot have
    // its in-flight replies land on top of the new state.
    property int walkToken: 0

    function reset() {
        walkToken++;
        status = "idle"; channel = ""; tip = 0; scanned = 0;
        reachedGenesis = false; txs = []; errorText = ""; skipClockOnly = false;
        decodeFailed = false; decodeError = "";
        root.txsUpdated();
    }

    function fail(msg) { status = "error"; errorText = msg; }

    // Every SLOT on the .rep returns a PENDING TOKEN, not a value: it has to be resolved
    // through logos.watch (see Main.qml's watch()). Reading `backend.localRpc(...).result`
    // directly always yields undefined, which is why this panel reported "could not reach a
    // sequencer" against a perfectly healthy one. So the backwards walk below is written in
    // continuation-passing style: each batch is a callback that schedules the next.
    function rpc(u, method, params, onOk, onErr) {
        explorer.watch(backend.localRpc(u, method, params),
            function (res) {
                res = res || {};
                if (!res.ok) { onErr(res.error || "no result"); return; }
                onOk(res.result);
            },
            function () { onErr("request failed"); });
    }

    // Walk backwards until enough real transactions are in hand. A sequencer mints a block on
    // a timer whether or not anyone transacted, so stopping after a fixed number of BLOCKS
    // stops in the middle of empty history and shows nothing.
    function connectLocal() {
        reset();
        if (!explorer || !backend) { fail("the explorer backend is not ready yet"); return; }
        status = "reading";
        var u = urlField.text.trim() || ZT.LOCAL_DEFAULT_URL;
        root.url = u;
        var token = root.walkToken;
        rpc(u, "getChannelId", [],
            function (ch) {
                if (token !== root.walkToken) return;
                // The shared rpc() helper only rejects an absent result, but a channel id has
                // to be non-empty to be usable: it is sent to /api/decode and tagged onto every
                // row. The synchronous original tested this with a plain falsy check; keep it.
                if (!ch) { fail("could not reach a sequencer at " + u); return; }
                root.channel = String(ch);
                rpc(u, "getLastBlockId", [],
                    function (t) {
                        if (token !== root.walkToken) return;
                        root.tip = Number(t) || 0;
                        root.walkStep({ u: u, token: token, low: root.tip + 1,
                                        real: 0, batchIdx: 0, collected: [] });
                    },
                    function () { if (token === root.walkToken) fail("connected, but the tip could not be read"); });
            },
            function () { if (token === root.walkToken) fail("could not reach a sequencer at " + u); });
    }

    // One batch of the walk. Recursion happens inside a resolved callback, so each step is a
    // fresh event-loop turn and the stack does not grow with the number of batches.
    function walkStep(st) {
        if (st.token !== root.walkToken) return;
        if (!(st.low > 1 && st.real < ZT.LOCAL_MIN_TXS && root.scanned < ZT.LOCAL_MAX_BLOCKS)) {
            root.finishWalk(st); return;
        }
        var size = st.batchIdx === 0 ? ZT.LOCAL_FIRST_BATCH : ZT.LOCAL_BATCH;
        var hi = st.low - 1, lo = Math.max(1, hi - size + 1);
        rpc(st.u, "getBlockRange", [lo, hi],
            function (all) {
                if (st.token !== root.walkToken) return;
                if (!all || !all.length) { root.finishWalk(st); return; }
                root.scanned += all.length; st.low = lo;

                // Upload only blocks that could carry something displayable. On a chain proven
                // to tick a clock every block, a single-transaction block IS that tick.
                var send = [];
                for (var i = 0; i < all.length; i++) {
                    if (!root.skipClockOnly) { send.push(all[i]); continue; }
                    var n = ZT.blockTxCount(all[i]);
                    if (n === null || n > 1) send.push(all[i]);
                }
                if (!send.length) { st.batchIdx++; root.walkStep(st); return; }

                explorer.watch(backend.decodeBlocks(JSON.stringify({ blocks: send, channel: root.channel })),
                    function (res) {
                        if (st.token !== root.walkToken) return;
                        if (!res || !res.ok) {
                            // zonescan's decoder is the thing that failed, not this chain. Stop
                            // walking: every further batch would fail the same way, and the walk
                            // would still climb to the 20k-block ceiling before saying anything.
                            root.decodeFailed = true;
                            root.decodeError = (res && res.error) || "the decoder did not answer";
                            root.finishWalk(st);
                            return;
                        }
                        var decoded = res.blocks || [];
                        var ok = [];
                        for (var j = 0; j < decoded.length; j++) if (decoded[j] && decoded[j].ok) ok.push(decoded[j]);
                        if (st.batchIdx === 0) root.skipClockOnly = ZT.clockOnlyIsSkippable(send, ok);

                        // Clock ticks only from the newest batch: they are the bulk of an idle
                        // chain and would swamp memory without adding anything to show.
                        var keepClock = st.batchIdx === 0;
                        for (var k = 0; k < ok.length; k++) {
                            var b = ok[k], keep = [];
                            for (var m = 0; m < (b.txs || []).length; m++) {
                                var t = b.txs[m];
                                if (ZT.progName(t.program) !== "clock") st.real++;
                                if (keepClock || ZT.progName(t.program) !== "clock") keep.push(t);
                            }
                            if (keep.length) { var c = {}; for (var p in b) c[p] = b[p]; c.txs = keep; st.collected.push(c); }
                        }
                        st.batchIdx++;
                        root.walkStep(st);
                    },
                    function () {
                        if (st.token !== root.walkToken) return;
                        root.decodeFailed = true;
                        root.decodeError = "the decode request failed";
                        root.finishWalk(st);
                    });
            },
            function () { if (st.token === root.walkToken) root.finishWalk(st); });
    }

    function finishWalk(st) {
        if (st.token !== root.walkToken) return;
        root.reachedGenesis = st.low <= 1;
        if (!root.scanned) { fail("connected, but no blocks were returned"); return; }
        var tagged = ZT.localTag(st.collected, root.channel);
        tagged.sort(function (a, b) { return (b.block_id || 0) - (a.block_id || 0); });
        root.txs = tagged;
        // Rows decoded here exist ONLY in this process. Hand them to the explorer so opening
        // one resolves locally instead of asking the remote zonescan for a chain it has never
        // seen, which could only ever answer "not found".
        if (explorer && tagged.length) explorer.registerLocalTxs(tagged);
        root.status = tagged.length ? "ok" : "error";
        if (!tagged.length) {
            root.errorText = root.decodeFailed
                ? ("your sequencer was read (" + ZT.num(root.scanned) + " blocks), but zonescan's "
                   + "decoder could not be reached: " + root.decodeError)
                : "blocks were read but none decoded as LEZ blocks";
        }
        root.txsUpdated();
    }

    Column {
        id: col
        x: 12; y: 10; width: parent.width - 24; spacing: 8

        Text {
            text: "SEQUENCER ADDRESS"; font.pixelSize: 11; font.bold: true
            font.letterSpacing: 0.5; color: ZT.pal.soft
        }
        Row {
            width: parent.width; spacing: 8
            Rectangle {
                width: parent.width - connectBtn.width - 8; height: 32; radius: 6
                color: ZT.pal.bg; border.width: 1; border.color: ZT.pal.line
                TextInput {
                    id: urlField
                    anchors.fill: parent; anchors.leftMargin: 9; anchors.rightMargin: 9
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.url; font.family: "monospace"; font.pixelSize: 12
                    color: ZT.pal.fg; clip: true; selectByMouse: true
                    enabled: root.status !== "reading"
                    onAccepted: root.connectLocal()
                }
            }
            Rectangle {
                id: connectBtn
                width: btnTxt.implicitWidth + 26; height: 32; radius: 6
                color: root.status === "ok" ? "#fef3f2" : ZT.pal.fg
                border.width: 1; border.color: root.status === "ok" ? "#fecdca" : ZT.pal.fg
                opacity: root.status === "reading" ? 0.6 : 1
                Text {
                    id: btnTxt; anchors.centerIn: parent; font.pixelSize: 12; font.bold: true
                    color: root.status === "ok" ? "#b42318" : ZT.pal.panel
                    text: root.status === "ok" ? "Disconnect"
                          : (root.status === "reading" ? "Cancel" : "Connect")
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // reset() bumps walkToken, which is what actually abandons the walk: every
                    // in-flight batch checks it before touching state.
                    onClicked: {
                        if (root.status === "reading" || root.status === "ok") root.reset();
                        else root.connectLocal();
                    }
                }
            }
        }
        Rectangle {
            width: parent.width; height: noteCol.implicitHeight + 18; radius: 7
            color: ZT.pal.bg; border.width: 1; border.color: ZT.pal.line
            Column {
                id: noteCol
                x: 11; y: 9; width: parent.width - 22; spacing: 6
                Text {
                    width: parent.width; wrapMode: Text.WordWrap; font.pixelSize: 11
                    color: ZT.pal.muted; lineHeight: 1.35
                    text: "Reads a sequencer on your own machine. Only the encoded blocks are sent to the zonescan server, to be decoded; nothing about your chain is stored."
                }
            }
        }
        Text {
            visible: root.status === "error"; width: parent.width; wrapMode: Text.WordWrap
            text: root.errorText; color: "#b42318"; font.pixelSize: 12
        }
        Text {
            visible: root.status === "reading"
            text: root.scanned > 0
                  ? ("reading blocks… " + ZT.num(root.scanned) + " scanned · Cancel to stop")
                  : "contacting the sequencer…"
            color: ZT.pal.muted; font.pixelSize: 12
        }
        Text {
            visible: root.status === "ok"; width: parent.width; wrapMode: Text.WordWrap
            font.pixelSize: 12; color: ZT.pal.muted
            text: "connected · tip #" + ZT.num(root.tip)
                  + " · scanned " + (root.reachedGenesis ? "whole chain" : ZT.num(root.scanned) + " blocks back")
                  + " · " + ZT.num(root.txs.length) + " tx(s)"
        }
    }
}
