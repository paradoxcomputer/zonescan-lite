import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../components"
import "../theme"
import "../theme.js" as ZT

// Transaction detail (renderTx): header badges, action line + finality, the full
// kv grid (incl. the decoded Instruction row with async token_of / corpus-layout
// refinement), private-tx surface, and the raw-inscription payload panel.
Item {
    id: page
    property var explorer: null
    property string channel: ""
    property string txHash: ""
    readonly property var backend: explorer ? explorer.backend : null
    readonly property int rev: explorer ? explorer.rev : 0

    property var tx: null
    property bool loaded: false
    property bool notFound: false
    property string loadError: ""     // the request failed — NOT the same as "no such transaction"

    // ── decoded instruction: RETAINED INPUTS, rendered by a binding ──────────────
    // This was six imperative assignments to a plain string, made from inside async callbacks
    // that are dead by the time anything else happens. The string therefore held whatever ink
    // was current when the response landed - `instrText`/`renderByLayout` bake pal.link and
    // pal.muted straight into <a style="color:…"> - and a theme flip could not reach it.
    // Keeping the INPUTS and rendering in one binding fixes that without ever re-issuing a
    // network call on a flip: nothing below touches `backend`.
    property var tokResolved: null    // resolved token_of for accounts[0] (token standard), or null
    property var layout: null         // corpus-inferred field layout for this program, or null
    property int layoutTick: 0        // an inference can RESOLVE to null; only a tick reports that
    // Programs whose instructions decode from a hand-written branch in instrText(). Hoisted out
    // of refineInstruction() because the render binding has to re-apply the same guard.
    readonly property var builtinProgs: ["token","amm","clock","pinata","pinata_token","ata","authenticated_transfer","privacy_preserving_circuit"]

    readonly property string instrHtml: {
        page.rev;         // SCHEMAS/PROGS are module-level JS the binding engine cannot observe
        page.layoutTick;  // and a layout that resolved to null leaves `layout` untouched
        var t = page.tx;
        if (!t || !t.instruction_data || !t.instruction_data.length) return "";
        // TOTAL, deliberately. theme.js's numeric decoders (u128le / u64le / leInt / b58) call
        // BigInt, and the QML engine does not have it - `typeof BigInt === "undefined"` on both
        // Qt 6.9.2 (what Basecamp runs) and 6.11.1. Any instruction needing a 64/128-bit int
        // therefore THROWS. That defect is pre-existing and lives in theme.js; what changes here
        // is where it surfaces. The old code assigned from inside an async callback, so a throw
        // just meant the assignment never happened and the row stayed hidden. A binding is
        // different: the engine reports every uncaught exception, and this one re-evaluates on
        // `rev`, which ticks with the live feed - it turned into a steady stream of
        // "ReferenceError: BigInt is not defined" that failed 8 sitometres steps. Returning ""
        // reproduces the old observable behaviour exactly; it does not paper over a new bug.
        try {
            // The guard is HERE, not only where the layout was inferred. A layout is memoized
            // for the whole session; if a schema is registered afterwards, re-testing SCHEMAS on
            // every evaluation is what lets the authoritative decode win. Checking it once at
            // inference time would lose to the memo for the rest of the session.
            var haveSchema = !!(ZT.SCHEMAS && ZT.SCHEMAS[t.program]);
            if (page.layout && t.program && !haveSchema
                && page.builtinProgs.indexOf(ZT.progName(t.program)) < 0) {
                var html = ZTheme.rich(ZT.renderByLayout, t.instruction_data, page.layout, t);
                if (html) return html;
            }
            return ZTheme.rich(ZT.instrText, t, page.tokResolved);
        } catch (e) {
            return "";
        }
    }
    // Rows decoded from a sequencer on this machine are tagged onto a pseudo-zone. zonescan has
    // never seen that chain, so asking it for one could only ever answer "not found".
    readonly property bool isLocal: !!explorer && explorer.isLocalChannel(page.channel)

    // NOT `z`: QQuickItem::z is FINAL, and shadowing it made this whole page fail to load with
    // "Cannot override FINAL property" - a fourth fatal QML error of the same family as the
    // three fixed in 59d4bfd, and the reason no recorded run ever opened a transaction.
    readonly property string zoneId: tx && tx.channel ? tx.channel : channel
    readonly property var taMap: {
        var m = ({}); var arr = (tx && tx.token_accounts) || [];
        for (var i = 0; i < arr.length; i++) m[arr[i].account] = arr[i];
        return m;
    }
    // structured cid_pin (IPFS pin) view for a recognized raw inscription, else null
    readonly property var cidPin: { page.rev; return (tx && tx.kind === "raw") ? ZT.cidPinData(tx) : null; }

    Component.onCompleted: load()
    function retry() {
        page.loaded = false; page.notFound = false; page.loadError = "";
        page.tokResolved = null; page.layout = null;
        page.load();
    }
    function load() {
        // A local row resolves from the in-process index the local-zone panel filled; the
        // remote explorer is never asked about it.
        if (page.isLocal) {
            var lt = explorer.localTx(page.txHash);
            page.loaded = true;
            if (!lt) { page.notFound = true; return; }
            page.tx = lt;
            return;
        }
        // zone-scoped: a hash is not unique across zones, and this page knows its zone
        explorer.watch(backend.getTxOn(txHash, page.channel),
            function (t) {
                page.loaded = true;
                if (!t || !t.ok) {
                    if (t && t.status === 404) page.notFound = true;
                    else page.loadError = (t && t.error) || "the request failed";
                    return;
                }
                if (!t.hash) { page.notFound = true; return; }
                page.tx = t;
                page.refineInstruction(t);
            },
            function () { page.loaded = true; page.loadError = "the request failed"; });
    }
    // token-standard transfer → resolve which token via the holding account, then
    // custom/deployed programs with no schema → infer a layout from the corpus.
    // Fetches only. Every branch stores an INPUT; none of them renders, so nothing here can be
    // left holding a stale colour and nothing here re-runs on a theme flip.
    function refineInstruction(t) {
        var name = ZT.progName(t.program);
        if (name === "token" && t.instruction_data && t.instruction_data.length >= 5 && t.instruction_data[0] === 0 && t.accounts && t.accounts[0]) {
            explorer.watch(backend.getTokenOf(t.accounts[0], page.zoneId),
                function (tok) { if (tok && tok.ok) page.tokResolved = tok; }, function () {});
        }
        var haveSchema = ZT.SCHEMAS && ZT.SCHEMAS[t.program];
        if (t.program && t.instruction_data && t.instruction_data.length && !haveSchema && page.builtinProgs.indexOf(name) < 0) {
            // theme.js memoizes the inferred layout per program. Without consulting it, every
            // visit to any tx of a schema-less program re-fetched a whole sample page and re-ran
            // inferLayout, and the instruction row visibly popped in each time.
            if (ZT.hasLayout(t.program)) {
                page.layout = ZT.getLayout(t.program);
                page.layoutTick = page.layoutTick + 1;
                return;
            }
            explorer.watch(backend.getProgramQuery(t.program, "channel=" + encodeURIComponent(page.zoneId)),
                function (d) {
                    if (!d || !d.ok) return;   // leave the layout unmemoized so a retry can infer it
                    var samples = (d.txs || []).map(function (x) { return x.instruction_data; });
                    var lay = ZT.inferLayout(samples);
                    ZT.setLayout(t.program, lay);   // null is a real answer: "not inferable"
                    page.layout = lay;
                    page.layoutTick = page.layoutTick + 1;
                }, function () {});
        }
    }

    Flickable {
        anchors.fill: parent; contentWidth: width; contentHeight: col.implicitHeight + 40; clip: true
        ScrollBar.vertical: ScrollBar { }
        Column {
            id: col
            x: 18; width: parent.width - 36; spacing: 0; topPadding: 10

            Crumb {
                // The pseudo-zone has no zone page — linking to it led to an empty phantom.
                items: page.isLocal
                    ? [ { label: "Home", action: function () { page.explorer.navHome(); } },
                        { label: "Local sequencer" },
                        { label: "Tx " + ZT.sh(page.txHash) } ]
                    : [ { label: "Home", action: function () { page.explorer.navHome(); } },
                        { label: "Zone " + ZT.sh(page.zoneId), action: function () { page.explorer.navZone(page.zoneId); } },
                        { label: "Tx " + ZT.sh(page.txHash) } ]
            }
            Item { width: 1; height: 10 }

            // loading / not-found / failed
            Rectangle {
                visible: !page.loaded || page.notFound || page.loadError !== ""
                width: parent.width; height: 96; color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line
                Column {
                    anchors.centerIn: parent; spacing: 8; width: parent.width - 40
                    Text { anchors.horizontalCenter: parent.horizontalCenter; color: ZTheme.soft; font.pixelSize: 13
                        horizontalAlignment: Text.AlignHCenter; width: parent.width; wrapMode: Text.WordWrap
                        text: !page.loaded ? "loading transaction…"
                              : (page.loadError !== "" ? ("couldn't load this transaction: " + page.loadError)
                                 : (page.isLocal ? "this local transaction is no longer loaded — reconnect your sequencer from Home"
                                    : "transaction not found in the current window")) }
                    Rectangle { visible: page.loadError !== ""; anchors.horizontalCenter: parent.horizontalCenter
                        width: 60; height: 24; radius: 6; color: ZTheme.panel; border.width: 1; border.color: ZTheme.line2
                        Text { anchors.centerIn: parent; text: "Retry"; color: ZTheme.fg; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: page.retry() } }
                }
            }

            // main panel
            Rectangle {
                visible: page.loaded && !page.notFound && page.tx
                width: parent.width; height: body.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: body; width: parent.width
                    // phead with badges
                    Rectangle {
                        width: parent.width; height: 46
                        gradient: Gradient { GradientStop { position: 0; color: ZTheme.pheadA } GradientStop { position: 1; color: ZTheme.pheadB } }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                        Row {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                            spacing: 8
                            Text { text: "Transaction"; color: ZTheme.navy; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                            ZBadge { property var v: page.tx ? (page.rev, ZT.visBadgeFor(page.tx)) : ({}); anchors.verticalCenter: parent.verticalCenter
                                text: v.text || ""; bg: v.bg || ZTheme.panel; fg: v.fg || ZTheme.fg; bd: v.bd || ZTheme.line }
                            ZBadge { property var t: page.tx ? (page.rev, ZT.typeBadgeFor(page.tx)) : ({}); anchors.verticalCenter: parent.verticalCenter
                                text: t.text || ""; italic: !!t.italic; bg: t.bg || ZTheme.panel; fg: t.fg || ZTheme.fg; bd: t.bd || ZTheme.line }
                        }
                    }
                    // action line + finality
                    Row {
                        x: 18; topPadding: 16; bottomPadding: 2; width: parent.width - 36; spacing: 8
                        RichLabel {
                            explorer: page.explorer; text: page.tx ? ZT.txAction(page.tx) : ""
                            font.pixelSize: 17; font.weight: Font.DemiBold; color: ZTheme.navy
                            width: parent.width - finB.width - 8
                        }
                        ZBadge {
                            id: finB; anchors.verticalCenter: parent.verticalCenter
                            property string fk: page.tx ? (page.rev, ZT.finTier(page.tx)) : ""
                            visible: !!fk
                            text: fk ? ZTheme.finBadge[fk].label : ""; bg: fk ? ZTheme.finBadge[fk].bg : "transparent"
                            fg: fk ? ZTheme.finBadge[fk].fg : ZTheme.soft; bd: "transparent"
                            tip: page.tx ? (page.rev, ZT.finTip(page.tx)) : ""
                        }
                    }
                    // kv grid
                    Column {
                        x: 18; topPadding: 14; bottomPadding: 18; width: parent.width - 36; spacing: 7
                        KvRow { explorer: page.explorer; k: "Txn Hash"; v: page.tx ? (page.tx.hash || "") : "" }
                        KvRow { explorer: page.explorer; k: "Visibility"; v: page.tx ? ZT.cap(ZT.txVis(page.tx)) : ""; mono: false }
                        KvRowRich { k: "Type"; explorer: page.explorer
                            vHtml: {
                                if (!page.tx) return "";
                                var g = (page.tx.kind === "public") ? ZT.guessFor(page.tx.program, page.tx) : null;
                                return g ? ZT.guessHtml(g) : ZT.esc(ZT.typeLabel(ZT.txType(page.tx)));
                            } }
                        KvRowRich { k: "Program"; explorer: page.explorer
                            visible: !!(page.tx && page.tx.program)
                            vHtml: {
                                if (!page.tx || !page.tx.program) return "";
                                var g = ZT.guessFor(page.tx.program, page.tx);
                                var inner = (g && !g.generic) ? (ZT.guessHtml(g) + ' <span style="color:' + ZTheme.muted + '">' + ZT.esc(ZT.sh(page.tx.program, 6, 5)) + "</span>") : ZT.esc(ZT.progShort(page.tx.program));
                                return '<a href="program:' + ZT.u(page.zoneId) + ':' + ZT.u(page.tx.program) + '" style="color:' + ZTheme.link + '">' + inner + "</a>";
                            } }
                        // A local row's channel is the pseudo-zone, which has no page to link to;
                        // show the real channel id the sequencer reported instead.
                        KvRow { visible: page.isLocal; explorer: page.explorer; k: "Local channel"
                            v: page.isLocal && page.tx ? (page.tx.local_channel || "-") : "" }
                        KvRowRich { visible: !page.isLocal
                            k: page.tx && page.tx.kind === "raw" ? "Channel" : "Sequencer"; explorer: page.explorer
                            vHtml: (page.tx && !page.isLocal) ? ('<a href="zone:' + ZT.u(page.zoneId) + '" style="color:' + ZTheme.link + '">' + ZT.esc(page.zoneId) + "</a>") : "" }
                        // block / slot
                        KvRow { explorer: page.explorer; visible: !!(page.tx && page.tx.kind === "raw"); k: "L1 slot"
                            v: page.tx && page.tx.kind === "raw" ? (page.tx.slot ? ZT.num(page.tx.slot) : "-") : "" }
                        KvRow { explorer: page.explorer; visible: !!(page.tx && page.tx.kind !== "raw"); k: "L2 Block"
                            v: page.tx && page.tx.kind !== "raw" ? ("#" + ZT.num(page.tx.block_id) + (page.tx.slot ? "  ·  L1 slot " + ZT.num(page.tx.slot) : "")) : "" }
                        // accounts (chips, non-raw)
                        Item {
                            visible: !!(page.tx && page.tx.kind !== "raw")
                            width: parent.width; height: accCol.implicitHeight
                            Row {
                                id: accCol; width: parent.width; spacing: 18
                                Text { width: 150; text: "Accounts (" + (page.tx && page.tx.accounts ? page.tx.accounts.length : 0) + ")"; color: ZTheme.soft; font.pixelSize: 12 }
                                Flow {
                                    width: parent.width - 168; spacing: 6
                                    Repeater {
                                        model: (page.tx && page.tx.accounts) ? page.tx.accounts : []
                                        delegate: Chip {
                                            required property var modelData
                                            property var ta: page.taMap[modelData]
                                            text: modelData
                                            annotation: ta ? ("· " + ta.symbol + " " + ta.role) : ""
                                            clickable: true
                                            onClicked: page.explorer.navWallet(modelData, page.zoneId)
                                        }
                                    }
                                    Text { visible: !(page.tx && page.tx.accounts && page.tx.accounts.length); text: "none"; color: ZTheme.soft; font.pixelSize: 12 }
                                }
                            }
                        }
                        // instruction (decoded, refined async)
                        KvRowRich { k: "Instruction"; explorer: page.explorer
                            visible: page.instrHtml.length > 0
                            vHtml: page.instrHtml }
                        // deploys program
                        KvRowRich { k: "Deploys program"; explorer: page.explorer
                            visible: !!(page.tx && page.tx.deploy_program)
                            vHtml: page.tx && page.tx.deploy_program ? ('<a href="program:' + ZT.u(page.zoneId) + ':' + ZT.u(page.tx.deploy_program) + '" style="color:' + ZTheme.link + '">' + ZT.esc(ZT.progShort(page.tx.deploy_program)) + "</a>") : "" }
                        // guest ELF — size + a real download link (opens the zonescan REST
                        // endpoint externally; keyed by the deployed program hash).
                        KvRowRich { k: "Guest ELF"; explorer: page.explorer
                            visible: !!(page.tx && page.tx.bytecode_len)
                            vHtml: {
                                if (!page.tx || !page.tx.bytecode_len) return "";
                                // elfHref resolves against the origin the BACKEND is configured for,
                                // so pointing the module at a local zonescan repoints this link too.
                                var href = ZT.elfHref(page.tx.deploy_program || page.tx.program || page.tx.hash);
                                var size = ZT.num(page.tx.bytecode_len) + " bytes";
                                return href ? (size + ' · <a href="' + href + '" style="color:' + ZTheme.link + '">download .elf</a>')
                                            : (size + ' <span style="color:' + ZTheme.muted + '">· download unavailable (no zonescan origin)</span>');
                            } }
                        // nullifiers / commitments / encrypted outputs (private)
                        Item {
                            visible: !!(page.tx && page.tx.nullifiers && page.tx.nullifiers.length)
                            width: parent.width; height: nfCol.implicitHeight
                            Row { id: nfCol; width: parent.width; spacing: 18
                                Text { width: 150; text: "Nullifiers (" + (page.tx && page.tx.nullifiers ? page.tx.nullifiers.length : 0) + ")"; color: ZTheme.soft; font.pixelSize: 12 }
                                Flow { width: parent.width - 168; spacing: 6
                                    Repeater { model: (page.tx && page.tx.nullifiers) ? page.tx.nullifiers : []
                                        delegate: Chip { required property var modelData; text: modelData } } }
                            }
                        }
                        Item {
                            visible: !!(page.tx && page.tx.commitments && page.tx.commitments.length)
                            width: parent.width; height: cmCol.implicitHeight
                            Row { id: cmCol; width: parent.width; spacing: 18
                                Text { width: 150; text: "Commitments (" + (page.tx && page.tx.commitments ? page.tx.commitments.length : 0) + ")"; color: ZTheme.soft; font.pixelSize: 12 }
                                Flow { width: parent.width - 168; spacing: 6
                                    Repeater { model: (page.tx && page.tx.commitments) ? page.tx.commitments : []
                                        delegate: Chip { required property var modelData; text: modelData } } }
                            }
                        }
                        KvRow { explorer: page.explorer; visible: !!(page.tx && page.tx.encrypted_outputs != null); k: "Encrypted outputs"; mono: false
                            v: page.tx && page.tx.encrypted_outputs != null ? (page.tx.encrypted_outputs + " (private, opaque)") : "" }
                    }
                }
            }

            // cid_pin "Pinned content" panel (structured IPFS pin view) — before the payload
            Item { width: 1; height: 16; visible: !!page.cidPin }
            Rectangle {
                visible: !!page.cidPin
                width: parent.width; height: cpCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: cpCol; width: parent.width
                    Phead { title: "Pinned content"
                        ZBadge { text: "cid_pin"; bg: ZTheme.tyBadge.raw.bg; fg: ZTheme.tyBadge.raw.fg; bd: ZTheme.tyBadge.raw.bd; fontPx: 11 } }
                    Text { x: 18; topPadding: 16; width: parent.width - 36; text: page.cidPin ? page.cidPin.title : ""
                        color: ZTheme.navy; font.pixelSize: 17; font.weight: Font.DemiBold; wrapMode: Text.WordWrap }
                    Column {
                        x: 18; topPadding: 12; bottomPadding: 6; width: parent.width - 36; spacing: 7
                        KvRowRich { k: "Source"; explorer: page.explorer
                            vHtml: {
                                if (!page.cidPin) return "";
                                if (page.cidPin.iaId) return '<a href="' + page.cidPin.iaHref + '" style="color:' + ZTheme.link + '">archive.org/details/' + ZT.esc(page.cidPin.iaId) + "</a>";
                                return page.cidPin.source ? ZT.esc(page.cidPin.source) : "-";
                            } }
                        KvRow { explorer: page.explorer; k: "Pin id"; v: page.cidPin && page.cidPin.cid ? page.cidPin.cid : "" }
                        KvRow { explorer: page.explorer; k: "Pinned by"; v: page.cidPin && page.cidPin.pinnedBy ? page.cidPin.pinnedBy : ""; mono: false }
                        KvRow { explorer: page.explorer; k: "Pinned at"; mono: false
                            v: page.cidPin && page.cidPin.pinnedAtUtc ? (page.cidPin.pinnedAtUtc + "  (" + page.cidPin.pinnedAtAge + ")") : "" }
                        KvRow { explorer: page.explorer; k: "Total size"; mono: false
                            v: page.cidPin && page.cidPin.sizeHuman ? (page.cidPin.sizeHuman + "  (" + page.cidPin.sizeBytes + " bytes)") : "" }
                    }
                    // files table
                    Column {
                        x: 18; topPadding: 8; width: parent.width - 36; visible: !!(page.cidPin && page.cidPin.files.length)
                        Rectangle {
                            width: parent.width; height: 34; color: ZTheme.theadBg
                            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                            Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 12 } spacing: 24
                                Text { text: "File (" + (page.cidPin ? page.cidPin.files.length : 0) + ")"; color: ZTheme.soft; font.pixelSize: 11; font.weight: Font.DemiBold }
                            }
                        }
                        Repeater {
                            model: page.cidPin ? page.cidPin.files : []
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width; height: 34; color: "transparent"
                                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                                RowLayout { anchors { fill: parent; leftMargin: 12; rightMargin: 12 } spacing: 16
                                    Text { Layout.preferredWidth: 180; elide: Text.ElideRight; text: modelData.name; color: ZTheme.fg; font.pixelSize: 12 }
                                    Text { Layout.fillWidth: true; elide: Text.ElideMiddle; text: modelData.cidShort; color: ZTheme.soft; font.pixelSize: 11; font.family: "ui-monospace, Menlo, Consolas, monospace" }
                                    RichLabel { explorer: page.explorer; font.pixelSize: 12
                                        text: '<a href="' + modelData.viewHref + '" style="color:' + ZTheme.link + '">view</a> · <a href="' + modelData.dlHref + '" style="color:' + ZTheme.link + '">download</a>' }
                                }
                            }
                        }
                    }
                    Text {
                        x: 18; topPadding: 8; bottomPadding: 16; width: parent.width - 36
                        color: ZTheme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
                        text: page.cidPin ? ("File links resolve through the IPFS gateway " + page.cidPin.gateway + " - content is served by the IPFS network, not by this explorer"
                            + (page.cidPin.gatewayConfigured ? "" : " (operators can set ZONE_SCAN_IPFS_GATEWAY to use their own gateway)") + ".") : ""
                    }
                }
            }

            // raw payload panel
            Item { width: 1; height: 16; visible: !!(page.tx && page.tx.kind === "raw") }
            Rectangle {
                visible: !!(page.tx && page.tx.kind === "raw")
                width: parent.width; height: rawCol.implicitHeight
                color: ZTheme.panel; radius: 12; border.width: 1; border.color: ZTheme.line; clip: true
                Column {
                    id: rawCol; width: parent.width
                    Rectangle {
                        width: parent.width; height: 46
                        gradient: Gradient { GradientStop { position: 0; color: ZTheme.pheadA } GradientStop { position: 1; color: ZTheme.pheadB } }
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
                        Row { anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 } spacing: 8
                            Text { text: "Raw inscription payload"; color: ZTheme.navy; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                            Text { color: ZTheme.muted; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (!page.tx) return "";
                                    var hasText = page.tx.raw_text != null && page.tx.raw_text !== "";
                                    return (page.tx.raw_len ? ZT.num(page.tx.raw_len) + " bytes · " : "") + (hasText ? "UTF-8 text" : "binary (hex)");
                                } }
                        }
                    }
                    Column {
                        x: 18; topPadding: 14; bottomPadding: 18; width: parent.width - 36; spacing: 9
                        Text {
                            width: parent.width; color: ZTheme.muted; font.pixelSize: 12; wrapMode: Text.WordWrap
                            text: {
                                if (!page.tx) return "";
                                var hasText = page.tx.raw_text != null && page.tx.raw_text !== "";
                                return "A raw text/data inscription - not a sequencer block. The bytes below are its on-chain content, shown " + (hasText ? "as decoded UTF-8 text" : "as a hex dump") + ".";
                            }
                        }
                        Rectangle {
                            width: parent.width; height: Math.min(360, payTxt.implicitHeight + 24)
                            color: ZTheme.panel2; radius: 7; border.width: 1; border.color: ZTheme.line2; clip: true
                            Flickable {
                                anchors.fill: parent; contentHeight: payTxt.implicitHeight + 24; clip: true
                                Text {
                                    id: payTxt; x: 14; y: 12; width: parent.width - 28
                                    font.family: "ui-monospace, Menlo, Consolas, monospace"; font.pixelSize: 12; color: ZTheme.fg
                                    wrapMode: Text.WrapAnywhere
                                    text: {
                                        if (!page.tx) return "";
                                        var hasText = page.tx.raw_text != null && page.tx.raw_text !== "";
                                        return hasText ? page.tx.raw_text : ZT.fmtHex(page.tx.raw_hex || "");
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
