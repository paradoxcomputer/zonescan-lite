// zonescan's exact logic + design tokens, ported 1:1 from the web dashboard
// (src/serve.rs client script). This `.pragma library` file IS the live JS global
// scope: the live globals (state / PROGS / GUESS / SCHEMAS / FLT / LAYOUTS) live here
// as module vars fed by the backend, and the pure functions are ported verbatim.
// HTML-returning functions (instrText / txAction / decode) are rendered by a QML
// Text{ textFormat: RichText } (see RichLabel.qml), links via onLinkActivated.
.pragma library

// ── design tokens (:root) ────────────────────────────────────────────────────
var lightPal = {
    bg:    "#f4f4f5", panel: "#ffffff", panel2: "#f4f4f5",
    line:  "#e6e6e9", line2: "#d4d4da",
    fg:    "#18181b", muted: "#6e6e77", soft: "#9b9ba4",
    link:  "#27272a", navy:  "#18181b", silver:"#c9c9d0",
    green: "#3d8c40", amber: "#9b9ba4", purple:"#52525b", red: "#c0392b",
    heroA: "#3a3a42", heroB: "#0c0c0e",
    rowHover: "#f7f9fd", rowSel: "#eef4ff",
    theadBg:  "#fbfcfe",
    // .htag best-guess tag
    htagFg: "#9a6a00", htagBg: "#fff7e6", htagBd: "#ffe2a8",
    // dimmed guess ink: the low-confidence branch of guessHtml() used to freeze this hex
    // inline, so it could never follow the palette.
    mutedDim: "#8f8f98",
    // "not settling" pill. Deliberately its OWN pair rather than htag*: identical values
    // today, but it is a severity encoding (degraded), not a best-guess tag, and the two
    // must be free to diverge. (The web calls this .v-nosettle and already uses different
    // values - realigning them CHANGES light rendering, so it is held back.)
    nosettleBg: "#fff7e6", nosettleFg: "#9a6a00"
};

// Type-badge palette (.b-ty-*): { bg, fg, bd }. 1:1 with the CSS.
var lightTy = {
    token:                   { bg:"#dcfce7", fg:"#166534", bd:"#bbf7d0" },
    authenticated_transfer:  { bg:"#e0f2fe", fg:"#075985", bd:"#bae6fd" },
    clock:                   { bg:"#f4f4f5", fg:"#71717a", bd:"#e4e4e7" },
    shield:                  { bg:"#ccfbf1", fg:"#0f766e", bd:"#99f6e4" },
    deshield:                { bg:"#fef3c7", fg:"#92400e", bd:"#fde68a" },
    private_send:            { bg:"#ede9fe", fg:"#5b21b6", bd:"#ddd6fe" },
    ata:                     { bg:"#e0e7ff", fg:"#3730a3", bd:"#c7d2fe" },
    amm:                     { bg:"#fae8ff", fg:"#86198f", bd:"#f5d0fe" },
    pinata:                  { bg:"#ffe4e6", fg:"#9f1239", bd:"#fecdd3" },
    pinata_token:            { bg:"#ffe4e6", fg:"#9f1239", bd:"#fecdd3" },
    deploy:                  { bg:"#ffedd5", fg:"#c2410c", bd:"#fdba74" },
    raw:                     { bg:"#fef9c3", fg:"#854d0e", bd:"#fde68a" },
    other:                   { bg:"#f1f1f3", fg:"#52525b", bd:"#e0e0e4" },
    // bd is line2, not a copy of it - the guess chip is deliberately the lowest-contrast
    // chip of the family and borrows the plain hairline.
    guess:                   { bg:"#f8fafc", fg:"#6e6e77", bd: lightPal.line2 }
};
var lightVis = {
    public:  { bg:"#ffffff", fg:"#18181b", bd:"#d4d4d8" },
    private: { bg:"#000000", fg:"#ffffff", bd:"#000000" },
    raw:     { bg:"#fffbeb", fg:"#854d0e", bd:"#fde68a" }
};
// #AARRGGBB, not CSS rgba(): these are assigned straight to QML `color` properties, and QML
// cannot parse "rgba(19,169,123,.14)". An unparseable colour is an INVALID QColor, which paints
// BLACK - so every "final" and "on L1 · finalizing" pill rendered as a black box.
//   rgba(19,169,123,.14) -> alpha .14*255 = 36 = 0x24 -> #2413a97b
//   rgba(37,99,235,.12)  -> alpha .12*255 = 31 = 0x1f -> #1f2563eb
var lightFin = {
    fin:  { label:"final",              bg:"#2413a97b", fg: lightPal.green },
    safe: { label:"on L1 · finalizing", bg:"#1f2563eb", fg:"#1d4ed8" },
    pend: { label:"pending",            bg:"#eef0f3",   fg:"#6b7280" }
};
var lightVer = {
    rc5:  { bg:"#e0e7ff", fg:"#3730a3" },
    rc4:  { bg:"#dcfce7", fg:"#166534" },
    rc3:  { bg:"#fef3c7", fg:"#92400e" },
    data: { bg:"#fef9c3", fg:"#854d0e" }   // .v-data raw data channel
};
// ── the live token objects ───────────────────────────────────────────────────
// Everything downstream reads THESE - `pal.muted`, `tyBadge.guess.bg`, `finBadge[k].bg` - and
// reads them at call time. applyPalette() therefore replaces their CONTENTS in place; it never
// reassigns them. That distinction is load-bearing: `pal` is captured by module scope here and
// by 300-odd `ZT.pal.*` sites in QML, and a reassignment would leave every one of those looking
// at the old object. Nothing anywhere aliases these objects (verified), so in-place is safe.
var pal = {};
var tyBadge = {};
var visBadge = {};
var finBadge = {};
var verBadge = {};

// Copy a whole palette in place. `pal` is flat; the four badge maps are one level of nesting,
// so their entries are merged key-by-key rather than swapped, keeping any entry object a caller
// grabbed earlier (e.g. `var fc = ZT.finBadge[tier]`) pointing at live values.
//
// NOTE this is only the DATA half of a theme flip. A `.pragma library` is invisible to QML's
// binding engine, so mutating these objects repaints nothing on its own - the QML side has to
// re-evaluate. Push here FIRST, then notify.
function applyPalette(p, ty, vis, fin, ver) {
    _copyInto(pal, p);
    _copyMapInto(tyBadge, ty);
    _copyMapInto(visBadge, vis);
    _copyMapInto(finBadge, fin);
    _copyMapInto(verBadge, ver);
}
function _copyInto(dst, src) {
    if (!src) return;
    for (var k in src) dst[k] = src[k];
}
function _copyMapInto(dst, src) {
    if (!src) return;
    for (var k in src) {
        var v = src[k];
        if (v !== null && typeof v === "object") {
            if (!dst[k] || typeof dst[k] !== "object") dst[k] = {};
            _copyInto(dst[k], v);
        } else {
            dst[k] = v;
        }
    }
}
// Light is the boot palette: theme.js is imported (and its first bindings evaluated) before
// anything can choose a mode, so the live objects must never be observed empty.
applyPalette(lightPal, lightTy, lightVis, lightFin, lightVer);

function tyOf(name) { return tyBadge[name] || tyBadge.other; }
function visOf(kind) { return visBadge[kind] || visBadge.public; }

// ── live globals (fed by the backend) ────────────────────────────────────────
var state = null;
var PROGS = {};     // program_id_hex -> human name
var GUESS = {};     // program_id_hex -> best-guess {name,confidence,generic,token,samples}
var SCHEMAS = {};   // program_id_hex -> deployer instruction schema (ABI)
var LAYOUTS = {};   // program_id -> inferred field layout (or null), memoized per session
function setState(s) { state = s; }
function setRegistry(progs, guesses, schemas) {
    if (progs) PROGS = progs;
    if (guesses) GUESS = guesses;
    if (schemas) SCHEMAS = schemas;
}
// Layout memoization. inferLayout() walks a whole sample page of a program's instructions,
// so without this every visit to any tx of a schema-less program re-fetched and re-inferred,
// and the instruction row visibly popped in each time. `null` is a real, cacheable answer
// ("corpus too small / too irregular to infer"), hence the explicit has/ get split.
function setLayout(prog, lay) { if (prog) LAYOUTS[prog] = (lay === undefined ? null : lay); }
function hasLayout(prog) { return !!prog && Object.prototype.hasOwnProperty.call(LAYOUTS, prog); }
function getLayout(prog) { return prog ? (LAYOUTS[prog] || null) : null; }

// ── formatters ───────────────────────────────────────────────────────────────
// num(): thousands-grouped integer (live uses toLocaleString; we group explicitly
// so it matches en-US output regardless of the QML locale).
function num(n) {
    if (n === null || n === undefined || n === "") return "-";
    var x = Number(n);
    if (isNaN(x)) return String(n);
    var neg = x < 0; var s = String(Math.trunc(Math.abs(x)));
    return (neg ? "-" : "") + s.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
// bigint-safe thousands grouping for u128 amount strings.
function grp(s) {
    if (s === null || s === undefined || s === "") return "";
    s = String(s);
    if (!/^\d+$/.test(s)) return s;
    return s.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
function esc(s) {
    if (s === null || s === undefined) return "";
    return String(s).replace(/[&<>"']/g, function (c) {
        return { "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;" }[c];
    });
}
function u(s) { return encodeURIComponent(s); }
function cap(s) { s = s || ""; return s.charAt(0).toUpperCase() + s.slice(1); }
function sh(s, a, b) {
    a = (a === undefined ? 12 : a); b = (b === undefined ? 8 : b);
    if (!s) return "-";
    s = String(s);
    return s.length > a + b + 1 ? s.slice(0, a) + "…" + s.slice(-b) : s;
}
// ── channel aliases ─────────────────────────────────────────────────────────
// Curated in-repo names for channels worth recognising. zonescan publishes no alias endpoint
// and no alias field on a sequencer (/api/aliases is the SPA HTML fallback), so THIS is the
// source of truth: to name a channel, add an entry below.
//
// Keyed by the FULL 64-char channel id, never a prefix — 0101…0101 and 0101…0102 are
// different channels that share their first 60 characters.
var CHAN_ALIAS = {
    "0101010101010101010101010101010101010101010101010101010101010101": "dev · shared default channel",
    "7777777777777777777777777777777777777777777777777777777777777777": "Paradox Computer"
};
function normChan(ch) { return ch ? String(ch).replace(/^0x/, "").toLowerCase() : ""; }
function aliasOf(ch) { var k = normChan(ch); return (k && CHAN_ALIAS[k]) || null; }
// Reverse lookup, so typing the name the UI displays actually finds the zone. Without this the
// search box would answer "account not found" for a name it renders itself.
// Mirror of the backend's normalizeNode(), for showing the user what will actually be
// checked BEFORE the request goes out — a mangled address (see nodeField's select-all) is far
// easier to spot spelled out than inferred from a failure 15s later.
function normalizeNodeUrl(raw) {
    var v = String(raw || "").trim();
    if (!v) return "";
    if (v.indexOf("://") < 0) v = "https://" + v;
    return v.replace(/\/+$/, "");
}
function channelForAlias(name) {
    var q = String(name || "").trim().toLowerCase();
    if (!q) return null;
    for (var k in CHAN_ALIAS) if (String(CHAN_ALIAS[k]).toLowerCase() === q) return k;
    return null;
}
// chanLabel: friendly alias (primary) + short hex (secondary), else plain short hex. The hex
// always stays on screen — the alias names a channel, it does not replace its identity.
function chanLabel(ch, shortHex) {
    var s = esc(shortHex || sh(ch));
    var a = aliasOf(ch);
    return a ? ('<span style="color:' + pal.navy + ';font-weight:600">' + esc(a) + '</span> '
              + '<span style="color:' + pal.soft + '">' + s + '</span>') : s;
}
function fmtAge(unix) {
    if (!unix) return "-";
    var s = Math.max(0, Math.floor(Date.now() / 1000) - unix);
    if (s < 60) return s + " secs ago";
    if (s < 3600) return Math.floor(s / 60) + " mins ago";
    if (s < 86400) return Math.floor(s / 3600) + " hrs ago";
    return Math.floor(s / 86400) + " days ago";
}
function ageOf(t) {
    var ts = t.timestamp || 0;
    if (ts > 1e12) ts = Math.floor(ts / 1000);
    if (ts > 1e9 && ts < 2e10) return fmtAge(ts);
    if (t.seen_unix) return fmtAge(t.seen_unix);
    return "-";
}

// ── program-name resolution ──────────────────────────────────────────────────
function progName(p) { return (p && PROGS[p]) || p; }
function progShort(p) {
    if (p && PROGS[p]) return PROGS[p];
    return (p && /^[0-9a-f]{40,}$/i.test(p)) ? sh(p, 6, 5) : p;
}
function isRawId(p) { return !!(p && /^[0-9a-f]{40,}$/i.test(p) && !PROGS[p]); }
function guessFor(p, row) {
    if (p && PROGS[p]) return null;
    return (row && row.program_guess) || GUESS[p] || null;
}
function guessTip(g) {
    var n = g.samples ? (" · " + g.samples + " tx" + (g.samples === 1 ? "" : "s")) : "";
    if (g.generic) return "value-transfer shape; exact program unresolved - best-guess, unverified" + n;
    return "best-guess from tx fingerprint - unverified · " + Math.round((g.confidence || 0) * 100) + "% confidence" + n;
}
// ≈ name — italic/muted + underline, never styled like a verified name (the live site
// uses a dotted underline; QML RichText only does solid, so we approximate with underline).
function guessHtml(g) {
    var loOpacity = (g.confidence || 0) < 0.6 ? 0.75 : 1.0;
    var col = loOpacity < 1 ? pal.mutedDim : pal.muted;
    return '<span style="color:' + col + ';font-style:italic;text-decoration:underline">'
         + '<span style="font-style:normal;text-decoration:none">≈</span> ' + esc(g.name) + '</span>';
}
// zonescan REST origin — for external links the wallet can't proxy (the guest-ELF download).
// Fed from the backend's `baseUrl` PROP via setBaseUrl(), so it is the origin this build
// actually talks to rather than a copy that can drift from it.
var ZONESCAN_BASE = "";
function setBaseUrl(u) { if (u) ZONESCAN_BASE = String(u).replace(/\/+$/, ""); }
function elfHref(hash) { return ZONESCAN_BASE ? (ZONESCAN_BASE + "/api/elf/" + u(hash)) : ""; }

// ── classification (txVis / txType / typeLabel) ──────────────────────────────
var TYPE_LABEL = {
    clock:"Clock", token:"Token", authenticated_transfer:"Transfer", ata:"ATA", amm:"AMM",
    pinata:"Pinata", pinata_token:"Pinata Token", deploy:"Deploy", shield:"Shield", deshield:"Deshield",
    "private-send":"Transfer", public:"Public", private:"Private", raw:"Inscription"
};
function txVis(t) { return t.kind === "raw" ? "raw" : (t.kind === "private" ? "private" : "public"); }
function txType(t) {
    if (t.kind === "raw") return "raw";
    if (t.kind === "deploy") return "deploy";
    if (t.kind === "private") { var s = t.subtype; return (s === "shield" || s === "deshield") ? s : "authenticated_transfer"; }
    return progName(t.program) || "public";
}
function txKind(t) { return (t.kind === "public" && progName(t.program) === "token") ? "token" : t.kind; }
function typeLabel(ty) {
    if (TYPE_LABEL[ty]) return TYPE_LABEL[ty];
    return /^[0-9a-f]{40,}$/i.test(ty) ? "Program" : cap(ty);
}
function tyClass(ty) { return TYPE_LABEL[ty] ? ty.replace(/-/g, "_") : "other"; }

// Badge descriptor for a tx's Type cell (consumed by ZBadge / TxFeedRow).
// Returns { html?, text?, bg, fg, bd, italic } — html set when it's a ≈guess.
function typeBadgeFor(t) {
    var g = (t.kind === "public") ? guessFor(t.program, t) : null;
    if (g) return { html: guessHtml(g), text: "≈ " + (g.name || "?"), bg: tyBadge.guess.bg, fg: pal.muted, bd: tyBadge.guess.bd, italic: true, guess: true };
    var ty = txType(t); var c = tyOf(tyClass(ty));
    return { text: typeLabel(ty), bg: c.bg, fg: c.fg, bd: c.bd, italic: false, guess: false, title: ty };
}
function visBadgeFor(t) {
    var v = txVis(t); var c = visOf(v);
    return { text: v === "raw" ? "Raw" : (v === "private" ? "Private" : "Public"), bg: c.bg, fg: c.fg, bd: c.bd };
}

// ── shared transactions filter (Visibility + multi-Type + Sort) ──────────────
var FLT = { vis: "all", types: {}, sort: "newest" };   // types: set-as-object {key:true}
var TYPE_CHIPS = [["authenticated_transfer","Transfer"],["token","Token"],["clock","Clock"],
    ["shield","Shield"],["deshield","Deshield"],["amm","AMM"],["ata","ATA"],["pinata","Pinata"],
    ["program","Program"],["deploy","Deploy"],["raw","Inscription"]];
function fltTypesCount() { var n = 0; for (var k in FLT.types) if (FLT.types[k]) n++; return n; }
function fltTypeList() { var a = []; for (var k in FLT.types) if (FLT.types[k]) a.push(k); return a; }
function filterParams(p) {   // p: object of query params to mutate
    if (FLT.vis !== "all") p.kind = FLT.vis;
    if (fltTypesCount()) p.types = fltTypeList().join(",");
    if (FLT.sort === "oldest") p.sort = "oldest";
    return p;
}
function typeKey(t) { var ty = txType(t); return /^[0-9a-f]{40,}$/i.test(ty) ? "program" : ty; }
function filterMatches(t) {
    if (FLT.vis === "public" && txVis(t) !== "public") return false;
    if (FLT.vis === "private" && txVis(t) !== "private") return false;
    if (FLT.vis === "raw" && txVis(t) !== "raw") return false;
    if (fltTypesCount() && !FLT.types[typeKey(t)]) return false;
    return true;
}
function clockOk(t) { return !!FLT.types["clock"] || progName(t.program) !== "clock"; }
function fltSort() { return FLT.sort === "oldest" ? "oldest" : "newest"; }
// A stable signature of the CURRENT filter, including sort. FLT lives in this .pragma library,
// so it is engine-wide: a page kept alive in the router's cache can be re-shown after the
// filter changed elsewhere, holding rows fetched under the old one. Pages record this at fetch
// time and compare on re-show.
function fltSig() {
    var p = {}; filterParams(p);
    var parts = []; for (var k in p) parts.push(k + "=" + p[k]);
    parts.sort();
    return parts.join("&") + "|" + fltSort();
}
// Dedupe/identity key for a feed row. A hash is NOT unique across zones - identical genesis
// transactions repeat verbatim - so keying `seen` on the hash alone silently dropped every
// zone's copy but the first. The server's own cursor includes before_channel for the same
// reason. Local rows carry the pseudo-zone, which keeps them distinct from a remote row.
function rowKey(t) { return String(t.channel || "") + ":" + String(t.hash || ""); }

// ── risc0 word decoders (ported verbatim) ────────────────────────────────────
function u128le(w, off) { var v = BigInt(0); for (var i = 0; i < 4; i++) v += BigInt((w[off + i] || 0) >>> 0) << BigInt(32 * i); return v; }
function u64le(w, off) { return BigInt((w[off] || 0) >>> 0) | (BigInt((w[off + 1] || 0) >>> 0) << BigInt(32)); }
// risc0 String = [len:u32][ceil(len/4) words of utf8, LE-packed per word]
function r0str(w, off) {
    var len = (w[off] || 0) >>> 0, nw = Math.ceil(len / 4), b = [];
    for (var i = 0; i < nw; i++) { var x = (w[off + 1 + i] || 0) >>> 0; for (var k = 0; k < 4; k++) b.push((x >>> (8 * k)) & 0xff); }
    return utf8Decode(b.slice(0, len));
}
function r0strWords(w, off) { return 1 + Math.ceil(((w[off] || 0) >>> 0) / 4); }
// UTF-8 decode (QML V4 has no TextDecoder).
function utf8Decode(bytes) {
    var out = "", i = 0, n = bytes.length;
    while (i < n) {
        var c = bytes[i++] & 0xff, cp;
        if (c < 0x80) cp = c;
        else if (c < 0xE0) cp = ((c & 0x1f) << 6) | (bytes[i++] & 0x3f);
        else if (c < 0xF0) cp = ((c & 0x0f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f);
        else { cp = ((c & 0x07) << 18) | ((bytes[i++] & 0x3f) << 12) | ((bytes[i++] & 0x3f) << 6) | (bytes[i++] & 0x3f); }
        try { out += String.fromCodePoint(cp); } catch (e) { out += "�"; }
    }
    return out;
}
// deployer-schema (ABI) walk. Returns {v, p}.
function r0dec(w, t, p) {
    if (typeof t === "string") {
        if (t === "u8" || t === "u16" || t === "u32") return { v: (w[p] || 0) >>> 0, p: p + 1 };
        if (t === "bool") return { v: !!w[p], p: p + 1 };
        if (t === "u64") return { v: u64le(w, p).toString(), p: p + 2 };
        if (t === "u128") return { v: u128le(w, p).toString(), p: p + 4 };
        if (t === "string") return { v: r0str(w, p), p: p + r0strWords(w, p) };
        if (t === "bytes") { var n = (w[p] || 0) >>> 0, b = w.slice(p + 1, p + 1 + n); return { v: bytesDisp(b), p: p + 1 + n }; }
        return { v: "?" + t, p: p + 1 };
    }
    if (t && t.vec) { var nn = (w[p] || 0) >>> 0, q = p + 1, a = []; for (var i = 0; i < nn && q <= w.length; i++) { var r = r0dec(w, t.vec, q); a.push(r.v); q = r.p; } return { v: a, p: q }; }
    if (t && t.array) { var et = t.array[0], an = t.array[1] | 0, q2 = p, a2 = []; for (var j = 0; j < an; j++) { var r2 = r0dec(w, et, q2); a2.push(r2.v); q2 = r2.p; } return { v: a2, p: q2 }; }
    if (t && t.struct) { var q3 = p, o = {}; for (var si = 0; si < t.struct.length; si++) { var f = t.struct[si]; var r3 = r0dec(w, f.type, q3); o[f.name] = r3.v; q3 = r3.p; } return { v: o, p: q3 }; }
    if (t && t.enum) { var vi = (w[p] || 0) >>> 0, vd = t.enum[vi], q4 = p + 1; if (!vd) return { v: "variant " + vi, p: q4 }; var o2 = { _variant: vd.name }; var flds = vd.fields || []; for (var fi = 0; fi < flds.length; fi++) { var r4 = r0dec(w, flds[fi].type, q4); o2[flds[fi].name] = r4.v; q4 = r4.p; } return { v: o2, p: q4 }; }
    return { v: null, p: p + 1 };
}
function bytesDisp(b) {
    var ok = b.length && b.every(function (x) { return x >= 9 && x <= 126; });
    if (ok) return b.map(function (x) { return String.fromCharCode(x); }).join("");
    return "0x" + b.map(function (x) { return ((x >>> 0) & 0xff).toString(16); }).map(function (h) { return h.length < 2 ? "0" + h : h; }).join("");
}
function fmtSchema(v) {
    if (v === null || v === undefined) return "";
    if (Array.isArray(v)) return "[" + v.map(fmtSchema).join(", ") + "]";
    if (typeof v === "object") {
        var head = v._variant ? "<b>" + esc(v._variant) + "</b>" : "", ps = [];
        for (var k in v) { if (k === "_variant") continue; ps.push('<span style="color:' + pal.muted + '">' + esc(k) + ':</span> ' + fmtSchema(v[k])); }
        return head + (ps.length ? (head ? " {" : "{") + " " + ps.join(", ") + " }" : "");
    }
    return "<b>" + esc(String(v)) + "</b>";
}
function decodeBySchema(w, schema) { try { return fmtSchema(r0dec(w, schema, 0).v); } catch (e) { return null; } }

// ── instrText: the rich instruction line (ported verbatim) ───────────────────
// tok (optional) = resolved token_of for the holding account (token standard).
function instrText(t, tok) {
    var w = t.instruction_data || []; if (!w.length) return "";
    if (t.program && SCHEMAS[t.program]) { var d = decodeBySchema(w, SCHEMAS[t.program]); if (d) return d; }
    var name = PROGS[t.program] || t.program, a = t.accounts || [];
    var acc = function (i) { return a[i] ? '<a href="wallet:' + u(t.channel) + ':' + u(a[i]) + '" style="color:' + pal.link + '">' + esc(sh(a[i], 6, 4)) + "</a>" : ""; };
    var ft = function () { return (a[0] ? " · from " + acc(0) : "") + (a[1] ? " → to " + acc(1) : ""); };
    if (name === "token" && w.length >= 1) {
        var v = w[0] >>> 0;
        var tn = ["Transfer","NewFungibleDefinition","NewDefinitionWithMetadata","InitializeAccount","Burn","Mint","PrintNft"][v];
        if (v === 0 && w.length >= 5) {
            var tk = "token-standard";
            if (tok && tok.resolved && tok.definition) { var lbl = tok.name || sh(tok.definition, 6, 4); tk = '<a href="token:' + u(t.channel) + ':' + u(tok.definition) + '" style="color:' + pal.link + '">' + esc(lbl) + "</a>"; }
            return "<b>Transfer</b> <b>" + grp(u128le(w, 1).toString()) + "</b> " + tk + ft();
        }
        if (v === 1) { var nm = r0str(w, 1), sup = u128le(w, 1 + r0strWords(w, 1)); return "<b>NewFungibleDefinition</b> - <b>" + esc(nm) + "</b> · supply " + grp(sup.toString()); }
        if (v === 3) return "<b>InitializeAccount</b>";
        return "<b>" + esc(tn || ("variant " + v)) + "</b> " + rawWords(w, 1, 17);
    }
    if (name === "authenticated_transfer") {
        var av = w[0] >>> 0;
        if (w.length === 5 && av === 0) return "<b>Transfer</b> <b>" + grp(u128le(w, 1).toString()) + '</b> <b>LEZ</b> <span style="color:' + pal.muted + ';font-size:11px">(native)</span>' + ft();
        if (w.length === 1 && av === 1) return "<b>Register</b> - create native account" + (a[0] ? " · " + acc(0) : "");
        if (w.length >= 4) {
            var amt = u128le(w, 0);
            if (amt === BigInt(0)) return "<b>Register</b> - initialize native account" + (a[0] ? " · " + acc(0) : "");
            return "<b>Transfer</b> <b>" + grp(amt.toString()) + '</b> <b>LEZ</b> <span style="color:' + pal.muted + ';font-size:11px">(native)</span>' + ft();
        }
    }
    if (name === "clock" && w.length >= 2) {
        var ts = u64le(w, 0), dd = "";
        try { var ms = Number(ts); if (ms > 1e12 && ms < 4e12) dd = " (" + new Date(ms).toISOString().replace("T", " ").slice(0, 19) + "Z)"; } catch (e) {}
        return "<b>Tick</b> - timestamp " + ts.toString() + dd;
    }
    if (name === "pinata" && w.length >= 4) return "<b>Claim</b> - PoW solution " + u128le(w, 0).toString();
    if (name === "amm" && w.length >= 1) {
        var vn = ["NewDefinition","AddLiquidity","RemoveLiquidity"][w[0] >>> 0] || ("variant " + (w[0] >>> 0));
        return "<b>" + esc(vn) + "</b> " + rawWords(w, 1, 17);
    }
    if (name === "ata" && w.length >= 1) {
        var iv = w[0] >>> 0;
        if (iv === 0) return "<b>Create</b> - associated token account" + ft();
        if (iv === 1 && w.length >= 13) return "<b>Transfer</b> <b>" + grp(u128le(w, 9).toString()) + '</b> <span style="color:' + pal.muted + '">via ATA</span>' + ft();
        if (iv === 2 && w.length >= 13) return "<b>Burn</b> <b>" + grp(u128le(w, 9).toString()) + '</b> <span style="color:' + pal.muted + '">via ATA</span>' + ft();
        return "<b>" + (["Create","Transfer","Burn"][iv] || ("variant " + iv)) + "</b> " + rawWords(w, 1, 17);
    }
    // ---- no registered schema: a clearly-TENTATIVE best-effort decode ----
    var raw = rawWords(w, 0, 20);
    var tag = htag("tentative", "best-effort guess - no instruction schema is registered for this program; add one to decode exactly");
    if (isRawId(t.program)) {
        var def = r0def(w);
        if (def) return tag + "<b>NewFungibleDefinition</b> - <b><span style=\"color:" + pal.muted + ";font-style:italic\">≈ " + esc(def.name) + "</span></b> · supply " + grp(def.supply);
        if (w.length === 5 && (w[0] >>> 0) <= 15 && !(w[3] || w[4]) && ((w[1] | w[2]) >>> 0)) {
            var amt2 = u64le(w, 1);
            var tg = t.token_guess ? '<span style="color:' + pal.muted + ';font-style:italic">≈ ' + esc(t.token_guess) + "</span>" : '<span style="color:' + pal.muted + '">token/program unresolved</span>';
            return tag + "<b>Transfer</b> <b>" + grp(amt2.toString()) + "</b> " + tg + ' <span style="color:' + pal.muted + ';font-size:11px">· value-transfer shape · variant ' + (w[0] >>> 0) + "</span>" + ft();
        }
    }
    var str = asAsciiInstr(w);
    if (str) return tag + "<b>&ldquo;" + esc(str) + "&rdquo;</b> <span style=\"color:" + pal.muted + ";font-size:11px\">· string · " + w.length + " words</span>";
    for (var i = 0; i + 1 < w.length; i++) {
        var vv = BigInt(w[i] >>> 0) + (BigInt(w[i + 1] >>> 0) << BigInt(32));
        if (vv >= BigInt(1500000000000) && vv <= BigInt(2500000000000)) {
            var ds = vv.toString(); try { ds = new Date(Number(vv)).toISOString().replace("T", " ").slice(0, 19) + "Z"; } catch (e) {}
            var bt = (t.timestamp && vv === BigInt(t.timestamp)) ? ' <span style="color:' + pal.muted + '">· = block time</span>' : "";
            var pos = i ? ' <span style="color:' + pal.muted + '">(words ' + i + "-" + (i + 1) + ")</span>" : "";
            return tag + "<b>u64</b> " + esc(ds) + ' <span style="color:' + pal.muted + '">timestamp</span>' + bt + pos + " " + raw;
        }
    }
    var v0 = w.length ? "<b>variant " + (w[0] >>> 0) + "</b> · " : "";
    return v0 + '<span style="color:' + pal.muted + '">' + w.length + " u32 word" + (w.length === 1 ? "" : "s") + " · no schema</span> " + raw;
}
function rawWords(w, from, to) {
    var slice = w.slice(from, to);
    return '<span style="color:' + pal.muted + ';font-size:11px">[' + slice.join(", ") + (w.length > to ? ", …" : "") + "]</span>";
}
function htag(text, title) {
    return '<span style="color:' + pal.htagFg + ';background-color:' + pal.htagBg + '">&nbsp;' + esc(text) + "&nbsp;</span> ";
}
function asAsciiInstr(w) {
    if (!w || !w.length) return null;
    var b = w;
    if (w.length > 1 && w[0] === w.length - 1) b = w.slice(1);
    if (!b.length || b.length > 512) return null;
    if (!b.every(function (x) { return (x >= 32 && x <= 126) || x === 9 || x === 10 || x === 13; })) return null;
    var s = b.map(function (x) { return String.fromCharCode(x); }).join("");
    return s.trim().length >= 2 ? s : null;
}
// NewFungibleDefinition-shaped instruction on an unnamed program.
function r0def(w) {
    if (!w || w.length < 7 || (w[0] >>> 0) !== 1) return null;
    var len = (w[1] || 0) >>> 0; if (!len || len > 64) return null;
    var nw = Math.ceil(len / 4); if (2 + nw + 4 !== w.length) return null;
    var name = r0str(w, 1); if (!name || name.length !== len || !/^[\x20-\x7e]+$/.test(name)) return null;
    var r = w.slice(2 + nw); if (((r[2] | r[3]) >>> 0) !== 0 || !((r[0] | r[1]) >>> 0)) return null;
    return { name: name, supply: (BigInt(r[0] >>> 0) | (BigInt(r[1] >>> 0) << BigInt(32))).toString() };
}

// ── corpus-inferred field layout ─────────────────────────────────────────────
function b58(bytes) {
    var A = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    var n = BigInt(0); for (var i = 0; i < bytes.length; i++) n = n * BigInt(256) + BigInt(bytes[i] >>> 0);
    var s = ""; while (n > BigInt(0)) { s = A[Number(n % BigInt(58))] + s; n /= BigInt(58); }
    for (var j = 0; j < bytes.length; j++) { if ((bytes[j] >>> 0) === 0) s = "1" + s; else break; }
    return s || "1";
}
function leInt(w, off, len) { var n = BigInt(0); for (var k = 0; k < len; k++) n += BigInt(w[off + k] >>> 0) << (BigInt(8) * BigInt(k)); return n; }
function hexOf(w, off, len) { return w.slice(off, off + len).map(function (x) { var h = (x >>> 0).toString(16); return h.length < 2 ? "0" + h : h; }).join(""); }
function inferLayout(samples) {
    samples = (samples || []).filter(function (w) { return w && w.length && w.every(function (x) { return (x >>> 0) <= 255; }); });
    if (samples.length < 6) return null;
    var byV = {}; samples.forEach(function (w) { var v = w[0] >>> 0; (byV[v] = byV[v] || []).push(w); });
    var variants = {};
    for (var vk in byV) {
        var g = byV[vk], lc = {}; g.forEach(function (w) { lc[w.length] = (lc[w.length] || 0) + 1; });
        var len = +Object.keys(lc).sort(function (a, b) { return lc[b] - lc[a]; })[0];
        var gg = g.filter(function (w) { return w.length === len; }); if (gg.length < 5 || len < 2 || len > 1024) continue;
        var cst = [], hi = [];
        for (var p = 0; p < len; p++) { var set = {}; gg.forEach(function (w) { set[w[p] >>> 0] = 1; }); var ks = Object.keys(set); cst.push(ks.length === 1 ? +ks[0] : null); hi.push(ks.length >= 8); }
        var fields = [{ kind: "tag", off: 0, len: 1 }]; var i = 1;
        while (i < len) {
            if (cst[i] !== null) { var jc = i; while (jc < len && cst[jc] !== null) jc++; fields.push({ kind: "fixed", off: i, len: jc - i }); i = jc; continue; }
            var j = i; while (j < len && cst[j] === null) j++;
            var bS = -1, bL = 0, cs = 0;
            for (var kk = i; kk <= j; kk++) { if (kk < j && hi[kk]) cs++; else { if (cs > bL) { bL = cs; bS = kk - cs; } cs = 0; } }
            if (bL >= 32) {
                var idL = bL >= 64 ? 64 : 32;
                if (bS > i) fields.push({ kind: (bS - i) <= 4 ? "u32" : (bS - i) <= 8 ? "u64" : (bS - i) <= 16 ? "u128" : "bytes", off: i, len: bS - i });
                fields.push({ kind: "id" + idL, off: bS, len: idL });
                var tS = bS + idL; if (tS < j) fields.push({ kind: (j - tS) <= 8 ? "u64" : "bytes", off: tS, len: j - tS });
            } else { var L = j - i; fields.push({ kind: L === 4 ? "u32" : L === 8 ? "u64" : L === 16 ? "u128" : "bytes", off: i, len: L }); }
            i = j;
        }
        variants[vk] = { samples: gg.length, len: len, fields: fields };
    }
    return Object.keys(variants).length ? { variants: variants } : null;
}
function renderByLayout(w, layout, t) {
    var v = w.length ? (w[0] >>> 0) : -1, vl = layout && layout.variants[v];
    if (!vl || w.length !== vl.len) return null;
    var acc = {}; (t.accounts || []).forEach(function (x) { acc[x] = 1; });
    var parts = vl.fields.map(function (f) {
        if (f.kind === "tag") return "<b>variant " + v + "</b>";
        if (f.kind === "fixed") return '<span style="color:' + pal.muted + '">fixed[' + f.len + "]</span>";
        if (f.kind === "u32" || f.kind === "u64" || f.kind === "u128") return "<b>" + leInt(w, f.off, f.len).toString() + '</b> <span style="color:' + pal.muted + '">' + f.kind + "</span>";
        if (f.kind === "id32" || f.kind === "id64") {
            var id = b58(w.slice(f.off, f.off + f.len)), known = acc[id];
            var lbl = known ? '<a href="wallet:' + u(t.channel) + ':' + u(id) + '" style="color:' + pal.link + '">' + esc(sh(id, 6, 4)) + "</a>" : esc(sh(id, 8, 6));
            return "<b>id</b> " + lbl + ' <span style="color:' + pal.muted + '">' + f.len + "B" + (known ? " · account" : "") + "</span>";
        }
        return '<span style="color:' + pal.muted + '">bytes[' + f.len + ']</span> <span style="font-size:11px">' + hexOf(w, f.off, f.len) + "</span>";
    });
    return htag("inferred", "layout inferred from this program's instruction corpus - tentative") + parts.join(' <span style="color:' + pal.muted + '">·</span> ') + ' <span style="color:' + pal.muted + ';font-size:11px">· ' + vl.samples + " samples</span>";
}

// ── zone badges / labels / metrics ───────────────────────────────────────────
function dataBadge(s) { return !!(s && s.data_channel); }
function zoneTitle(s) { return aliasOf(s.channel) || s.channel_short || sh(s.channel); }
function l2Tip(s) { return (s && s.latest_block_id > 0) ? "#" + num(s.latest_block_id) : (s && s.activity_state ? "-" : "#0"); }
function bpmStr(s) {
    var v = s && s.blocks_per_min;
    return (v != null && isFinite(v)) ? ((v >= 10 ? num(Math.round(v)) : v.toFixed(1)) + " blk/min") : "";
}
function txMixStr(s) {
    var m = s && s.tx_mix; if (!m) return ""; var p = [];
    if (m.public) p.push(num(m.public) + " pub"); if (m.private) p.push(num(m.private) + " priv");
    if (m.deploy) p.push(num(m.deploy) + " deploy"); return p.join(" · ");
}
// consBadge → { text, ok, title } | null
function consBadge(s) {
    var c = s.consistency || {};
    var skew = c.checked > 0 && c.hash_failures === c.checked;
    var gaps = c.id_gaps || 0;
    if (s.consistent === true) {
        var notes = []; if (skew) notes.push("hash recompute n/a (version skew)"); if (gaps) notes.push(gaps + " id-gap" + (gaps > 1 ? "s" : ""));
        var title = "chain links verified over " + (c.checked || 0) + " blocks" + (notes.length ? " - " + notes.join(", ") : "");
        return { ok: true, text: "✓ " + (notes.length ? "links ok" : "verified") + (gaps ? " · " + gaps + " gap" + (gaps > 1 ? "s" : "") : ""), title: title };
    }
    if (s.consistent === false) {
        var why = []; if (c.chain_breaks) why.push(c.chain_breaks + " chain break" + (c.chain_breaks > 1 ? "s" : "")); if (c.hash_failures && !skew) why.push(c.hash_failures + " hash mismatch");
        return { ok: false, text: "⚠ inconsistent", title: why.join(", ") || "inconsistent" };
    }
    return null;
}
function chainCheckText(s) {
    var c = s.consistency || {};
    if (s.consistent == null) return "not verified yet";
    var skew = c.checked > 0 && c.hash_failures === c.checked;
    if (s.consistent === false) { var why = []; if (c.chain_breaks) why.push(c.chain_breaks + " chain break(s)"); if (c.hash_failures && !skew) why.push(c.hash_failures + " hash mismatch(es)"); return "INCONSISTENT - " + (why.join(", ") || "see details"); }
    var t = "links verified over " + (c.checked || 0) + " blocks"; var notes = [];
    if (skew) notes.push("hash recompute unavailable - explorer/sequencer common version differ");
    if (c.id_gaps) notes.push(c.id_gaps + " id-gap(s): missed or not-yet-settled block(s)");
    if (notes.length) t += " (" + notes.join("; ") + ")";
    return t;
}
// settleBadge → { text, ok, bg, fg, title } | null
//
// `settling` is published per sequencer and has THREE states, which is why a plain boolean
// cannot carry it: true = inscribing its blocks onto the L1 right now, false = known not to be,
// null/absent = unknown (typically a channel that is not live). The port never rendered this
// field at all, so a zone that had stopped settling looked identical to one that was.
function settleBadge(s) {
    if (!s || s.settling === undefined || s.settling === null) return null;
    var last = s.settled_slot ? (" · last settled L1 slot " + num(s.settled_slot)) : "";
    if (s.settling)
        return { text: "settling", ok: true, bg: finBadge.fin.bg, fg: finBadge.fin.fg,
                 title: "inscribing blocks onto the L1" + last };
    return { text: "not settling", ok: false, bg: pal.nosettleBg, fg: pal.nosettleFg,
             title: "not inscribing onto the L1 at the moment" + last };
}
// Long form for the zone page's detail grid.
function settleText(s) {
    if (!s || s.settling === undefined || s.settling === null) return "unknown";
    var last = s.settled_slot ? (" · last settled L1 slot " + num(s.settled_slot)) : "";
    return (s.settling ? "yes - inscribing onto the L1" : "no - not inscribing right now") + last;
}
function tipNote(s) {
    if (s.seq_tip == null) return "";
    if (s.seq_tip < s.latest_block_id) return " · seq tip #" + num(s.seq_tip) + " < L1 #" + num(s.latest_block_id) + " ⚠";
    return " · seq tip #" + num(s.seq_tip) + " (L1 #" + num(s.latest_block_id) + ")";
}
// activityChip → { text, tier, title } | null   (tier ∈ fin/safe/pend used for color)
function activityChip(s) {
    var st = s && s.activity_state; if (!st) return null;
    var m = { finalizing: ["safe", "finalizing", "on-L1 inscriptions awaiting finality"],
              "clock-only": ["pend", "clock-only", "idle - clock heartbeats only"],
              raw: ["safe", "raw", "raw text/data inscriptions (not sequencer blocks) - shown as rows"] }[st];
    if (!m) return null;
    return { tier: m[0], text: m[1], title: m[2] };
}

// ── finality (three tiers) ───────────────────────────────────────────────────
function seqFinal(ch) { var q = findSeq(ch); return q ? (q.finalized_block_id || 0) : 0; }
function seqSafe(ch) { var q = findSeq(ch); return q ? Math.max(q.safe_block_id || 0, q.finalized_block_id || 0) : 0; }
function findSeq(ch) { var s = (state && state.sequencers) || []; for (var i = 0; i < s.length; i++) if (s[i].channel === ch) return s[i]; return null; }
// finTier(t) -> 'fin'|'safe'|'pend'|null  (drives the finality badge color/label)
function finTier(t) {
    if (t.kind === "raw") { var lib = (state && state.l1 && state.l1.lib_slot) || 0, sl = t.slot || 0; if (!sl) return null; return (lib && sl <= lib) ? "fin" : "safe"; }
    var fin = seqFinal(t.channel), safe = seqSafe(t.channel);
    if (!fin && !safe) return null;
    if (t.block_id <= fin) return "fin";
    if (t.block_id <= safe) return "safe";
    return "pend";
}

// ── local zone: a sequencer on the user's own machine ────────────────────────
// Ported from the web dashboard, minus its transport workaround. A browser must use a
// WebSocket because a cross-origin HTTP POST to loopback is blocked; a desktop module has no
// same-origin policy, so it speaks plain JSON-RPC over HTTP and skips all of that.
var LOCAL_ZONE = "localhost";
var LOCAL_DEFAULT_URL = "http://127.0.0.1:3070";
var LOCAL_MIN_TXS = 25;      // keep reading until this many real (non-clock) txs are in hand
var LOCAL_FIRST_BATCH = 150; // small first read so the newest rows land quickly
var LOCAL_BATCH = 2000;      // then go wide (the decode endpoint caps a request at 2048)
var LOCAL_MAX_BLOCKS = 20000;

// A block's transaction count without decoding it. Borsh lays the header out at a fixed size
// (block_id u64, two 32-byte hashes, timestamp u64, 64-byte signature = 144 bytes) and the
// body's Vec length follows as a u32 LE at byte 144. So the first ~148 bytes answer "could
// this block hold anything but a clock tick?", which decides whether it is worth uploading.
// Returns null when the prefix cannot be read, and callers treat null as "send it".
function blockTxCount(b64) {
    try {
        var head = b64.length > 200 ? b64.slice(0, 200) : b64;
        var bin = atobPoly(head);
        if (bin.length < 148) return null;
        return ((bin.charCodeAt(144)) | (bin.charCodeAt(145) << 8) |
                (bin.charCodeAt(146) << 16) | (bin.charCodeAt(147) << 24)) >>> 0;
    } catch (e) { return null; }
}

// Whether skipping single-transaction blocks is SAFE on this chain, established by observation
// rather than assumption, against a batch that was uploaded in full:
//   1. the header offset really does yield each block's transaction count on this build;
//   2. every block carries exactly one clock tick, so tx_count == 1 means clock-only.
// A chain without a per-block clock, or a build whose header differs, fails this and keeps
// uploading everything. Getting it wrong would silently hide transactions.
function clockOnlyIsSkippable(sentB64, decoded) {
    if (!sentB64.length || sentB64.length !== decoded.length) return false;
    for (var i = 0; i < decoded.length; i++) {
        var txs = decoded[i].txs || [];
        if (blockTxCount(sentB64[i]) !== txs.length) return false;
        var clocks = 0;
        for (var j = 0; j < txs.length; j++) if (progName(txs[j].program) === "clock") clocks++;
        if (clocks !== 1) return false;
    }
    return true;
}

// Re-tag decoded blocks onto the pseudo-zone so every existing renderer links under it.
function localTag(blocks, chan) {
    var out = [];
    for (var i = 0; i < blocks.length; i++) {
        var b = blocks[i], txs = b.txs || [];
        for (var j = 0; j < txs.length; j++) {
            var t = {};
            for (var k in txs[j]) t[k] = txs[j][k];
            t.block_id = b.block_id; t.timestamp = b.timestamp;
            t.channel = LOCAL_ZONE; t.channel_short = "local"; t.local_channel = chan;
            out.push(t);
        }
    }
    return out;
}

// base64 -> binary string. QML's JS engine has no atob(), so decode explicitly.
function atobPoly(b64) {
    var AL = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    var out = "", acc = 0, bits = 0;
    for (var i = 0; i < b64.length; i++) {
        var c = b64.charAt(i);
        if (c === "=" || c === "\n" || c === "\r" || c === " " || c === "\t") continue;
        var v = AL.indexOf(c);
        if (v < 0) return "";
        acc = (acc << 6) | v; bits += 6;
        if (bits >= 8) { bits -= 8; out += String.fromCharCode((acc >> bits) & 0xff); }
    }
    return out;
}

// Tooltip for the finality badge. The "finalizing" tier is the one that needs a duration,
// and it comes from finalityEta(): measured, or the lag in slots when the rate has not been
// observed long enough to state one. The web dashboard used to assert a hardcoded "~1h" here.
function finTip(t) {
    var k = finTier(t);
    if (k === "fin") return "final - irreversibly settled on the L1";
    if (k === "safe") return "inscribed on the L1 and finalizing (irreversible once past the L1's last-final slot - " + finalityEta() + ")";
    if (k === "pend") return "pending - not yet observed inscribed on the L1";
    return "";
}

// ── txAction: one-line human action (ported verbatim) ────────────────────────
// A 32-byte value written in hex is the SAME key an account id spells in base58, so a public
// key pasted in hex has to be offered as an account. Returns "" for anything that is not 64
// hex chars. Ported from the web dashboard.
function hexToB58(h) {
    if (!/^[0-9a-f]{64}$/.test(h)) return "";
    var AL = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
    var n = BigInt("0x" + h), out = "";
    while (n > BigInt(0)) { out = AL[Number(n % BigInt(58))] + out; n = n / BigInt(58); }
    for (var i = 0; i + 1 < h.length && h[i] === "0" && h[i + 1] === "0"; i += 2) out = "1" + out;
    return out || "1";
}

// MEASURED seconds-to-finality: lag in slots x observed seconds-per-slot, published by the
// server as l1.finality_eta_secs. When the server has not observed the rate long enough to
// trust it the field is absent, and the lag is stated in slots rather than inventing a
// duration. Ported from the web dashboard, which replaced a hardcoded "~1h".
function dur(s) {
    s = Number(s) || 0;
    if (s < 90) return s + " secs";
    if (s < 5400) return Math.round(s / 60) + " mins";
    return (s / 3600).toFixed(1) + " hrs";
}
function finalityEta() {
    var l1 = (state && state.l1) || {};
    if (l1.finality_eta_secs !== undefined && l1.finality_eta_secs !== null) return "about " + dur(l1.finality_eta_secs);
    if (l1.finality_lag !== undefined && l1.finality_lag !== null) return num(l1.finality_lag) + " slots behind";
    return "lag unknown";
}

function accShort(a) { return a ? esc(sh(a, 6, 4)) : "?"; }
function txAction(t) {
    var w = t.instruction_data || [], a = t.accounts || [], name = progName(t.program), tok = t.token, amt = t.amount;
    var amtS = amt != null ? grp(amt) : "";
    var ft = (a[0] ? " from " + accShort(a[0]) : "") + (a[1] ? " to " + accShort(a[1]) : "");
    if (t.kind === "raw") {
        if (t.raw_type === "cid_pin" && t.raw_title) return "Pinned · " + esc(t.raw_title);
        return "Raw inscription" + (t.slot ? " · L1 slot " + num(t.slot) : "");
    }
    if (t.kind === "deploy") return "Deploy program" + (t.deploy_program ? " " + esc(progShort(t.deploy_program)) : "");
    if (t.kind === "private") { var s = t.subtype; if (s === "shield") return "Shield (private deposit)"; if (s === "deshield") return "Deshield (private withdraw)"; return "Private transfer"; }
    if (name === "ata") { var v = w[0] >>> 0;
        if (v === 0) return "Create " + (tok ? esc(tok) + " " : "") + "token account" + (a[0] ? " for " + accShort(a[0]) : "");
        if (v === 1) return "Transfer " + (amtS ? amtS + " " : "") + (tok ? esc(tok) + " " : "") + "via ATA" + ft;
        if (v === 2) return "Burn " + (amtS ? amtS + " " : "") + (tok ? esc(tok) + " " : "") + "via ATA"; }
    if (name === "token") { var tv = w[0] >>> 0;
        if (tv === 0) return "Transfer " + (amtS ? amtS + " " : "") + (tok ? esc(tok) : "tokens") + ft;
        if (tv === 1) return "Create token " + (tok ? esc(tok) : "") + (amtS ? " · supply " + amtS : "");
        if (tv === 3) return "Initialize " + (tok ? esc(tok) + " " : "") + "token account";
        if (tv === 4) return "Burn " + (amtS ? amtS + " " : "") + (tok ? esc(tok) : "tokens");
        if (tv === 5) return "Mint " + (amtS ? amtS + " " : "") + (tok ? esc(tok) : "tokens"); }
    if (name === "authenticated_transfer") {
        // rc5 wraps native in an ENUM: [0, u128] = Transfer (amount at w1, 5 words) and the
        // 1-word [1] = CreateAccount. rc3/rc4 is a BARE u128 (4 words): all-zero = Register,
        // else the amount at w0. Reading u128le(w,0) on the rc5 shape puts the variant word
        // into the low limb, which showed a 1-LEZ transfer as 2^32. Prefer the server-decoded
        // amount (amtS) - it already handles both shapes - and only fall back to local words.
        if (w.length === 1 && (w[0] >>> 0) === 1) return "Register native account" + (a[0] ? " " + accShort(a[0]) : "");
        if (w.length === 4 && u128le(w, 0) === BigInt(0)) return "Register native account" + (a[0] ? " " + accShort(a[0]) : "");
        var na = amt != null ? amtS
            : (w.length === 5 && (w[0] >>> 0) === 0 ? grp(u128le(w, 1).toString())
            : (w.length >= 4 ? grp(u128le(w, 0).toString()) : ""));
        return "Transfer " + (na ? na + " " : "") + "LEZ" + ft; }
    if (name === "pinata") return "Claim native LEZ" + (a[0] ? " to " + accShort(a[0]) : "");
    if (name === "faucet") return ("Faucet dispense " + (tok ? esc(tok) + " " : "") + (a[0] ? "to " + accShort(a[0]) : "")).replace(/ +$/, "");
    if (name === "clock") return "Clock tick";
    if (isRawId(t.program)) {
        var def = r0def(w);
        if (def) return 'New token <span style="color:' + pal.muted + ';font-style:italic">≈ ' + esc(def.name) + "</span> · supply " + grp(def.supply);
        if (amt != null) {
            var tg = t.token_guess ? ' <span style="color:' + pal.muted + ';font-style:italic">≈ ' + esc(t.token_guess) + "</span>" : ' <span style="color:' + pal.muted + '">(token unresolved)</span>';
            return "Transfer " + amtS + tg + ft;
        }
    }
    var pn = (name && !/^[0-9a-f]{40,}$/i.test(name)) ? name.replace(/_/g, " ") : progShort(t.program);
    return esc(cap(pn || "program")) + (w.length ? " · variant " + (w[0] >>> 0) : "");
}

// ── sparkline points (finality-lag series [unix,lag]) → polyline for a Canvas ─
function sparkPoints(series, w, h) {
    series = series || []; if (series.length < 2) return null;
    var ys = series.map(function (p) { return p[1]; });
    var mn = Math.min.apply(null, ys), mx = Math.max.apply(null, ys), rng = (mx - mn) || 1, n = series.length;
    var pts = series.map(function (p, i) { return { x: (i / (n - 1)) * (w - 2) + 1, y: h - 1 - ((p[1] - mn) / rng) * (h - 2) }; });
    return { pts: pts, rising: ys[n - 1] > ys[0] };
}
// human byte size (mirrors fmtBytes).
function fmtBytes(n) {
    if (n == null || isNaN(n)) return "-";
    var un = ["B","KB","MB","GB","TB"], i = 0, v = Number(n);
    while (v >= 1024 && i < un.length - 1) { v /= 1024; i++; }
    return (i ? v.toFixed(1) : String(v)) + " " + un[i];
}
// Parse a cid_pin raw inscription into a structured object for the TxPage panel, or
// null if the tx is not a cid_pin record. Mirrors parseCidPin + cidPinPanel data.
function cidPinData(t) {
    if (!t || !t.raw_text) return null;
    var j; try { j = JSON.parse(t.raw_text); } catch (e) { return null; }
    if (!j || typeof j !== "object" || j.type !== "cid_pin") return null;
    var lab = {};
    if (typeof j.label === "string") { try { lab = JSON.parse(j.label) || {}; } catch (e) {} }
    else if (j.label && typeof j.label === "object") { lab = j.label; }
    // http(s) gateway only — never let a config value smuggle a scheme
    var gw = String((state && state.ipfs_gateway) || "https://ipfs.io").replace(/\/+$/, "");
    if (!/^https?:\/\//i.test(gw)) gw = "https://ipfs.io";
    var files = (Array.isArray(lab.files) ? lab.files : []).filter(function (f) { return f && typeof f === "object"; });
    var ts = Number(j.ts), size = Number(lab.totalSize);
    var title = (lab.title && String(lab.title).trim()) || j.cid || "(untitled)";
    var iaId = lab.source === "internet_archive" ? (lab.id || String(j.cid || "").replace(/^ia:/, "")) : null;
    var fileRows = files.map(function (f) {
        var href = gw + "/ipfs/" + u(f.cid || "") + "?filename=" + u(f.name || "");
        return { name: f.name || "?", cidFull: f.cid || "", cidShort: sh(f.cid || "", 12, 8), viewHref: href, dlHref: href + "&download=true" };
    });
    return {
        title: title,
        iaId: iaId,
        iaHref: iaId ? ("https://archive.org/details/" + u(iaId)) : "",
        source: lab.source || "",
        cid: j.cid || "",
        pinnedBy: j.source ? (j.source + (lab.module && lab.module !== j.source ? " · " + lab.module : "")) : "",
        pinnedAtUtc: (isFinite(ts) && ts > 0) ? new Date(ts * 1000).toUTCString() : "",
        pinnedAtAge: (isFinite(ts) && ts > 0) ? fmtAge(ts) : "",
        sizeHuman: isFinite(size) ? fmtBytes(size) : "",
        sizeBytes: isFinite(size) ? num(size) : "",
        files: fileRows,
        gateway: gw,
        gatewayConfigured: !!(state && state.ipfs_gateway)
    };
}
// group a hex string into space-separated byte pairs, 32 bytes/line.
function fmtHex(hx) {
    hx = (hx || "").replace(/[^0-9a-fA-F]/g, ""); var bytes = hx.match(/.{1,2}/g) || [], out = "";
    for (var i = 0; i < bytes.length; i += 32) out += bytes.slice(i, i + 32).join(" ") + "\n";
    return out.replace(/\n$/, "");
}
