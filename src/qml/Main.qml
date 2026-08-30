import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "components"
import "pages"
import "theme"
import "theme.js" as ZT

Rectangle {
    id: root
    color: ZTheme.bg

    // ── stock QtQuick.Controls ───────────────────────────────────────────────
    // Everything in this tree that we draw ourselves flips through ZTheme bindings. The ~26
    // STOCK controls (8 ScrollBars, 2 ComboBoxes, 2 TextFields, a TextArea, 2 BusyIndicators,
    // the FilterBar's Button and its 11 CheckBoxes) do not: they paint from `palette.*`, which
    // owes us nothing. One block here covers every one of them that is an ITEM in this tree —
    // pages are created into `pageHost`, so they inherit it too.
    //
    // The light column is the Basic style's OWN default palette, measured at runtime and copied
    // back verbatim, so declaring it is a no-op in light: with this block applied, every
    // control's resolved palette is byte-identical to having no block at all. Values live in
    // ZTheme (ctl*) beside the rest of the theme, not here.
    //
    // Two things this block does NOT reach, both verified rather than assumed:
    //   * a free-standing Popup — FilterBar's type menu carries its own block (see there);
    //   * an attached ToolTip — covered by the three Bindings at the bottom of this file.
    //
    // And it only works at all while the host installs the Basic style
    // (QQuickStyle::setStyle("Basic"), Basecamp MainContainer.cpp:73). Basic and Fusion honour
    // `palette`; Material and Universal largely ignore it. One line changed over there silently
    // un-themes all of this, and nothing in this module's CI can see it happen.
    palette.window:          ZTheme.ctlWindow
    palette.windowText:      ZTheme.ctlWindowText
    palette.base:            ZTheme.ctlBase
    palette.text:            ZTheme.ctlText
    palette.button:          ZTheme.ctlButton
    palette.buttonText:      ZTheme.ctlButtonText
    palette.mid:             ZTheme.ctlMid
    palette.midlight:        ZTheme.ctlMidlight
    palette.light:           ZTheme.ctlLight
    palette.dark:            ZTheme.ctlDark
    palette.shadow:          ZTheme.ctlShadow
    palette.highlight:       ZTheme.ctlHighlight
    palette.highlightedText: ZTheme.ctlHighlightedText
    palette.placeholderText: ZTheme.ctlPlaceholderText
    palette.brightText:      ZTheme.ctlBrightText
    palette.toolTipBase:     ZTheme.ctlToolTipBase
    palette.toolTipText:     ZTheme.ctlToolTipText

    readonly property var backend: logos.module("zonescan_lite")
    property bool ready: false
    readonly property var state: backend ? backend.state : null
    readonly property var l1: state && state.l1 ? state.l1 : null
    readonly property var seqs: state && state.sequencers ? state.sequencers : []

    // Live connection health, straight from the backend PROP. The dot next to it reports the
    // L1 chain, which is a different fact: the L1 can be perfectly healthy in the last
    // snapshot we hold while zonescan itself has been unreachable for minutes.
    readonly property string conn: backend ? (backend.connectionStatus || "") : ""
    readonly property bool stale: conn === "Error"
    readonly property double lastOk: backend ? (backend.lastOkUnix || 0) : 0
    // ZT.fmtAge() reads Date.now(), which the binding engine cannot observe, and lastOkUnix
    // stops changing the moment the outage starts - so the banner's age would freeze at
    // "0 secs ago" for its whole duration. Tick a property the binding depends on instead.
    property int ageTick: 0
    Timer { running: root.stale; repeat: true; interval: 1000; onTriggered: root.ageTick++ }

    // rev bumps whenever live state/registry changes; state-dependent bindings
    // across the pages reference explorer.rev to re-evaluate (theme.js reads the
    // module-level state/PROGS/GUESS/SCHEMAS, which QML can't observe directly).
    property int rev: 0
    function _syncRegistry() {
        if (!backend) return;
        ZT.setState(backend.state || null);
        ZT.setRegistry(backend.programs || {}, backend.guesses || {}, backend.schemas || {});
        ZT.setBaseUrl(backend.baseUrl || "");
        rev = rev + 1;
    }
    Connections {
        target: root.backend
        ignoreUnknownSignals: true
        function onStateChanged()    { root._syncRegistry(); }
        function onProgramsChanged()  { root._syncRegistry(); }
        function onGuessesChanged()   { root._syncRegistry(); }
        function onSchemasChanged()   { root._syncRegistry(); }
        function onBaseUrlChanged()   { root._syncRegistry(); }
        function onTxsChanged()       { root.rev = root.rev + 1; }   // live feed tick
        // The contract's error signal. It was declared from the start and never emitted or
        // connected, so every transient failure was silent on both sides.
        function onError(message)     { root.notify(message, true); }
    }

    // logos.watch wrapper — resolve a SLOT's pending token.
    function watch(promise, onOk, onErr) { logos.watch(promise, onOk, onErr); }

    // one sequencer ⇒ the home feed IS that zone's feed.
    function soloChannel() { return root.seqs.length === 1 ? root.seqs[0].channel : null; }

    // ── transient notices (copy confirmations, backend errors) ───────────────
    property string noticeText: ""
    property bool noticeIsError: false
    function notify(msg, isError) {
        if (!msg) return;
        root.noticeText = String(msg);
        root.noticeIsError = !!isError;
        noticeTimer.restart();
    }
    Timer { id: noticeTimer; interval: 6000; onTriggered: root.noticeText = "" }

    // ── clipboard ────────────────────────────────────────────────────────────
    // QML exposes no clipboard object, so route through an off-screen TextEdit, which is the
    // supported path. Every identifier in the app used to be a plain Text: unselectable and
    // uncopyable, so the app consumed pasted hashes it would not let you produce.
    TextEdit { id: clipHelper; visible: false; width: 0; height: 0 }
    function copyText(s, what) {
        if (s === undefined || s === null || String(s).length === 0) return;
        clipHelper.text = String(s);
        clipHelper.selectAll();
        clipHelper.copy();
        clipHelper.text = "";
        root.notify((what || "Value") + " copied", false);
    }

    // ── local zone: rows decoded from a sequencer on this machine ────────────
    // These exist only in this process - zonescan has never seen that chain and stores
    // nothing about it - so a row that links into the remote explorer can only ever answer
    // "not found". LocalZonePanel registers them here and TxPage resolves from this index
    // before it considers a network lookup.
    property var localTxIndex: ({})
    function registerLocalTxs(rows) {
        if (!rows) return;
        var idx = root.localTxIndex;
        for (var i = 0; i < rows.length; i++) if (rows[i] && rows[i].hash) idx[rows[i].hash] = rows[i];
        root.localTxIndex = idx;
    }
    function localTx(hash) { return (hash && root.localTxIndex[hash]) || null; }
    function isLocalChannel(ch) { return ch === ZT.LOCAL_ZONE; }

    // ── router: zone-scoped descriptors + history stack ─────────────────────
    property var nav: ({ type: "home" })
    property var history: [({ type: "home" })]
    property int histIndex: 0
    readonly property bool canBack: histIndex > 0
    readonly property bool canForward: histIndex < history.length - 1
    // The current descriptor, flattened into observable strings. `nav` is a var holding a JS
    // object, which nothing outside QML can read; these make the active route legible to
    // bindings and to the integration suite, which otherwise has to infer the route from
    // rendered text - unreliable now that pages are cached and keep their text while hidden.
    readonly property string navType: (nav && nav.type) ? nav.type : "home"
    readonly property string navChannel: (nav && nav.channel) ? nav.channel : ""
    readonly property string navId: (nav && nav.id) ? nav.id : ""

    function _same(a, b) { return a && b && a.type === b.type && a.channel === b.channel && a.id === b.id; }
    function _push(desc) {
        if (_same(history[histIndex], desc)) { _render(); return; }   // same page ⇒ re-show (a retry)
        var h = history.slice(0, histIndex + 1); h.push(desc);
        history = h; histIndex = h.length - 1; nav = desc; _render();
    }
    // The zone most recently opened, so the Home sidebar can mark where you were. Home now
    // survives a Back (it is cached, not rebuilt), which makes that marker worth having.
    property string lastZoneChannel: ""
    function navHome()             { _push({ type: "home" }); }
    function navZone(ch)           { root.lastZoneChannel = ch || ""; _push({ type: "zone", channel: ch }); }
    function navTx(ch, hash)       { _push({ type: "tx", channel: ch, id: hash }); }
    function navProgram(ch, prog)  { _push({ type: "program", channel: ch, id: prog }); }
    function navToken(ch, tid)     { _push({ type: "token", channel: ch, id: tid }); }
    function navWallet(addr, ch)   { _push({ type: "wallet", channel: ch || "", id: addr }); }
    function navBack()    { if (canBack)    { histIndex--; nav = history[histIndex]; _render(); } }
    // _push truncates the forward branch (browser semantics), but navBack deliberately does
    // not - so the entries above histIndex were reachable by nothing until this existed.
    function navForward() { if (canForward) { histIndex++; nav = history[histIndex]; _render(); } }

    // link scheme from theme.js: "<kind>:<channel>:<id>" (zone has no id).
    function routeLink(url) {
        var s = String(url);
        if (/^https?:\/\//i.test(s)) { Qt.openUrlExternally(s); return; }   // external (IPFS gateway) links
        var parts = s.split(":");
        var kind = parts[0], ch = parts[1] || "", id = parts.slice(2).join(":");
        if (kind === "wallet") navWallet(id, ch);
        else if (kind === "token") navToken(ch, id);
        else if (kind === "tx") navTx(ch, id);
        else if (kind === "program") navProgram(ch, id);
        else if (kind === "zone") navZone(ch);
    }

    // ── page host: cached instances, not a re-created Loader ─────────────────
    // setSource() destroyed and rebuilt the page on every navigation, so Back threw away
    // scroll position, filters, the whole loaded feed, and a local-zone walk of up to 20k
    // blocks. Pages are kept alive per descriptor and swapped by visibility instead.
    property var pageCache: ({})
    property var pageOrder: []          // LRU, least-recent first
    readonly property int pageCacheMax: 6
    property string pageError: ""

    function _key(d) { return d.type + "|" + (d.channel || "") + "|" + (d.id || ""); }
    function _urlFor(d) {
        if (d.type === "tx")      return "pages/TxPage.qml";
        if (d.type === "zone")    return "pages/ZonePage.qml";
        if (d.type === "program") return "pages/ProgramPage.qml";
        if (d.type === "token")   return "pages/TokenPage.qml";
        if (d.type === "wallet")  return "pages/AccountPage.qml";
        return "pages/HomePage.qml";
    }
    function _propsFor(d) {
        var p = { explorer: root, visible: false };
        if (d.type === "tx")           { p.channel = d.channel; p.txHash = d.id; }
        else if (d.type === "zone")    { p.channel = d.channel; }
        else if (d.type === "program") { p.channel = d.channel; p.progId = d.id; }
        else if (d.type === "token")   { p.channel = d.channel; p.tokenId = d.id; }
        else if (d.type === "wallet")  { p.channel = d.channel; p.accId = d.id; }
        return p;
    }
    function _touch(key) {
        var i = root.pageOrder.indexOf(key);
        if (i >= 0) root.pageOrder.splice(i, 1);
        root.pageOrder.push(key);
    }
    function _evict() {
        var cur = _key(root.nav);
        while (root.pageOrder.length > root.pageCacheMax) {
            var k = root.pageOrder[0];
            if (k === cur) break;
            root.pageOrder.shift();
            var it = root.pageCache[k];
            delete root.pageCache[k];
            if (it) it.destroy();
        }
    }
    function _render() {
        var d = root.nav, key = _key(d);
        root.pageError = "";
        var item = root.pageCache[key] || null;
        if (item === null) {
            // A page that fails to compile used to render as an unexplained empty rectangle;
            // three such errors shipped in 0.1.0 (see commit 59d4bfd).
            var comp = Qt.createComponent(Qt.resolvedUrl(_urlFor(d)), Component.PreferSynchronous);
            if (comp.status === Component.Error) {
                root.pageError = comp.errorString();
                for (var kk in root.pageCache) root.pageCache[kk].visible = false;
                return;
            }
            item = comp.createObject(pageHost, _propsFor(d));
            if (item === null) {
                root.pageError = "could not create " + _urlFor(d);
                for (var k2 in root.pageCache) root.pageCache[k2].visible = false;
                return;
            }
            item.anchors.fill = pageHost;
            root.pageCache[key] = item;
        }
        _touch(key);
        for (var k3 in root.pageCache) root.pageCache[k3].visible = (k3 === key);
        _evict();
        if (typeof item.pageShown === "function") item.pageShown();
    }

    // ── search ───────────────────────────────────────────────────────────────
    property bool searching: false
    property string searchNote: ""
    // 64 hex chars is ambiguous: a tx hash, a channel id, or a public key in hex. Resolve in
    // order of certainty. Every branch now ENDS somewhere the user can see - the old version
    // guessed an account for input that matched nothing, so a typo'd hash landed on
    // "account not found" rather than saying the search matched nothing.
    function doSearch(v) {
        v = (v || "").trim();
        root.searchNote = "";
        if (!v) { root.searchNote = "Enter a transaction hash, account, token, channel id or zone name."; return; }
        if (!backend) { root.searchNote = "Not connected to zonescan yet."; return; }
        // A named channel resolves by its name: the zones list shows "Paradox Computer", so
        // typing that has to find it rather than fall through to "account not found".
        var aliased = ZT.channelForAlias(v);
        if (aliased) { root.navZone(aliased); return; }
        root.searching = true;
        if (/^(0x)?[0-9a-fA-F]{64}$/.test(v)) {
            var h = v.replace(/^0x/, "").toLowerCase();
            watch(backend.getTx(h),
                  function (t) {
                      root.searching = false;
                      if (t && t.ok && t.channel) { root.navTx(t.channel, h); return; }
                      var sq = (backend.state && backend.state.sequencers) || [];
                      for (var i = 0; i < sq.length; i++) if (sq[i].channel === h) { root.navZone(h); return; }
                      if (t && !t.ok && t.status !== 404) {
                          root.searchNote = "Search failed: " + (t.error || "zonescan did not answer");
                          return;
                      }
                      // 32 bytes of hex spell the same key an account id spells in base58, so
                      // offer that reading before giving up. hexToB58 always answers for
                      // 64 lowercase hex, which is why there is no further fallback here.
                      root.navWallet(ZT.hexToB58(h), null);
                  },
                  function ()  { root.searching = false; root.searchNote = "Search failed: zonescan did not answer."; });
            return;
        }
        watch(backend.whatIs(v),
              function (r) {
                  root.searching = false;
                  if (r && r.ok && r.kind === "token" && r.channel) { root.navToken(r.channel, v); return; }
                  if (r && r.ok) { root.navWallet(v, null); return; }
                  if (r && r.status === 404) { root.searchNote = "Nothing matched \"" + v + "\"."; return; }
                  root.searchNote = "Search failed: " + ((r && r.error) || "zonescan did not answer");
              },
              function ()  { root.searching = false; root.searchNote = "Search failed: zonescan did not answer."; });
    }

    // ── settings: which zonescan node to read from ──────────────────────────
    property bool settingsOpen: false
    property bool nodeBusy: false
    property string nodeMsg: ""
    property bool nodeMsgError: false
    readonly property string nodeSource: backend ? (backend.nodeSource || "") : ""

    // Every cached page holds rows fetched from the PREVIOUS node. Showing them under a new
    // node's name would attribute one chain's data to another, so the cache is dropped whole
    // and history collapses back to home.
    function _dropPages() {
        for (var k in root.pageCache) {
            var it = root.pageCache[k];
            delete root.pageCache[k];
            if (it) it.destroy();
        }
        root.pageOrder = [];
    }

    // `url` empty means "forget my choice" and fall back to $ZONESCAN_BASE_URL / the default.
    // The backend probes a candidate first and changes nothing if it fails, so a rejected URL
    // leaves the app exactly where it was.
    function applyNode(url) {
        if (!backend || root.nodeBusy) return;
        root.nodeBusy = true; root.nodeMsgError = false;
        root.nodeMsg = url === "" ? "Resetting…"
                                  : ("Checking " + ZT.normalizeNodeUrl(url) + " …");
        watch(backend.setNodeUrl(url),
              function (r) {
                  root.nodeBusy = false;
                  if (!r || !r.ok) {
                      root.nodeMsgError = true;
                      root.nodeMsg = (r && r.error) || "Could not use that node.";
                      return;
                  }
                  root.nodeMsgError = false;
                  root.nodeMsg = "";
                  root.history = [({ type: "home" })]; root.histIndex = 0; root.nav = root.history[0];
                  root._dropPages(); root._render();
                  root.settingsOpen = false;
                  root.notify(r.reset ? ("Reset to " + r.url)
                                      : ("Now reading " + r.url + (r.zones !== undefined ? " · " + r.zones + " zones" : "")),
                              false);
              },
              function () {
                  root.nodeBusy = false; root.nodeMsgError = true;
                  root.nodeMsg = "The check did not complete.";
              });
    }

    function openSettings() {
        root.nodeMsg = ""; root.nodeMsgError = false;
        nodeField.text = backend ? (backend.baseUrl || "") : "";
        root.settingsOpen = true;
        nodeField.forceActiveFocus();
        // Select it all, so typing REPLACES the address instead of appending to it. Without
        // this, typing "zonescan.paradox.computer" into a field already holding
        // "https://zonescan.paradox.computer" silently produces the two concatenated.
        nodeField.selectAll();
    }

    function doRefresh() {
        if (!backend) return;
        backend.refresh();
        root.notify("Refreshing…", false);
    }

    Connections { target: logos
        function onViewModuleReadyChanged(m, isReady) { if (m === "zonescan_lite") { root.ready = isReady && root.backend !== null; root._syncRegistry(); } } }
    Component.onCompleted: {
        root.ready = root.backend !== null && logos.isViewModuleReady("zonescan_lite");
        root._syncRegistry();
        root._render();
        searchInput.forceActiveFocus();
    }

    // ── keyboard ─────────────────────────────────────────────────────────────
    // None of this existed: the only history control was a 30x30 MouseArea, and there was no
    // way to reach the search field without the mouse.
    // No Backspace here: a global Shortcut fires ahead of the focused item, so deleting a
    // character in the search field would navigate Back instead.
    Shortcut { sequence: "Esc"; onActivated: {
        if (root.settingsOpen) root.settingsOpen = false;
        else if (searchInput.activeFocus) { root.searchNote = ""; searchInput.focus = false; }
        else root.navBack();
    } }
    Shortcut { sequences: ["Ctrl+,"]; onActivated: root.openSettings() }
    Shortcut { sequence: "Alt+Left"; onActivated: root.navBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: root.navForward() }
    Shortcut { sequences: ["Ctrl+F", "Ctrl+L"]; onActivated: { searchInput.forceActiveFocus(); searchInput.selectAll(); } }
    Shortcut { sequence: "/"; enabled: !searchInput.activeFocus; onActivated: searchInput.forceActiveFocus() }
    Shortcut { sequences: [StandardKey.Refresh, "Ctrl+R"]; onActivated: root.doRefresh() }
    Shortcut { sequence: "Alt+Home"; onActivated: root.navHome() }

    // ── Topbar ──────────────────────────────────────────────────────────────
    Rectangle {
        id: topbar
        anchors { top: parent.top; left: parent.left; right: parent.right }
        height: 68; z: 10
        gradient: Gradient { GradientStop { position: 0; color: ZTheme.topbarA } GradientStop { position: 1; color: ZTheme.topbarB } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.topbarLine }
        RowLayout { anchors { fill: parent; leftMargin: 18; rightMargin: 18 } spacing: 18
            Row { spacing: 11
                // Two rasters, not one recoloured raster: every opaque pixel of logo.png is
                // near-black (avg luma 15.0 over 1307 opaque px), so it disappears on a dark
                // topbar - and QML's Image has no colour filter, with Qt5Compat.GraphicalEffects
                // absent from the runtime closure. logo-light.png is the same file with the
                // alpha channel byte-identical and the RGB replaced by the dark `fg`, #ffffff.
                // `_mode`, not `userMode`: _mode changes AFTER theme.js has been pushed.
                Image { source: ZTheme._mode === "dark" ? "icons/logo-light.png" : "icons/logo.png"
                    width: 40; height: 40; anchors.verticalCenter: parent.verticalCenter; fillMode: Image.PreserveAspectFit
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.navHome() } }
                Text { anchors.verticalCenter: parent.verticalCenter; textFormat: Text.StyledText
                    text: "<b>zone</b>scan"; color: ZTheme.navy; font.pixelSize: 19; font.weight: Font.Bold; font.letterSpacing: 0.2
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.navHome() } }
                // Module version — so a bug report can quote the build it came from.
                Text { anchors.verticalCenter: parent.verticalCenter; visible: !!(root.backend && root.backend.version)
                    text: root.backend ? ("v" + root.backend.version) : ""; color: ZTheme.soft; font.pixelSize: 11
                    font.family: "ui-monospace, Menlo, Consolas, monospace" }
            }
            Item { Layout.fillWidth: true }
            // settings — pick which zonescan node the module reads from
            Rectangle {
                implicitWidth: 30; implicitHeight: 28; radius: 8; border.width: 1
                border.color: root.settingsOpen ? ZTheme.fg : ZTheme.line2
                gradient: Gradient { GradientStop { position: 0; color: ZTheme.ctrlA } GradientStop { position: 1; color: ZTheme.ctrlB } }
                Text { anchors.centerIn: parent; text: "⚙"; color: ZTheme.muted; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: root.settingsOpen ? root.settingsOpen = false : root.openSettings()
                    ToolTip.visible: containsMouse; ToolTip.text: "Settings (Ctrl+,)" }
            }
            // manual refresh — refresh() was implemented and documented from the start with
            // nothing in the view able to call it.
            Rectangle {
                implicitWidth: 30; implicitHeight: 28; radius: 8; border.width: 1; border.color: ZTheme.line2
                gradient: Gradient { GradientStop { position: 0; color: ZTheme.ctrlA } GradientStop { position: 1; color: ZTheme.ctrlB } }
                Text { anchors.centerIn: parent; text: "⟳"; color: ZTheme.muted; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.doRefresh()
                    ToolTip.visible: containsMouse; ToolTip.text: "Refresh (Ctrl+R)"; hoverEnabled: true }
            }
            // sync pill — reports zonescan reachability FIRST, then the L1's own health.
            Rectangle {
                implicitWidth: syncRow.implicitWidth + 22; implicitHeight: 28; radius: 8; border.width: 1; border.color: ZTheme.line2
                gradient: Gradient { GradientStop { position: 0; color: ZTheme.ctrlA } GradientStop { position: 1; color: ZTheme.ctrlB } }
                Row { id: syncRow; anchors.centerIn: parent; spacing: 7
                    Rectangle { width: 8; height: 8; radius: 4; anchors.verticalCenter: parent.verticalCenter
                        color: { if (root.stale) return ZTheme.red;
                                 if (!root.l1 || !root.l1.reachable) return ZTheme.red;
                                 if ((root.l1.mode && root.l1.mode !== "online") || root.l1.advancing === false) return ZTheme.silver;
                                 return ZTheme.green; } }
                    Text { anchors.verticalCenter: parent.verticalCenter; color: ZTheme.muted; font.pixelSize: 12
                        text: { if (root.stale) return "zonescan unreachable";
                                if (root.conn === "Connecting") return "connecting…";
                                if (!root.l1) return "connecting…";
                                if (!root.l1.reachable) return "L1 unreachable";
                                if (root.l1.mode && root.l1.mode !== "online") return "L1 " + (root.l1.mode === "bootstrapping" ? "syncing" : root.l1.mode);
                                if (root.l1.advancing === false) return "L1 not advancing";
                                return root.l1.synced === true ? "L1 synced" : "L1 online"; } }
                }
            }
            // L1 REST version pill (mono navy)
            Rectangle {
                visible: !!(root.l1 && root.l1.reachable && root.l1.l1_version)
                implicitWidth: verT.implicitWidth + 22; implicitHeight: 28; radius: 8; border.width: 1; border.color: ZTheme.line2
                gradient: Gradient { GradientStop { position: 0; color: ZTheme.ctrlA } GradientStop { position: 1; color: ZTheme.ctrlB } }
                Text { id: verT; anchors.centerIn: parent; color: ZTheme.navy; font.pixelSize: 12; font.weight: Font.DemiBold
                    font.family: "ui-monospace, Menlo, Consolas, monospace"; text: root.l1 ? ("L1 v" + (root.l1.l1_version || "")) : "" }
            }
            Text { Layout.maximumWidth: 280; elide: Text.ElideRight; text: root.state ? (root.state.node || "-") : "-"
                color: ZTheme.soft; font.pixelSize: 11; font.family: "ui-monospace, Menlo, Consolas, monospace" }
        }
    }

    // ── Hero + search ────────────────────────────────────────────────────────
    Rectangle {
        id: hero
        anchors { top: topbar.bottom; left: parent.left; right: parent.right }
        height: heroCol.implicitHeight + 44
        // radial-ish: approximate the top-left radial with a diagonal gradient
        gradient: Gradient { GradientStop { position: 0; color: ZTheme.heroA } GradientStop { position: 1; color: ZTheme.heroB } }
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.heroLine }
        Column {
            id: heroCol
            anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 18; rightMargin: 18; topMargin: 22 }
            spacing: 12
            RowLayout { width: parent.width; spacing: 10
                Rectangle { visible: root.canBack; implicitWidth: 30; implicitHeight: 30; radius: 8; color: backMa.containsMouse ? ZTheme.heroBtnHover : ZTheme.heroBtnBg; border.width: 1; border.color: ZTheme.heroBtnBd
                    Text { anchors.centerIn: parent; text: "←"; color: ZTheme.heroFg; font.pixelSize: 15 }
                    MouseArea { id: backMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.navBack()
                        ToolTip.visible: containsMouse; ToolTip.text: "Back (Alt+Left)" } }
                Rectangle { visible: root.canForward; implicitWidth: 30; implicitHeight: 30; radius: 8; color: fwdMa.containsMouse ? ZTheme.heroBtnHover : ZTheme.heroBtnBg; border.width: 1; border.color: ZTheme.heroBtnBd
                    Text { anchors.centerIn: parent; text: "→"; color: ZTheme.heroFg; font.pixelSize: 15 }
                    MouseArea { id: fwdMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.navForward()
                        ToolTip.visible: containsMouse; ToolTip.text: "Forward (Alt+Right)" } }
                // h1 + sub
                Row {
                    spacing: 8; Layout.alignment: Qt.AlignVCenter; Layout.fillWidth: true
                    Text { text: "Logos Execution Zone Explorer"; color: ZTheme.heroFg; font.pixelSize: 18; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    Text { visible: parent.width > 620; text: ":: data, liveness and consistency of Logos L2"; color: ZTheme.heroSub; font.pixelSize: 13; anchors.verticalCenter: parent.verticalCenter }
                }
            }
            Rectangle { width: Math.min(parent.width, 1204); height: 48; radius: 11; color: ZTheme.searchBg; border.width: 1; border.color: ZTheme.searchBd; clip: true
                RowLayout { anchors.fill: parent; spacing: 0
                    TextField { id: searchInput; Layout.fillWidth: true; Layout.fillHeight: true
                        enabled: !root.searching
                        placeholderText: "Search by Txn Hash / Account / Channel"; leftPadding: 16; rightPadding: 16
                        color: ZTheme.fg; font.pixelSize: 14; font.family: "ui-monospace, Menlo, Consolas, monospace"
                        background: Rectangle { color: ZTheme.searchBg }
                        onAccepted: root.doSearch(text)
                        onTextChanged: root.searchNote = "" }
                    Rectangle { Layout.fillHeight: true; implicitWidth: 96
                        gradient: Gradient { GradientStop { position: 0; color: root.searching ? ZTheme.btnBusyA : ZTheme.actionA } GradientStop { position: 1; color: root.searching ? ZTheme.btnBusyB : ZTheme.actionB } }
                        Text { anchors.centerIn: parent; text: root.searching ? "…" : "Search"; color: ZTheme.onDark; font.pixelSize: 14; font.weight: Font.DemiBold }
                        MouseArea { anchors.fill: parent; enabled: !root.searching; cursorShape: Qt.PointingHandCursor; onClicked: root.doSearch(searchInput.text) } }
                }
            }
            // search feedback — an empty, in-flight or unmatched search used to look identical
            // to no search at all.
            Text { visible: root.searchNote !== ""; text: root.searchNote; color: ZTheme.heroErrFg; font.pixelSize: 12
                width: parent.width; wrapMode: Text.WordWrap }
        }
    }

    // ── stale-data banner ────────────────────────────────────────────────────
    // connectionStatus was published by the backend and read by nothing, so an outage kept
    // rendering the last good snapshot as though it were live.
    Rectangle {
        id: staleBar
        anchors { top: hero.bottom; left: parent.left; right: parent.right }
        height: root.stale ? 34 : 0
        visible: root.stale
        color: ZTheme.warnBg
        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.warnLine }
        RowLayout {
            anchors { fill: parent; leftMargin: 18; rightMargin: 18 }
            spacing: 10
            Text { color: ZTheme.warnFg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight
                text: {
                    root.ageTick;
                    var age = root.lastOk > 0 ? ZT.fmtAge(root.lastOk) : "";
                    return "Can't reach zonescan — showing the last snapshot"
                         + (age ? " from " + age : "") + ". Figures below are not live.";
                } }
            Rectangle { implicitWidth: 62; implicitHeight: 22; radius: 6; color: ZTheme.warnBtnBg; border.width: 1; border.color: ZTheme.warnBd
                Text { anchors.centerIn: parent; text: "Retry"; color: ZTheme.warnFg; font.pixelSize: 11; font.weight: Font.DemiBold }
                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.doRefresh() } }
        }
    }

    // ── Page area (own scroll; pages fill it) ────────────────────────────────
    Item { id: pageHost; anchors { top: staleBar.bottom; left: parent.left; right: parent.right; bottom: parent.bottom } }

    // page-load failure (a QML compile error in a page)
    Rectangle {
        anchors.fill: pageHost; visible: root.pageError !== ""; color: ZTheme.bg
        Column {
            anchors.centerIn: parent; width: Math.min(parent.width - 48, 620); spacing: 10
            Text { text: "This page failed to load"; color: ZTheme.fg; font.pixelSize: 15; font.weight: Font.DemiBold
                anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: root.pageError; color: ZTheme.muted; font.pixelSize: 11; width: parent.width; wrapMode: Text.Wrap
                font.family: "ui-monospace, Menlo, Consolas, monospace" }
            Row { spacing: 8; anchors.horizontalCenter: parent.horizontalCenter
                Rectangle { implicitWidth: 74; implicitHeight: 26; radius: 6; color: ZTheme.panel; border.width: 1; border.color: ZTheme.line2
                    Text { anchors.centerIn: parent; text: "Go home"; color: ZTheme.fg; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.navHome() } }
                Rectangle { implicitWidth: 74; implicitHeight: 26; radius: 6; color: ZTheme.panel; border.width: 1; border.color: ZTheme.line2
                    Text { anchors.centerIn: parent; text: "Copy error"; color: ZTheme.fg; font.pixelSize: 12 }
                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.copyText(root.pageError, "Error") } }
            }
        }
    }

    // ── settings panel ───────────────────────────────────────────────────────
    // A scrim + card rather than a Popup: Popups render into an overlay that the offscreen
    // inspector reports as neither visible text nor clickable, which would put this out of
    // reach of the integration spec.
    Rectangle {
        id: settingsScrim
        anchors.fill: parent
        visible: root.settingsOpen
        color: ZTheme.scrim
        z: 40
        MouseArea { anchors.fill: parent; onClicked: root.settingsOpen = false }

        Rectangle {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 560)
            height: card.implicitHeight + 36
            radius: 12; color: ZTheme.panel; border.width: 1; border.color: ZTheme.line2
            // swallow clicks so they do not reach the dismiss scrim underneath
            MouseArea { anchors.fill: parent }

            Column {
                id: card
                anchors { left: parent.left; right: parent.right; top: parent.top
                          leftMargin: 18; rightMargin: 18; topMargin: 18 }
                spacing: 10

                Text { text: "Settings"; color: ZTheme.navy; font.pixelSize: 16; font.weight: Font.DemiBold }

                Text { text: "ZONESCAN NODE"; color: ZTheme.soft; font.pixelSize: 11
                    font.weight: Font.Bold; font.letterSpacing: 0.5 }

                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    color: ZTheme.muted; font.pixelSize: 12; lineHeight: 1.35
                    text: "The explorer reads every zone, transaction and account from this node. "
                        + "It is checked before it is applied: if it cannot be reached, or does not answer "
                        + "like a zonescan node, nothing changes."
                }

                Rectangle {
                    width: parent.width; height: 34; radius: 7
                    color: root.nodeBusy ? ZTheme.bg : ZTheme.ctrlA
                    border.width: 1; border.color: root.nodeMsgError ? ZTheme.warnBd : ZTheme.line2
                    TextInput {
                        id: nodeField
                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                        verticalAlignment: TextInput.AlignVCenter
                        enabled: !root.nodeBusy
                        text: ""
                        color: ZTheme.fg; font.pixelSize: 12
                        font.family: "ui-monospace, Menlo, Consolas, monospace"
                        clip: true; selectByMouse: true
                        onAccepted: root.applyNode(nodeField.text)
                        onTextChanged: { root.nodeMsg = ""; root.nodeMsgError = false; }
                    }
                }

                // where the value in force came from — otherwise "why is it not the URL I
                // exported?" has no answer on screen
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    color: ZTheme.soft; font.pixelSize: 11
                    text: {
                        if (root.nodeSource === "saved") return "In use: your saved choice.";
                        if (root.nodeSource === "env")   return "In use: $ZONESCAN_BASE_URL.";
                        if (root.nodeSource === "default") return "In use: the built-in default.";
                        return "";
                    }
                }

                Text {
                    visible: root.nodeMsg !== ""
                    width: parent.width; wrapMode: Text.WordWrap
                    text: root.nodeMsg
                    color: root.nodeMsgError ? ZTheme.warnFg : ZTheme.muted
                    font.pixelSize: 12
                }

                // ── appearance ──
                // Shaped like HomePage's All | rc | data segment so it reads as the same
                // control. LIGHT is the shipped default; Auto is opt-in and follows the Basecamp
                // shell (its design system ships only a dark theme today, so choosing Auto
                // resolves dark inside the host and dark standalone).
                //
                // The SELECTED test reads ZTheme.userMode - the persisted preference - and not
                // _mode: with Auto chosen against a dark host, _mode is "dark" and would light
                // up the wrong segment. That read is state, never colour; the pill's own
                // colours come from tokens, so it cannot render a half-applied palette.
                Item { width: 1; height: 2 }
                Text { text: "APPEARANCE"; color: ZTheme.soft; font.pixelSize: 11
                    font.weight: Font.Bold; font.letterSpacing: 0.5 }
                Row {
                    spacing: 6
                    Repeater {
                        model: [ {t:"Auto",v:"auto"}, {t:"Light",v:"light"}, {t:"Dark",v:"dark"} ]
                        delegate: Rectangle {
                            id: appSeg
                            required property var modelData
                            readonly property bool sel: ZTheme.userMode === appSeg.modelData.v
                            height: 26; width: appT.implicitWidth + 22; radius: 7
                            color: appSeg.sel ? ZTheme.ctrlSel : ZTheme.ctrlA
                            border.width: 1; border.color: appSeg.sel ? ZTheme.fg : ZTheme.line2
                            Text { id: appT; anchors.centerIn: parent; text: appSeg.modelData.t; font.pixelSize: 12
                                color: appSeg.sel ? ZTheme.fg : ZTheme.muted }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: ZTheme.setUserMode(appSeg.modelData.v) }
                        }
                    }
                }
                Item { width: 1; height: 2 }

                Row {
                    spacing: 8
                    Rectangle {
                        implicitWidth: useT.implicitWidth + 26; implicitHeight: 30; radius: 7
                        color: root.nodeBusy ? ZTheme.primaryBusy : ZTheme.fg
                        Text { id: useT; anchors.centerIn: parent
                            text: root.nodeBusy ? "Checking…" : "Use this node"
                            color: ZTheme.panel; font.pixelSize: 12; font.bold: true }
                        MouseArea { anchors.fill: parent; enabled: !root.nodeBusy
                            cursorShape: Qt.PointingHandCursor; onClicked: root.applyNode(nodeField.text) }
                    }
                    Rectangle {
                        implicitWidth: defT.implicitWidth + 22; implicitHeight: 30; radius: 7
                        color: "transparent"; border.width: 1; border.color: ZTheme.line2
                        Text { id: defT; anchors.centerIn: parent; text: "Reset to default"
                            color: ZTheme.fg; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; enabled: !root.nodeBusy
                            cursorShape: Qt.PointingHandCursor; onClicked: root.applyNode("") }
                    }
                    Rectangle {
                        implicitWidth: closeT.implicitWidth + 22; implicitHeight: 30; radius: 7
                        color: "transparent"; border.width: 1; border.color: ZTheme.line2
                        Text { id: closeT; anchors.centerIn: parent; text: "Close"
                            color: ZTheme.muted; font.pixelSize: 12 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: root.settingsOpen = false }
                    }
                }
                Item { width: 1; height: 2 }
            }
        }
    }

    // ── transient notice toast ───────────────────────────────────────────────
    Rectangle {
        visible: root.noticeText !== ""
        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 22 }
        width: Math.min(noticeT.implicitWidth + 34, root.width - 40)
        height: 34; radius: 8; z: 50
        color: root.noticeIsError ? ZTheme.toastErrBg : ZTheme.toastBg
        border.width: 1; border.color: root.noticeIsError ? ZTheme.toastErrBd : ZTheme.toastBd
        Text { id: noticeT; anchors.centerIn: parent; width: parent.width - 28; elide: Text.ElideRight
            text: root.noticeText; color: root.noticeIsError ? ZTheme.toastErrFg : ZTheme.toastFg; font.pixelSize: 12; horizontalAlignment: Text.AlignHCenter }
        MouseArea { anchors.fill: parent; onClicked: root.noticeText = "" }
    }

    // footer note
    Rectangle { anchors.fill: parent; visible: !root.ready; color: ZTheme.bg
        Column { anchors.centerIn: parent; spacing: 12
            BusyIndicator { running: !root.ready; anchors.horizontalCenter: parent.horizontalCenter }
            Text { text: "Connecting to zonescan…"; color: ZTheme.muted; font.pixelSize: 13; anchors.horizontalCenter: parent.horizontalCenter } }
    }

    // ── the shared ToolTip ───────────────────────────────────────────────────
    // An attached ToolTip does NOT inherit Item.palette (verified: 0 of 17 roles reach it), so
    // without this the ten `ToolTip.text:` sites across Main, ZoneRow, ZBadge, KvRow and
    // TxFeedRow keep painting the light chip on a dark app.
    //
    // `ToolTip.toolTip` is ONE INSTANCE PER WINDOW — checked directly, the object reached from
    // three different items compares identical — so these three lines cover all ten sites. The
    // three roles are exactly what Basic's ToolTip.qml reads: toolTipBase (fill), toolTipText
    // (label), dark (border). Explicit `restoreMode` because the default differs between Qt
    // versions and there is nothing to restore to here.
    Binding { target: root.ToolTip.toolTip; property: "palette.toolTipBase"
              value: ZTheme.ctlToolTipBase; restoreMode: Binding.RestoreNone }
    Binding { target: root.ToolTip.toolTip; property: "palette.toolTipText"
              value: ZTheme.ctlToolTipText; restoreMode: Binding.RestoreNone }
    Binding { target: root.ToolTip.toolTip; property: "palette.dark"
              value: ZTheme.ctlDark; restoreMode: Binding.RestoreNone }
}
