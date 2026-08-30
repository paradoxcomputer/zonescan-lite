import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../theme"
import "../theme.js" as ZT

// Program detail (renderProgram): overview (name/guess · sequencer · exact tx
// count) + guess/id kv rows, the instruction-schema panel (registered schema, or
// an open propose-a-schema form validated against real on-chain instructions),
// then the scoped, clock-inclusive transaction feed.
Item {
    id: page
    property var explorer: null
    property string channel: ""
    property string progId: ""
    readonly property var backend: explorer ? explorer.backend : null
    readonly property int rev: explorer ? explorer.rev : 0

    // best-guess (module state — re-eval on rev). generic guesses stay in the Shape row.
    readonly property var g: { page.rev; return ZT.guessFor(page.progId, null); }
    readonly property string nameHtml: {
        page.rev; var gg = page.g;
        return (gg && !gg.generic) ? ZT.guessHtml(gg) : ZT.esc(ZT.progShort(page.progId));
    }
    readonly property string gHtml: {
        page.rev; var gg = page.g; if (!gg) return "";
        var s = ZT.guessHtml(gg);
        if (gg.token) s += ' · defines <span style="color:' + ZTheme.muted + ';font-style:italic"><span style="font-style:normal">≈</span> ' + ZT.esc(gg.token) + "</span>";
        s += ' <span style="color:' + ZTheme.muted + ';font-size:12px">' + ZT.esc(ZT.guessTip(gg)) + "</span>";
        return s;
    }
    // schema state (module state — re-eval on rev)
    readonly property var schema: { page.rev; return (ZT.SCHEMAS && ZT.SCHEMAS[page.progId]) ? ZT.SCHEMAS[page.progId] : null; }
    readonly property bool isCustom: /^[0-9a-f]{64}$/i.test(page.progId)
    readonly property bool hasName: { page.rev; return !!(ZT.PROGS && ZT.PROGS[page.progId]); }

    property string txCount: "…"

    // ── schema form output: STRUCTURED STATE, rendered by two bindings ───────────
    // These were 17 HTML strings built inside doPreview()/doSubmit() and their async callbacks.
    // Every one baked a hex straight into a <span style="color:…">, from a closure that is dead
    // by the time anything else runs, so a theme flip could not reach any of them: the preview
    // and the accept/reject message kept the previous theme's ink until the next click.
    //
    // schemaMsg  : { kind: "ok" | "err" | "info", text }   - text is already HTML-escaped
    // schemaPrev : { kind: "rows", schema, samples } | { kind: "err" | "info", text }
    //
    // The preview MUST retain {schema, samples} rather than a rendered string: decodeBySchema()
    // -> fmtSchema() bakes pal.muted into every field label, so a pre-rendered preview is
    // exactly the thing that cannot be re-inked.
    property var schemaMsg: null
    property var schemaPrev: null

    readonly property string schemaMsgHtml: page.fmtMsg(page.schemaMsg)
    readonly property string schemaPrevHtml: page.fmtPrev(page.schemaPrev)

    function fmtMsg(m) {
        if (!m) return "";
        var c = m.kind === "ok" ? ZTheme.green : (m.kind === "err" ? ZTheme.red : ZTheme.muted);
        return '<span style="color:' + c + '">' + m.text + "</span>";
    }
    function fmtPrev(pv) {
        if (!pv) return "";
        if (pv.kind !== "rows")
            return '<span style="color:' + (pv.kind === "err" ? ZTheme.red : ZTheme.muted) + '">'
                 + pv.text + "</span>";
        // TOTAL for the same reason as TxPage.instrHtml: r0dec() reaches theme.js's u64/u128
        // decoders, which call BigInt, which the QML engine does not have (Qt 6.9.2 and 6.11.1
        // both). The imperative version threw inside an async callback and simply left the
        // preview unset; a binding would report it on every re-evaluation instead.
        var out = [];
        try {
        for (var j = 0; j < pv.samples.length; j++) {
            var w = pv.samples[j];
            var d = ZT.r0dec(w, pv.schema, 0), full = (d.p === w.length);
            // rich(), not a bare call: fmtSchema bakes pal.muted and reads no ZTheme property,
            // so without the re-invocation channel the decoded fields stay last theme's grey.
            var dec = ZTheme.rich(ZT.decodeBySchema, w, pv.schema)
                      || ('<span style="color:' + ZTheme.muted + '">(decode error)</span>');
            out.push('<div style="font-family:ui-monospace,Menlo,Consolas,monospace;font-size:12px">'
                + (full ? '<span style="color:' + ZTheme.green + '">✓</span>'
                        : '<span style="color:' + ZTheme.red + '">✗</span>')
                + " " + dec
                + (full ? "" : ' <span style="color:' + ZTheme.red + '">- consumed ' + d.p + "/" + w.length + " words</span>")
                + "</div>");
        }
        } catch (e) {
            return '<span style="color:' + ZTheme.red + '">preview failed: ' + ZT.esc(String(e)) + "</span>";
        }
        return out.length ? out.join("")
                          : '<span style="color:' + ZTheme.muted + '">no instructions to preview</span>';
    }

    // ── scoped feed controller (cursor pagination + live prepend, no filter bar) ──
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
        var p = { channel: page.channel, program: page.progId, clock: "1", limit: pageSize };
        // before_channel is part of the cursor: a hash alone is not unique across zones, so
        // without it a page boundary can repeat or skip a row.
        if (cur) { if (cur.ts != null) p.before_ts = cur.ts; p.before_block = cur.block; p.before_hash = cur.hash; if (cur.channel) p.before_channel = cur.channel; }
        var parts = []; for (var k in p) parts.push(k + "=" + encodeURIComponent(p[k]));
        return parts.join("&");
    }
    function resetFeed() {
        feedGen++;
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
    function prependLive() {
        if (!backend || !backend.txs) return;
        // No oldest-first guard here: this page has no FilterBar on purpose and buildQuery()
        // never sends `sort`, so the server always answers newest-first. Honouring the shared
        // Sort would freeze live prepend with nothing on the page able to unfreeze it.
        var add = [];
        var txs = backend.txs;
        for (var i = 0; i < txs.length; i++) {
            var t = txs[i], key = ZT.rowKey(t);
            if (page.seen[key]) continue;
            if (t.channel !== page.channel) continue;
            if (t.program !== page.progId) continue;
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

    function reload() {
        if (!backend) return;
        resetFeed();
        txCount = "…";
        // exact per-program total from the indexed /api/program (no scan).
        explorer.watch(backend.getProgramQuery(page.progId, "channel=" + encodeURIComponent(page.channel)),
            function (d) { page.txCount = (d && d.ok) ? ZT.num(d.tx_count) : "-"; },
            function () { page.txCount = "-"; });
    }

    // ── schema propose form ──
    function parseSchema() {
        var v = (schemaInput.text || "").trim();
        if (!v) return { kind: "empty" };
        try { return { kind: "ok", value: JSON.parse(v) }; }
        catch (e) { return { kind: "bad" }; }
    }
    function doPreview() {
        var ps = parseSchema();
        if (ps.kind === "bad") { page.schemaPrev = ({ kind: "err", text: "invalid JSON" }); return; }
        if (ps.kind === "empty") { page.schemaPrev = null; return; }
        var sc = ps.value;
        page.schemaPrev = ({ kind: "info", text: "decoding samples…" });
        explorer.watch(backend.getTxsQuery("channel=" + encodeURIComponent(page.channel) + "&program=" + encodeURIComponent(page.progId) + "&clock=1&limit=8"),
            function (r) {
                if (!r || !r.ok) { page.schemaPrev = ({ kind: "info", text: "preview failed: " + ZT.esc((r && r.error) || "no response") }); return; }
                var txs = r.items || [];
                var samples = [];
                for (var i = 0; i < txs.length && samples.length < 8; i++) {
                    var t = txs[i];
                    if (t.instruction_data && t.instruction_data.length) samples.push(t.instruction_data);
                }
                page.schemaPrev = ({ kind: "rows", schema: sc, samples: samples });
            },
            function () { page.schemaPrev = ({ kind: "info", text: "preview failed" }); });
    }
    function doSubmit() {
        var ps = parseSchema();
        if (ps.kind === "bad") { page.schemaMsg = ({ kind: "err", text: "invalid JSON" }); return; }
        if (ps.kind === "empty") { page.schemaMsg = ({ kind: "info", text: "paste a schema first" }); return; }
        var sc = ps.value;
        var nm = nameInput.visible ? (nameInput.text || "").trim() : "";
        page.schemaMsg = ({ kind: "info", text: "validating…" });
        var body = JSON.stringify({ channel: page.channel, program_id: page.progId, instruction: sc, name: nm });
        explorer.watch(backend.submitSchema(body),
            function (r) {
                r = r || {};
                if (!r.ok) { page.schemaMsg = ({ kind: "err", text: ZT.esc(r.error || "error") }); return; }
                if (r.stored || r.named) {
                    var bits = [];
                    if (r.stored) bits.push("schema accepted (" + r.passed + "/" + r.tested + ")");
                    if (r.named) bits.push("named &ldquo;" + ZT.esc(nm) + "&rdquo;");
                    page.schemaMsg = ({ kind: "ok", text: "✓ " + bits.join(" · ") + " - reloading…" });
                    page.reload();
                    // getSchemas() republishes the schemas PROP, so every open page re-decodes
                    // at once instead of waiting for the periodic registry tick.
                    explorer.watch(backend.getSchemas(),
                        function () { page.schemaMsg = ({ kind: "ok", text: "✓ " + bits.join(" · ") }); },
                        function () {});
                } else if (r.already_exists) {
                    page.schemaMsg = ({ kind: "info", text: "a schema is already registered for this program" });
                } else {
                    page.schemaMsg = ({ kind: "err", text: "✗ rejected - decodes only " + r.passed + "/" + r.tested + " instructions exactly" });
                }
            },
            function (e) { page.schemaMsg = ({ kind: "err", text: "error: " + e }); });
    }

    // createObject applies initial properties BEFORE completion, so these fired ahead of
    // Component.onCompleted and each open issued several identical first-page fetches.
    property bool _started: false
    onProgIdChanged: if (_started) reload()
    onChannelChanged: if (_started) reload()
    onRevChanged: prependLive()
    Component.onCompleted: { _started = true; reload(); }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 40; clip: true
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: col
            x: 18; width: parent.width - 36; spacing: 0; topPadding: 10

            Crumb {
                items: [
                    { label: "Home", action: function () { page.explorer.navHome(); } },
                    { label: "Zone " + ZT.sh(page.channel), action: function () { page.explorer.navZone(page.channel); } },
                    { label: "Program " + ((page.g && !page.g.generic) ? ("≈ " + page.g.name) : ZT.progShort(page.progId)) }
                ]
            }
            Item { width: 1; height: 10 }

            // ── overview panel ──
            Rectangle {
                width: parent.width; height: ovwCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: ovwCol; width: parent.width
                    Phead {
                        title: "Program"
                        RichLabel { explorer: page.explorer; text: page.nameHtml
                            color: ZTheme.soft; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                    }
                    // .ovw 3-tile grid (1px gaps over the line color, bottom border)
                    Rectangle {
                        id: ovwWrap
                        width: parent.width; color: ZTheme.line
                        implicitHeight: ovw.implicitHeight + 1
                        property real cw: (width - 2) / 3
                        property real cellH: Math.max(c1.implicitHeight, c2.implicitHeight, c3.implicitHeight) + 32
                        Grid {
                            id: ovw; columns: 3; columnSpacing: 1; rowSpacing: 1; width: parent.width
                            // Program
                            Rectangle {
                                width: ovwWrap.cw; height: ovwWrap.cellH; color: ZTheme.panel
                                Column { id: c1; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 16 } spacing: 4
                                    Text { text: "PROGRAM"; color: ZTheme.soft; font.pixelSize: 11; font.letterSpacing: 0.5 }
                                    RichLabel { width: parent.width; explorer: page.explorer; text: page.nameHtml
                                        color: ZTheme.navy; font.pixelSize: 15; font.weight: Font.DemiBold
                                        font.family: "ui-monospace, Menlo, Consolas, monospace"; wrapMode: Text.WrapAnywhere }
                                }
                            }
                            // Sequencer
                            Rectangle {
                                width: ovwWrap.cw; height: ovwWrap.cellH; color: ZTheme.panel
                                Column { id: c2; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 16 } spacing: 4
                                    Text { text: "SEQUENCER"; color: ZTheme.soft; font.pixelSize: 11; font.letterSpacing: 0.5 }
                                    RichLabel { width: parent.width; explorer: page.explorer; font.pixelSize: 13
                                        text: '<a href="zone:' + ZT.u(page.channel) + '" style="color:' + ZTheme.link + '">' + ZT.esc(ZT.sh(page.channel)) + "</a>" }
                                }
                            }
                            // Transactions
                            Rectangle {
                                width: ovwWrap.cw; height: ovwWrap.cellH; color: ZTheme.panel
                                Column { id: c3; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 20; rightMargin: 20; topMargin: 16 } spacing: 4
                                    Text { text: "TRANSACTIONS"; color: ZTheme.soft; font.pixelSize: 11; font.letterSpacing: 0.5 }
                                    Text { text: page.txCount; color: ZTheme.navy; font.pixelSize: 20; font.weight: Font.DemiBold
                                        font.family: "ui-monospace, Menlo, Consolas, monospace" }
                                }
                            }
                        }
                    }
                    // guess + program-id kv rows
                    Column {
                        x: 16; width: parent.width - 32; topPadding: 12; bottomPadding: 12; spacing: 8
                        KvRowRich { width: parent.width; visible: !!page.g; explorer: page.explorer
                            k: (page.g && page.g.generic) ? "Shape" : "Name"; vHtml: page.gHtml }
                        KvRow { width: parent.width; k: "Program id"; v: page.progId }
                    }
                }
            }
            Item { width: 1; height: 16 }

            // ── instruction schema (registered) ──
            Rectangle {
                visible: !!page.schema
                width: parent.width; height: haveCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: haveCol; width: parent.width
                    Phead { title: "Instruction schema" }
                    Column {
                        x: 16; width: parent.width - 32; topPadding: 16; bottomPadding: 16; spacing: 8
                        Text { width: parent.width; text: "A schema is registered - instructions decode into typed fields."
                            color: ZTheme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap }
                        Rectangle {
                            width: parent.width; height: schemaJson.implicitHeight + 20
                            color: ZTheme.panel2; radius: 6
                            Text { id: schemaJson; anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 10; rightMargin: 10; topMargin: 10 }
                                text: page.schema ? JSON.stringify(page.schema) : ""
                                color: ZTheme.fg; font.pixelSize: 12; font.family: "ui-monospace, Menlo, Consolas, monospace"
                                wrapMode: Text.WrapAnywhere }
                        }
                    }
                }
            }

            // ── instruction schema (ABI) — propose form (unresolved custom program) ──
            Rectangle {
                visible: !page.schema && page.isCustom
                width: parent.width; height: propCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: propCol; width: parent.width
                    Phead { title: "Instruction schema (ABI)"; count: "propose" }
                    Column {
                        x: 16; width: parent.width - 32; topPadding: 16; bottomPadding: 16; spacing: 8
                        RichLabel {
                            width: parent.width; explorer: page.explorer
                            color: ZTheme.muted; font.pixelSize: 12
                            text: 'No schema yet, so instructions show as raw words. Anyone can propose one - paste the program\'s <b>instruction type</b>. It\'s accepted only if it decodes this program\'s <b>real on-chain instructions exactly</b>. Examples: <code>{"struct":[{"name":"message","type":"bytes"}]}</code> · <code>{"enum":[{"name":"Greet","fields":[{"name":"msg","type":"string"}]}]}</code>'
                        }
                        TextField {
                            id: nameInput
                            visible: !page.hasName
                            width: parent.width
                            maximumLength: 32
                            font.pixelSize: 13
                            placeholderText: "program name alias (optional) - e.g. my_token"
                            background: Rectangle { color: ZTheme.panel; radius: 6; border.width: 1; border.color: ZTheme.line2 }
                        }
                        TextArea {
                            id: schemaInput
                            width: parent.width
                            font.pixelSize: 12; font.family: "ui-monospace, Menlo, Consolas, monospace"
                            wrapMode: TextArea.WrapAnywhere
                            placeholderText: '{"struct":[{"name":"message","type":"bytes"}]}'
                            background: Rectangle { color: ZTheme.panel; radius: 6; border.width: 1; border.color: ZTheme.line2 }
                        }
                        Row {
                            width: parent.width; spacing: 8
                            Button {
                                text: "Preview"; onClicked: page.doPreview()
                                contentItem: Text { text: "Preview"; color: ZTheme.muted; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { color: ZTheme.btnA; radius: 7; border.width: 1; border.color: ZTheme.line2 }
                                padding: 6; leftPadding: 11; rightPadding: 11
                            }
                            Button {
                                text: "Validate & submit"; onClicked: page.doSubmit()
                                contentItem: Text { text: "Validate & submit"; color: ZTheme.fg; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { color: ZTheme.ctrlSel; radius: 7; border.width: 1; border.color: ZTheme.fg }
                                padding: 6; leftPadding: 11; rightPadding: 11
                            }
                            RichLabel { explorer: page.explorer; visible: page.schemaMsgHtml.length > 0
                                text: page.schemaMsgHtml; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                        RichLabel { width: parent.width; explorer: page.explorer; visible: page.schemaPrevHtml.length > 0
                            text: page.schemaPrevHtml; font.pixelSize: 12 }
                    }
                }
            }
            Item { width: 1; height: 16; visible: !!page.schema || page.isCustom }

            // ── transactions feed ──
            Rectangle {
                width: parent.width; height: Math.max(360, page.height - 240)
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    anchors.fill: parent
                    Phead { title: "Transactions" }
                    TxTable {
                        width: parent.width; height: parent.height - 46
                        model: page.rows; explorer: page.explorer
                        loading: page.feedLoading; done: page.feedDone
                        emptyText: (page.backend && page.backend.state && page.backend.state.discovering) ? "⏳ scanning recent L1 blocks…" : "no transactions"
                        onAtEnd: page.loadMore(false)
                        onRowClicked: function (tx) { page.explorer.navTx(tx.channel, tx.hash); }
                    }
                }
            }
        }
    }
}
