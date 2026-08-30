// ZTheme - the observable half of the theme.
//
// theme.js is `.pragma library`: mutating its `pal` object is completely invisible to QML's
// binding engine, so it can hold the palette DATA but cannot drive a repaint (verified: a
// binding on `ZT.pal.bg` never re-evaluates, and neither does a captured-getter mirror).
// This singleton supplies the observability. Every token below is a real QML property with a
// NOTIFY signal, so ~335 binding sites repaint on a flip with no per-file plumbing.
//
// Division of labour:
//   theme.js  owns the LIGHT values for the 26 tokens the web dashboard's :root also has,
//             plus the four badge maps. That 1:1 mirror is the reason the two stay in step.
//   ZTheme    inherits those, adds the ~109 app-side tokens the QML used to hardcode, and
//             is the ONLY thing anything outside this directory reads.
//
// pragma Singleton + theme/qmldir. Never add a `plugin` line to that qmldir: Basecamp's
// RestrictedUrlInterceptor rejects a whole qmldir on /^\s*(optional\s+)?plugin(\s|$)/ and the
// module then reads as "not installed".
pragma Singleton

import QtQuick
import QtCore
import "../theme.js" as ZT

QtObject {
    id: zt

    // ── palettes ────────────────────────────────────────────────────────────────
    // Object.assign, not a copy of the literals: the 26 shared tokens keep exactly one
    // definition, in theme.js, so ZTheme and the HTML producers can never disagree.
    readonly property var lightPal: Object.assign({}, ZT.lightPal, {

        // ── Core ramp - all 15 live in theme.js lightPal; inherited, never redeclared
        //    amber/purple have zero consumers and hold greys. Carried unchanged on purpose.

        // ── Chrome & controls - hardcoded in the QML today; B3 sweeps the literals onto these
        topbarA:         "#f1f1f3",
        topbarB:         "#d9d9de",
        topbarLine:      "#c4c4cc",
        ctrlA:           "#ffffff",
        ctrlB:           "#f1f1f4",
        ctrlSel:         "#ececef",   // hover/selection go LIGHTER than resting in dark, or they read as disabled
        btnA:            "#ffffff",
        btnB:            "#ededf0",
        btnHoverA:       "#ffffff",
        btnHoverB:       "#e4e4e8",
        cardA:           "#ffffff",
        cardB:           "#f6f6f8",
        pheadA:          "#fafafb",
        pheadB:          "#f2f2f4",
        insetHi:         "#ffffff",   // dark becomes a translucent white inset, not a solid

        // ── Hero - already dark by design. heroA/heroB must be LIFTED in dark, never darkened:
        //    #0c0c0e sits two levels off a #0e0e11 page and the banner would merge into it.
        //    The foregrounds are FIXED in both themes - never fold heroFg into a surface token.
        heroLine:        "#000000",
        heroFg:          "#ffffff",
        heroSub:         "#b9b9c1",
        onDark:          "#ffffff",
        heroErrFg:       "#ffd9d2",
        heroBtnBg:       "#22ffffff",
        heroBtnHover:    "#33ffffff",
        heroBtnBd:       "#33ffffff",

        // ── Search & action
        searchBg:        "#ffffff",   // coupled to the search field's fg - flip the pair together
        searchBd:        "#1a1a1e",
        actionA:         "#3a3a40",
        actionB:         "#161618",
        actionHoverA:    "#161618",
        actionHoverB:    "#000000",
        btnBusyA:        "#6a6a70",
        btnBusyB:        "#3a3a3e",
        // ROLE SPLIT, not a duplicate. btnBusyA is the search button's busy gradient and
        // carries a fixed-white label (onDark); primaryBusy is the settings dialog's solid
        // primary button, whose label is ZTheme.panel. Identical in light (both #6a6a70 under
        // white ink), but in dark `panel` is near-black, so that button's busy fill has to go
        // LIGHTER while the search button's goes darker. One token cannot satisfy both.
        primaryBusy:     "#6a6a70",

        // ── Rows, tables, chips
        // shares theadBg's light value by coincidence and means the
        // opposite (sunken, not raised). Separate token; they diverge in dark.
        detailBg:        "#fbfcfe",
        chipBg:          "#f2f5fb",
        chipHover:       "#e8edf6",
        codeBg:          "#eef1f6",
        idleBg:          "#eef0f4",
        verFallbackBg:   "#eef0f4",   // separate role, same light value as idleBg

        // ── Danger / warn / toast
        dangerBg:        "#fef3f2",
        dangerFg:        "#b42318",
        dangerBd:        "#fecdca",
        dangerHoverBg:   "#fee4e2",
        dangerHoverBd:   "#fda29b",
        warnBg:          "#fdece8",
        warnLine:        "#f2cfc7",
        warnFg:          "#8c2d1c",
        warnBd:          "#e0b4a8",
        warnBtnBg:       "#ffffff",
        toastBg:         "#1c1c20",   // the toast is already dark: in dark mode it moves UP, not down
        toastBd:         "#33333a",
        toastFg:         "#e8e8ec",
        toastErrBg:      "#3a1a14",
        toastErrBd:      "#7a3325",
        toastErrFg:      "#ffd9d2",

        // ── Badge tint families - the flat accessors ZBadge and the pages bind to.
        //    The badge MAPS (tyBadge/visBadge/...) carry the same values keyed by tx type;
        //    these exist for the sites that pick a hue directly. Four separate amber/yellow/gold
        //    sets are deliberate - .htag, deshield, raw and vis-raw can share a row.
        bdgEmeraldBg:    "#dcfce7",
        bdgEmeraldFg:    "#166534",
        bdgEmeraldBd:    "#bbf7d0",
        bdgSkyBg:        "#e0f2fe",
        bdgSkyFg:        "#075985",
        bdgSkyBd:        "#bae6fd",
        bdgZincBg:       "#f4f4f5",
        bdgZincFg:       "#71717a",
        bdgZincBd:       "#e4e4e7",
        bdgTealBg:       "#ccfbf1",
        bdgTealFg:       "#0f766e",
        bdgTealBd:       "#99f6e4",
        bdgAmberBg:      "#fef3c7",
        bdgAmberFg:      "#92400e",
        bdgAmberBd:      "#fde68a",
        bdgVioletBg:     "#ede9fe",
        bdgVioletFg:     "#5b21b6",
        bdgVioletBd:     "#ddd6fe",
        bdgIndigoBg:     "#e0e7ff",
        bdgIndigoFg:     "#3730a3",
        bdgIndigoBd:     "#c7d2fe",
        bdgFuchsiaBg:    "#fae8ff",
        bdgFuchsiaFg:    "#86198f",
        bdgFuchsiaBd:    "#f5d0fe",
        bdgRoseBg:       "#ffe4e6",
        bdgRoseFg:       "#9f1239",
        bdgRoseBd:       "#fecdd3",
        bdgOrangeBg:     "#ffedd5",
        bdgOrangeFg:     "#c2410c",
        bdgOrangeBd:     "#fdba74",
        bdgYellowBg:     "#fef9c3",
        bdgYellowFg:     "#854d0e",
        bdgYellowBd:     "#fde68a",
        bdgYellowSoftBg: "#fffbeb",
        bdgYellowSoftFg: "#854d0e",
        bdgYellowSoftBd: "#fde68a",
        bdgGreyBg:       "#f1f1f3",
        bdgGreyFg:       "#52525b",
        bdgGreyBd:       "#e0e0e4",
        bdgFaintBg:      "#f8fafc",   // the guess chip: lowest-contrast chip of the whole family,
        // and it borrows the plain hairline rather than copying it.
        // No bdgFaintFg: the chip inherits its ink (the web sets no colour on .b-ty-guess).
        bdgFaintBd:      ZT.lightPal.line2,
        bdgRedBg:        "#fee2e2",   // unreg: 'cannot settle', deliberately a step past amber's 'degraded'
        bdgRedFg:        "#991b1b",
        bdgSlateBg:      "#eef0f3",   // fbadge.pend, the bottom of the fin > safe > pend severity ladder
        bdgSlateFg:      "#6b7280",
        bdgWhiteBg:      "#ffffff",   // vis-public. #d4d4d8 is ONE DIGIT off line2 (#d4d4da) - do not fold them.
        bdgWhiteFg:      "#18181b",
        bdgWhiteBd:      "#d4d4d8",
        // vis-private. Black MEANS private: the fill and the white text must not
        // change in dark. Only the border gains contrast, or the chip dissolves into
        // the panel and leaves a floating word. A naive screenshot diff will flag this.
        bdgBlackBg:      "#000000",
        bdgBlackFg:      "#ffffff",
        bdgBlackBd:      "#000000",

        // ── Translucent tints - QML ONLY, spelled #AARRGGBB.
        //    Qt's RichText CSS parser cannot read 8-digit hex; an unparseable colour becomes an
        //    invalid QColor and paints BLACK - the bug that already shipped once and turned every
        //    'final' pill into a black box. Never route one of these through an HTML producer.
        //    A .12 wash composites DARKER over a dark panel, so dark roughly doubles the alpha.
        tintGreen:       "#1f13a97b",   // rgba(19,169,123,.12) - alive / settling / fin
        tintGreen14:     "#2413a97b",   // rgba(19,169,123,.14) - fbadge.fin
        tintBlue:        "#1f2563eb",   // rgba(37,99,235,.12)  - fbadge.safe

        // ── App-only
        scrim:           "#66000000",
        // ZoneRow's Qt.rgba(19/255,169/255,123/255,.12): the same light value as tintGreen but a
        // distinct role. It is NOT derived from `green` - the 19,169,123 is the OLD brand green,
        // so B4 authors it fresh rather than 'preserving' it.
        aliveChip:       "#1f13a97b",
    })

    // The authored dark palette. Written out in FULL rather than as an override layer on top
    // of lightPal: an override layer makes a forgotten token silently inherit its light value,
    // and _assertKeys() - which only sees key sets - would pass while a white surface shipped
    // in a dark app. Spelled out, a forgotten token is a MISSING KEY, which is exactly what
    // _assertKeys catches.
    //
    // THE ELEVATION MODEL IS THE SAME ONE LIGHT USES: raised is lighter. The page is the floor
    // (#0e0e11) and the panel sits ON it (#131317); chrome, chips, rows, the hero and every
    // hover/selection state are lifted further. Below the panel there is almost no room left -
    // that is why light differentiates a sub-surface DOWNWARD (a grey block on a white panel)
    // and dark differentiates the same sub-surface UPWARD, by the same perceptual step. Only
    // `detailBg` spends the little room that is left below the panel, because a well has to
    // read as sunken.
    //
    // Two numbers pin the whole thing and neither is a taste call. contrast.py requires every
    // pairing to meet or beat its LIGHT ratio, so fg/panel >= 17.72 caps the panel at
    // Y <= 0.0071 - which is what keeps the panel this close to the floor. And a selected row
    // must both stay >= 1.15 against that panel (or nobody can see it) and hold fg/rowSel >=
    // 16.05; those two close on `fg` = #ffffff and nothing dimmer. Pure white is not
    // enthusiasm, it is the only ink that satisfies both, and it is the exact mirror of light's
    // #18181b on #ffffff.
    readonly property var darkPal: ({

        // ── Core ramp. These 15 are the tokens theme.js and the web dashboard's :root BOTH carry, so
        // they are the ones the parity test compares. Every one is pinned by the WCAG gate
        // (scratchpad/contrast.py): each fg/bg pairing must meet or beat its LIGHT ratio. That
        // single rule is what fixes bg, panel and fg - see the note above darkPal.
        bg:      "#0e0e11",
        panel:   "#131317",
        panel2:  "#1d1d21",
        line:    "#2c2c32",
        line2:   "#33333a",
        fg:      "#ffffff",
        muted:   "#a1a1ab",
        soft:    "#7c7c86",
        link:    "#eaeaf1",
        navy:    "#ffffff",
        silver:  "#4a4a53",                 // the dot's 'off' grey: as far off the panel as light's #c9c9d0 is off white
        green:   "#5cc264",
        amber:   "#7c7c86",                 // dead token, carries soft's value in both themes
        purple:  "#a1a1ab",                 // dead token, carries muted's value in both themes
        red:     "#e5675a",

        // ── Hero, rows and the .htag trio - also declared in theme.js, also mirrored on the web.
        // The hero is the one region light already paints dark, so dark LIFTS it: heroB is
        // 1.25:1 off the page, where a #141419 would have been 1.05:1 and simply merged.
        // rowHover/rowSel are the tightest pair in the palette. Both are lifted off the panel
        // (escalation lightens in dark) but capped by fg/rowHover >= 16.81 and fg/rowSel >=
        // 16.05, which leaves rowSel a window of about 0.0004 in Y. #1a2132 sits in it at
        // 1.154:1 against the panel, so the selected band is actually visible, and keeps
        // light's blue lean (r < g < b) so a selection still reads as a selection.
        heroA:     "#3a3a44",
        heroB:     "#24242b",
        rowHover:  "#1b1d25",
        rowSel:    "#1a2132",
        theadBg:   "#1a1a1f",
        htagFg:    "#fcd34d",
        htagBg:    "#2e2410",
        htagBd:    "#5c4413",

        // ── App-only members of theme.js's lightPal.
        mutedDim:    "#8f8f9a",
        nosettleBg:  "#2e2410",
        nosettleFg:  "#fcd34d",

        // ── Chrome & controls. The topbar carries `navy` text, so it stays dark enough to hold it and
        // the control pills sit ABOVE it. ctrlSel is lighter than ctrlA: a selection that went
        // darker than its resting state would read as disabled.
        topbarA:     "#1c1c21",
        topbarB:     "#131316",
        topbarLine:  "#2b2b31",
        ctrlA:       "#26262c",
        ctrlB:       "#1c1c21",
        ctrlSel:     "#2a2a31",
        btnA:        "#26262c",
        btnB:        "#1b1b20",
        btnHoverA:   "#2e2e35",
        btnHoverB:   "#232329",
        cardA:       "#1b1b1f",
        cardB:       "#151518",
        pheadA:      "#1e1e23",
        pheadB:      "#191a1d",
        insetHi:     "#0dffffff",           // translucent white inset in dark, not a solid

        // ── Hero. LIFTED, not darkened - it is the one surface that must stay lighter than the page,
        // and its foregrounds are FIXED (identical in both themes) because the hero was already
        // dark by design. heroLine stays a DARK hairline as in light: the banner is now lighter
        // than the page below it, so a light line would disappear into both sides.
        heroLine:      "#0c0c0f",
        heroFg:        "#ffffff",           // FIXED - never fold into a surface token
        heroSub:       "#b9b9c1",
        onDark:        "#ffffff",
        heroErrFg:     "#ffd9d2",
        heroBtnBg:     "#22ffffff",
        heroBtnHover:  "#33ffffff",
        heroBtnBd:     "#33ffffff",

        // ── Search & action. searchBg is coupled to the field's `fg` - flip them together or the box is
        // ink on ink. searchBd keeps its ROLE, not its lightness: light outlines the primary input
        // in near-black at 17:1, so dark outlines it at 2.4:1 against the field - well past line2's
        // 1.48, which is what a plain border gets. The action button is lifted like the hero and
        // stays a step above it (it also has to carry itself on /setup's bare page), and its hover
        // lifts again - a CTA that darkened on hover would read as disabled.
        searchBg:      "#131317",
        searchBd:      "#52525d",
        actionA:       "#45454d",
        actionB:       "#232329",
        actionHoverA:  "#55555f",
        actionHoverB:  "#2c2c33",
        btnBusyA:      "#55555d",
        btnBusyB:      "#2c2c31",
        primaryBusy:   "#8e8e99",           // goes LIGHTER (label is `panel`); btnBusyA goes darker (label is onDark)

        // ── Rows, tables, chips. detailBg and theadBg share a light value and mean OPPOSITE things;
        // here they finally diverge - thead rises above the panel, detail sinks below it.
        detailBg:       "#0d0d10",
        chipBg:         "#20222a",
        chipHover:      "#232936",
        codeBg:         "#212127",
        idleBg:         "#232329",
        verFallbackBg:  "#232329",          // separate role, same value as idleBg - as in light

        // ── Danger / warn / toast. The toast is already dark in light, so it moves UP here, not down.
        dangerBg:       "#2e1414",
        dangerFg:       "#f97066",
        dangerBd:       "#5c2220",
        dangerHoverBg:  "#3d1a18",
        dangerHoverBd:  "#7a2e2a",
        warnBg:         "#2a1512",
        warnLine:       "#43201a",
        warnFg:         "#ff9d8a",
        warnBd:         "#5a2a20",
        warnBtnBg:      "#1f1512",
        toastBg:        "#2a2a31",
        toastBd:        "#44444d",
        toastFg:        "#f4f4f5",
        toastErrBg:     "#4a2018",
        toastErrBd:     "#8f3d2c",
        toastErrFg:     "#ffd9d2",

        // ── Badge tint families. Four separate amber/yellow/gold sets on purpose - .htag, deshield, raw
        // and vis-raw can land on the same row and have to stay distinguishable.
        bdgEmeraldBg:     "#10241a",
        bdgEmeraldFg:     "#86efac",
        bdgEmeraldBd:     "#1d4a31",
        bdgSkyBg:         "#0d2233",
        bdgSkyFg:         "#7dd3fc",
        bdgSkyBd:         "#17466b",
        bdgZincBg:        "#232329",
        bdgZincFg:        "#a1a1aa",
        bdgZincBd:        "#3a3a41",
        bdgTealBg:        "#0d2622",
        bdgTealFg:        "#5eead4",
        bdgTealBd:        "#175048",
        bdgAmberBg:       "#2e2410",
        bdgAmberFg:       "#fcd34d",
        bdgAmberBd:       "#5c4413",
        bdgVioletBg:      "#221a3a",
        bdgVioletFg:      "#c4b5fd",
        bdgVioletBd:      "#3f2f74",
        bdgIndigoBg:      "#1a1e3d",
        bdgIndigoFg:      "#a5b4fc",
        bdgIndigoBd:      "#2f3878",
        bdgFuchsiaBg:     "#2e133a",
        bdgFuchsiaFg:     "#f0abfc",
        bdgFuchsiaBd:     "#63207a",
        bdgRoseBg:        "#33121c",
        bdgRoseFg:        "#fda4af",
        bdgRoseBd:        "#6b2233",
        bdgOrangeBg:      "#33210f",
        bdgOrangeFg:      "#fdba74",
        bdgOrangeBd:      "#59380f",
        bdgYellowBg:      "#2b2711",
        bdgYellowFg:      "#fde047",
        bdgYellowBd:      "#5c4413",
        bdgYellowSoftBg:  "#26220f",
        bdgYellowSoftFg:  "#fde047",
        bdgYellowSoftBd:  "#5c4413",
        bdgGreyBg:        "#212126",
        bdgGreyFg:        "#b0b0ba",
        bdgGreyBd:        "#35353b",

        bdgFaintBg:  "#1c1c21",
        bdgFaintBd:  "#33333a",             // MUST equal line2 - _assertDerived() checks it
        bdgRedBg:    "#3a1414",
        bdgRedFg:    "#fca5a5",
        bdgSlateBg:  "#232329",
        bdgSlateFg:  "#9aa0aa",
        bdgWhiteBg:  "#e4e4e8",             // vis-public: pulled off pure white so the pill does not glare
        bdgWhiteFg:  "#18181b",
        bdgWhiteBd:  "#6b6b74",
        bdgBlackBg:  "#000000",             // vis-private: black MEANS private, so fill and text are UNCHANGED;
        bdgBlackFg:  "#ffffff",
        bdgBlackBd:  "#4a4a53",             // only the border gains contrast, or the chip dissolves into the panel

        // ── Translucent tints. A .12 wash composites DARKER over a dark panel, so the alpha roughly
        // doubles (0x1f/0x24 -> 0x33) and the base hue lifts. QML-only, #AARRGGBB: Qt's RichText
        // CSS parser cannot read 8-digit hex and turns one into an invalid QColor, which paints
        // BLACK. Never route one of these through an HTML producer.
        tintGreen:    "#332dc896",
        tintGreen14:  "#332dc896",
        tintBlue:     "#33608cff",

        // ── App-only.
        scrim:      "#a6000000",
        aliveChip:  "#332dc896",            // authored fresh - light's 19,169,123 is the OLD brand green
    })

    // The four badge maps. Light comes straight from theme.js so there is exactly one copy of
    // it; dark is authored below. Two values in the dark maps are DERIVED and nothing in the
    // language enforces that - darkFin.fin.fg === darkPal.green and darkTy.guess.bd ===
    // darkPal.line2 - so _assertDerived() checks them at startup.
    readonly property var lightTy:  ZT.lightTy
    readonly property var lightVis: ZT.lightVis
    readonly property var lightFin: ZT.lightFin
    readonly property var lightVer: ZT.lightVer
    readonly property var darkTy: ({
        // Type badges (.b-ty-*), keyed by tx type - the same hues as the flat bdg* family above.
        // `guess` stays the FAINTEST chip against its panel in both themes (verified numerically),
        // and its bd is line2, checked by _assertDerived rather than copied by hand.
        token:                   { bg:"#10241a", fg:"#86efac", bd:"#1d4a31" },
        authenticated_transfer:  { bg:"#0d2233", fg:"#7dd3fc", bd:"#17466b" },
        clock:                   { bg:"#232329", fg:"#a1a1aa", bd:"#3a3a41" },
        shield:                  { bg:"#0d2622", fg:"#5eead4", bd:"#175048" },
        deshield:                { bg:"#2e2410", fg:"#fcd34d", bd:"#5c4413" },
        private_send:            { bg:"#221a3a", fg:"#c4b5fd", bd:"#3f2f74" },
        ata:                     { bg:"#1a1e3d", fg:"#a5b4fc", bd:"#2f3878" },
        amm:                     { bg:"#2e133a", fg:"#f0abfc", bd:"#63207a" },
        pinata:                  { bg:"#33121c", fg:"#fda4af", bd:"#6b2233" },
        pinata_token:            { bg:"#33121c", fg:"#fda4af", bd:"#6b2233" },
        deploy:                  { bg:"#33210f", fg:"#fdba74", bd:"#59380f" },
        raw:                     { bg:"#2b2711", fg:"#fde047", bd:"#5c4413" },
        other:                   { bg:"#212126", fg:"#b0b0ba", bd:"#35353b" },
        guess:                   { bg:"#1c1c21", fg:"#a1a1ab", bd:"#33333a" },
    })

    readonly property var darkVis: ({
        // Visibility badges - the one non-mechanical mapping in the palette. public stays the light
        // chip; private keeps its black fill and white text and gains only a border. A naive
        // screenshot diff will flag this pair, and it is correct.
        // QUOTED, and they must stay quoted. `public` and `private` are ECMAScript
        // future-reserved words, and Qt 6.9.2's QML-document parser - which is what Basecamp
        // actually runs - rejects them as bare object-literal keys with
        //     ZTheme.qml:405:9: Expected token `}'
        // ...which takes the ENTIRE singleton down ("Type ZTheme unavailable") and with it all
        // 24 importers. Qt 6.11.1 accepts them, so a 6.11 qmllint and a 6.11 offscreen run both
        // pass; only launching the real host finds it. theme.js gets away with the bare form
        // because a .js file goes through a different (permissive) parser. The key STRINGS are
        // unchanged, so nothing that reads visBadge["public"] moves.
        "public":   { bg:"#e4e4e8", fg:"#18181b", bd:"#6b6b74" },
        "private":  { bg:"#000000", fg:"#ffffff", bd:"#4a4a53" },
        "raw":      { bg:"#26220f", fg:"#fde047", bd:"#5c4413" },
    })

    readonly property var darkFin: ({
        // Finality badges. `label` is TEXT, not colour: it is copied verbatim, or the pill would
        // change WORDING on a theme flip. fin.bg/safe.bg are the 8-digit tints, and fin.fg must
        // equal darkPal.green - _assertDerived checks it.
        fin:   { label:"final", bg:"#332dc896", fg:"#5cc264" },
        safe:  { label:"on L1 · finalizing", bg:"#33608cff", fg:"#93c5fd" },
        pend:  { label:"pending", bg:"#232329", fg:"#9aa0aa" },
    })

    readonly property var darkVer: ({
        // LEZ version badges: rc5 indigo / rc4 emerald / rc3 amber / data yellow. Four distinct
        // hues, because a zone list shows several of them at once.
        rc5:   { bg:"#1a1e3d", fg:"#a5b4fc" },
        rc4:   { bg:"#10241a", fg:"#86efac" },
        rc3:   { bg:"#2e2410", fg:"#fcd34d" },
        data:  { bg:"#2b2711", fg:"#fde047" },
    })

    // ── stock-control palette (QPalette roles, app-only) ──────────────────
    // Kept OUT of pal/darkPal on purpose: pal mirrors the website's :root token-for-token, and
    // these are QPalette role names that have no CSS counterpart. They exist because the ~26
    // stock QtQuick.Controls in this app (ScrollBars, ComboBoxes, CheckBoxes, TextFields, the
    // TextArea, BusyIndicators) paint from `palette.*`, not from any token of ours.
    //
    // The LIGHT column is not a design choice - it is the Basic style's own default palette,
    // MEASURED at runtime (Qt 6.11.1, QT_QUICK_CONTROLS_STYLE=Basic) and copied back verbatim,
    // so declaring it changes nothing. That was checked directly: with this block applied, every
    // control's resolved palette is byte-identical to having no block at all.
    //
    // RISK, and it is not ours to close: this only works while the host calls
    // QQuickStyle::setStyle("Basic") (Basecamp MainContainer.cpp:73). Basic and Fusion honour
    // `palette`; Material and Universal largely ignore it. One line changed over there silently
    // un-themes every stock control here, and nothing in this module's CI can see it.
    readonly property var lightCtl: ({
        window:          "#ffffff",   // Popup / ComboBox-popup background
        windowText:      "#26282a",   // CheckBox label; Button border
        base:            "#ffffff",   // CheckBox indicator fill; TextField/TextArea background
        text:            "#353637",   // checkmark; TextField text; ComboBox delegate text
        button:          "#e0e0e0",   // Button / ComboBox background
        buttonText:      "#26282a",   // ComboBox display text AND its border - one role, two jobs
        mid:             "#bdbdbd",   // ScrollBar handle; CheckBox indicator border; popup outline
        midlight:        "#e4e4e4",   // pressed ComboBox delegate
        light:           "#f6f6f6",   // highlighted ComboBox delegate
        dark:            "#353637",   // pressed ScrollBar handle; ComboBox arrow; Popup/ToolTip border; BusyIndicator
        shadow:          "#28282a",   // Popup drop shadow
        highlight:       "#0066ff",   // text selection - IDENTICAL in dark, see below
        highlightedText: "#090909",
        placeholderText: "#88353637",
        brightText:      "#ffffff",
        toolTipBase:     "#ffffff",
        toolTipText:     "#000000",
    })

    // Dark follows the shipped elevation model: a Popup floats ABOVE the page, so it is lighter
    // than the panel, not darker. `highlight` is deliberately unchanged - #0066ff under white
    // text scores 4.83, which BEATS light's own 4.12 (#090909 on #0066ff), so inventing a
    // second blue would only add a colour to maintain. `buttonText` carries the ComboBox's
    // display text and its border on one role: light puts near-black on a light button, so dark
    // puts near-white on a dark one, and both jobs stay legible.
    readonly property var darkCtl: ({
        window:          "#131317",   // = panel
        windowText:      "#ffffff",   // = fg
        base:            "#1d1d21",   // = panel2; a checkbox square must not vanish into the popup
        text:            "#ffffff",
        button:          "#26262c",   // = btnA
        buttonText:      "#ffffff",
        mid:             "#5a5a66",
        midlight:        "#33333a",   // = line2
        light:           "#26262c",   // = ctrlA; the highlighted row LIFTS in dark
        dark:            "#d4d4dc",   // measured, not guessed: the ComboBox arrow and the BusyIndicator
                                      // both sit on `dark`, and light gives them a near-black glyph
                                      // (9.17 / 11.02). #d4d4dc is its own measured value, not an
                                      // alias of any ramp token: it is the DIMMEST glyph that still
                                      // clears both here (10.21 on `button`, 12.58 on `window`).
                                      // Anything dimmer regresses the spinner.
        shadow:          "#000000",
        highlight:       "#0066ff",
        highlightedText: "#ffffff",
        placeholderText: "#88ffffff",
        brightText:      "#131317",
        toolTipBase:     "#26262c",
        toolTipText:     "#ffffff",
    })

    // ── mode selection ────────────────────────────────────────────────────────
    // Settings and Loader are TYPED PROPERTIES, not bare children. QtObject has no default
    // property: a bare `Settings {}` here does not warn, it fails the whole document at LOAD
    // time and takes every importer down with it.

    // Our own persisted preference. QtCore Settings keys off QCoreApplication's org/app, so
    // inside Basecamp this lands in the host's config file rather than the module's own
    // QSettings("paradox.computer","zonescan_lite") store. Two stores for one module is the
    // accepted trade; it buys zero C++ and no .rep regeneration.
    // LIGHT, not "auto", is the shipped default — a product decision, not an oversight.
    // "auto" would follow the Basecamp shell, whose design system ships only a dark theme, so
    // every fresh install would open dark and the light palette this app was built around would
    // never be seen unless someone went looking for the picker. Auto remains one click away for
    // anyone who does want to track the host.
    property Settings own: Settings {
        category: "zonescan_lite"
        property string appearance: "light"     // auto | light | dark
    }
    readonly property string userMode: zt.own.appearance

    // Second-choice host read: the SAME store Logos/Theme/Theme.qml writes. Only consulted
    // when the probe below could not load. QSettings does not signal across Settings objects,
    // so this one cannot track a live host switch - moot while the design system is dark-only.
    property Settings hostCfg: Settings {
        category: "LogosDesignSystem"
        property string theme: "dark"
    }

    // First-choice host read. HostThemeProbe.qml is the only file in the repo that names
    // Logos.Theme, and `import Logos.Theme` is FATAL when the module is absent - it does not
    // warn, the component fails to load. The Loader is what contains that: outside Basecamp
    // it yields status=Loader.Error, item=null, and the app keeps running. Inside Basecamp
    // Theme.isDark is a live observable, so a host theme change propagates.
    property Loader probe: Loader { source: "HostThemeProbe.qml" }
    // Routed through an untyped helper on purpose: the probe's item is a plain QObject to
    // everything but Basecamp, so reading .hostDark off it directly is a qmllint
    // [missing-property] the lint gate would then have to allowlist by name. Both arguments
    // are passed (not read inside) so they stay real binding dependencies.
    readonly property bool hostDark: zt._hostDark(zt.probe.item, zt.hostCfg.theme)
    function _hostDark(item, hostThemeKey) {
        return item ? (item.hostDark === true) : (hostThemeKey === "dark")
    }

    readonly property string effective:
        zt.userMode === "auto" ? (zt.hostDark ? "dark" : "light") : zt.userMode

    // The ONE externally-observed mode property. No COLOUR outside ZTheme may be derived from
    // `effective` or `userMode`: they change BEFORE theme.js has been pushed, so a producer
    // re-invoked off them bakes the outgoing palette.
    //
    // Two reads are exempt and both are deliberate:
    //   * the appearance picker in Main.qml compares `userMode` to decide which of Auto/Light/
    //     Dark is SELECTED. That is state, not colour - and it cannot be replaced by a snapshot
    //     taken inside _apply(), because auto -> dark against a dark host leaves `effective`
    //     unchanged, _apply() never runs, and the picker would show the wrong segment forever.
    //     The pills' own colours come from tokens, so the pre-push window self-corrects.
    //   * the topbar logo picks an ASSET off `_mode` (QML Image has no colour filter and
    //     Qt5Compat.GraphicalEffects is not in the runtime closure), which is post-push.
    property string _mode: "light"

    // ── the live token surface ────────────────────────────────────────────────
    readonly property var pal:      zt._mode === "dark" ? zt.darkPal : zt.lightPal
    readonly property var tyBadge:  zt._mode === "dark" ? zt.darkTy  : zt.lightTy
    readonly property var visBadge: zt._mode === "dark" ? zt.darkVis : zt.lightVis
    readonly property var finBadge: zt._mode === "dark" ? zt.darkFin : zt.lightFin
    readonly property var verBadge: zt._mode === "dark" ? zt.darkVer : zt.lightVer
    readonly property var ctl:      zt._mode === "dark" ? zt.darkCtl : zt.lightCtl

    // The version fallback, kept as a map-read partner: `ZTheme.verBadge[k] || ZTheme.verUnknown`.
    // Derived from tokens rather than frozen, and deliberately NOT a verBadgeFor() helper -
    // that would turn an observable map read into an opaque JS call with no theme dependency.
    readonly property var verUnknown: ({ bg: zt.pal.verFallbackBg, fg: zt.pal.soft })


    // Core ramp - all 15 live in theme.js lightPal; inherited, never redeclared
    readonly property color bg:            zt.pal.bg
    readonly property color panel:         zt.pal.panel
    readonly property color panel2:        zt.pal.panel2
    readonly property color line:          zt.pal.line
    readonly property color line2:         zt.pal.line2
    readonly property color fg:            zt.pal.fg
    readonly property color muted:         zt.pal.muted
    readonly property color soft:          zt.pal.soft
    readonly property color link:          zt.pal.link
    readonly property color navy:          zt.pal.navy
    readonly property color silver:        zt.pal.silver
    readonly property color green:         zt.pal.green
    readonly property color red:           zt.pal.red
    readonly property color amber:         zt.pal.amber
    readonly property color purple:        zt.pal.purple

    // Chrome & controls - hardcoded in the QML today; B3 sweeps the literals onto these
    readonly property color topbarA:       zt.pal.topbarA
    readonly property color topbarB:       zt.pal.topbarB
    readonly property color topbarLine:    zt.pal.topbarLine
    readonly property color ctrlA:         zt.pal.ctrlA
    readonly property color ctrlB:         zt.pal.ctrlB
    readonly property color ctrlSel:       zt.pal.ctrlSel
    readonly property color btnA:          zt.pal.btnA
    readonly property color btnB:          zt.pal.btnB
    readonly property color btnHoverA:     zt.pal.btnHoverA
    readonly property color btnHoverB:     zt.pal.btnHoverB
    readonly property color cardA:         zt.pal.cardA
    readonly property color cardB:         zt.pal.cardB
    readonly property color pheadA:        zt.pal.pheadA
    readonly property color pheadB:        zt.pal.pheadB
    readonly property color insetHi:       zt.pal.insetHi

    // Hero - already dark by design. heroA/heroB must be LIFTED in dark, never darkened:
    readonly property color heroA:         zt.pal.heroA
    readonly property color heroB:         zt.pal.heroB
    readonly property color heroLine:      zt.pal.heroLine
    readonly property color heroFg:        zt.pal.heroFg
    readonly property color heroSub:       zt.pal.heroSub
    readonly property color onDark:        zt.pal.onDark
    readonly property color heroErrFg:     zt.pal.heroErrFg
    readonly property color heroBtnBg:     zt.pal.heroBtnBg
    readonly property color heroBtnHover:  zt.pal.heroBtnHover
    readonly property color heroBtnBd:     zt.pal.heroBtnBd

    // Search & action
    readonly property color searchBg:      zt.pal.searchBg
    readonly property color searchBd:      zt.pal.searchBd
    readonly property color actionA:       zt.pal.actionA
    readonly property color actionB:       zt.pal.actionB
    readonly property color actionHoverA:  zt.pal.actionHoverA
    readonly property color actionHoverB:  zt.pal.actionHoverB
    readonly property color btnBusyA:      zt.pal.btnBusyA
    readonly property color btnBusyB:      zt.pal.btnBusyB
    readonly property color primaryBusy:   zt.pal.primaryBusy

    // Rows, tables, chips
    readonly property color rowHover:      zt.pal.rowHover
    readonly property color rowSel:        zt.pal.rowSel
    readonly property color theadBg:       zt.pal.theadBg
    readonly property color detailBg:      zt.pal.detailBg
    readonly property color chipBg:        zt.pal.chipBg
    readonly property color chipHover:     zt.pal.chipHover
    readonly property color codeBg:        zt.pal.codeBg
    readonly property color idleBg:        zt.pal.idleBg
    readonly property color verFallbackBg: zt.pal.verFallbackBg

    // Danger / warn / toast
    readonly property color dangerBg:      zt.pal.dangerBg
    readonly property color dangerFg:      zt.pal.dangerFg
    readonly property color dangerBd:      zt.pal.dangerBd
    readonly property color dangerHoverBg: zt.pal.dangerHoverBg
    readonly property color dangerHoverBd: zt.pal.dangerHoverBd
    readonly property color warnBg:        zt.pal.warnBg
    readonly property color warnLine:      zt.pal.warnLine
    readonly property color warnFg:        zt.pal.warnFg
    readonly property color warnBd:        zt.pal.warnBd
    readonly property color warnBtnBg:     zt.pal.warnBtnBg
    readonly property color toastBg:       zt.pal.toastBg
    readonly property color toastBd:       zt.pal.toastBd
    readonly property color toastFg:       zt.pal.toastFg
    readonly property color toastErrBg:    zt.pal.toastErrBg
    readonly property color toastErrBd:    zt.pal.toastErrBd
    readonly property color toastErrFg:    zt.pal.toastErrFg
    readonly property color htagFg:        zt.pal.htagFg
    readonly property color htagBg:        zt.pal.htagBg
    readonly property color htagBd:        zt.pal.htagBd

    // Badge tint families - the flat accessors ZBadge and the pages bind to.
    readonly property color bdgEmeraldBg:  zt.pal.bdgEmeraldBg
    readonly property color bdgEmeraldFg:  zt.pal.bdgEmeraldFg
    readonly property color bdgEmeraldBd:  zt.pal.bdgEmeraldBd
    readonly property color bdgSkyBg:      zt.pal.bdgSkyBg
    readonly property color bdgSkyFg:      zt.pal.bdgSkyFg
    readonly property color bdgSkyBd:      zt.pal.bdgSkyBd
    readonly property color bdgZincBg:     zt.pal.bdgZincBg
    readonly property color bdgZincFg:     zt.pal.bdgZincFg
    readonly property color bdgZincBd:     zt.pal.bdgZincBd
    readonly property color bdgTealBg:     zt.pal.bdgTealBg
    readonly property color bdgTealFg:     zt.pal.bdgTealFg
    readonly property color bdgTealBd:     zt.pal.bdgTealBd
    readonly property color bdgAmberBg:    zt.pal.bdgAmberBg
    readonly property color bdgAmberFg:    zt.pal.bdgAmberFg
    readonly property color bdgAmberBd:    zt.pal.bdgAmberBd
    readonly property color bdgVioletBg:   zt.pal.bdgVioletBg
    readonly property color bdgVioletFg:   zt.pal.bdgVioletFg
    readonly property color bdgVioletBd:   zt.pal.bdgVioletBd
    readonly property color bdgIndigoBg:   zt.pal.bdgIndigoBg
    readonly property color bdgIndigoFg:   zt.pal.bdgIndigoFg
    readonly property color bdgIndigoBd:   zt.pal.bdgIndigoBd
    readonly property color bdgFuchsiaBg:  zt.pal.bdgFuchsiaBg
    readonly property color bdgFuchsiaFg:  zt.pal.bdgFuchsiaFg
    readonly property color bdgFuchsiaBd:  zt.pal.bdgFuchsiaBd
    readonly property color bdgRoseBg:     zt.pal.bdgRoseBg
    readonly property color bdgRoseFg:     zt.pal.bdgRoseFg
    readonly property color bdgRoseBd:     zt.pal.bdgRoseBd
    readonly property color bdgOrangeBg:   zt.pal.bdgOrangeBg
    readonly property color bdgOrangeFg:   zt.pal.bdgOrangeFg
    readonly property color bdgOrangeBd:   zt.pal.bdgOrangeBd
    readonly property color bdgYellowBg:   zt.pal.bdgYellowBg
    readonly property color bdgYellowFg:   zt.pal.bdgYellowFg
    readonly property color bdgYellowBd:   zt.pal.bdgYellowBd
    readonly property color bdgYellowSoftBg: zt.pal.bdgYellowSoftBg
    readonly property color bdgYellowSoftFg: zt.pal.bdgYellowSoftFg
    readonly property color bdgYellowSoftBd: zt.pal.bdgYellowSoftBd
    readonly property color bdgGreyBg:     zt.pal.bdgGreyBg
    readonly property color bdgGreyFg:     zt.pal.bdgGreyFg
    readonly property color bdgGreyBd:     zt.pal.bdgGreyBd
    readonly property color bdgFaintBg:    zt.pal.bdgFaintBg
    readonly property color bdgFaintBd:    zt.pal.bdgFaintBd
    readonly property color bdgRedBg:      zt.pal.bdgRedBg
    readonly property color bdgRedFg:      zt.pal.bdgRedFg
    readonly property color bdgSlateBg:    zt.pal.bdgSlateBg
    readonly property color bdgSlateFg:    zt.pal.bdgSlateFg
    readonly property color bdgWhiteBg:    zt.pal.bdgWhiteBg
    readonly property color bdgWhiteFg:    zt.pal.bdgWhiteFg
    readonly property color bdgWhiteBd:    zt.pal.bdgWhiteBd
    readonly property color bdgBlackBg:    zt.pal.bdgBlackBg
    readonly property color bdgBlackFg:    zt.pal.bdgBlackFg
    readonly property color bdgBlackBd:    zt.pal.bdgBlackBd

    // Translucent tints - QML ONLY, spelled #AARRGGBB.
    readonly property color tintGreen:     zt.pal.tintGreen
    readonly property color tintGreen14:   zt.pal.tintGreen14
    readonly property color tintBlue:      zt.pal.tintBlue

    // App-only
    readonly property color scrim:         zt.pal.scrim
    readonly property color mutedDim:      zt.pal.mutedDim
    readonly property color nosettleBg:    zt.pal.nosettleBg
    readonly property color nosettleFg:    zt.pal.nosettleFg
    readonly property color aliveChip:     zt.pal.aliveChip

    // Stock-control palette roles. Flat colour properties so a `palette.window: ZTheme.ctlWindow`
    // block reads like every other binding in the tree.
    readonly property color ctlWindow:          zt.ctl.window
    readonly property color ctlWindowText:      zt.ctl.windowText
    readonly property color ctlBase:            zt.ctl.base
    readonly property color ctlText:            zt.ctl.text
    readonly property color ctlButton:          zt.ctl.button
    readonly property color ctlButtonText:      zt.ctl.buttonText
    readonly property color ctlMid:             zt.ctl.mid
    readonly property color ctlMidlight:        zt.ctl.midlight
    readonly property color ctlLight:           zt.ctl.light
    readonly property color ctlDark:            zt.ctl.dark
    readonly property color ctlShadow:          zt.ctl.shadow
    readonly property color ctlHighlight:       zt.ctl.highlight
    readonly property color ctlHighlightedText: zt.ctl.highlightedText
    readonly property color ctlPlaceholderText: zt.ctl.placeholderText
    readonly property color ctlBrightText:      zt.ctl.brightText
    readonly property color ctlToolTipBase:     zt.ctl.toolTipBase
    readonly property color ctlToolTipText:     zt.ctl.toolTipText

    // ── the flip ─────────────────────────────────────────────────────────────────
    property int paletteRev: 0

    // The re-invocation channel for theme.js's HTML producers. Reading zt.paletteRev HERE,
    // in QML document scope, IS the entire dependency - property capture does not reach a
    // QObject read from inside imported-JS code, but it does reach a singleton reading its own
    // property. A producer called without rich() and touching no token stays stale FOREVER,
    // silently, and qmllint cannot see it. There is no partial-credit failure mode.
    function rich(fn, a, b, c) {
        void zt.paletteRev
        return fn(a, b, c)
    }

    // Ordering is load-bearing: push the DATA into theme.js first, then flip the observed
    // mode, then bump the rev. Reversed, every rich() binding re-runs against the old palette
    // and the whole app renders one theme behind.
    function _apply(m) {
        var dark = (m === "dark")
        ZT.applyPalette(dark ? zt.darkPal : zt.lightPal,
                        dark ? zt.darkTy  : zt.lightTy,
                        dark ? zt.darkVis : zt.lightVis,
                        dark ? zt.darkFin : zt.lightFin,
                        dark ? zt.darkVer : zt.lightVer)
        zt._mode = m
        zt.paletteRev = zt.paletteRev + 1
    }

    function setUserMode(m) {
        if (m === "auto" || m === "light" || m === "dark")
            zt.own.appearance = m
    }

    // ── startup self-checks ───────────────────────────────────────────────────
    // Non-empty means the palette is broken. Left observable rather than only logged so a
    // test (or a future diagnostics panel) can read it instead of scraping stderr.
    property string paletteFault: ""

    // A key present in LIGHT but missing from DARK is the nastiest failure mode in this file
    // and it does not throw: `darkPal.foo` is undefined, so the colour binding silently keeps
    // whatever it was showing, and any theme.js HTML producer interpolates the literal string
    // "undefined" into a style attribute. Both look like "the flip didn't work", not like a
    // missing token, and neither qmllint nor the compiler can see either one.
    //
    // console.error, not warn: qWarning is routinely filtered, qCritical is not. Loud, but
    // never fatal - a missing colour must not take down all 24 importers.
    function _assertKeys() {
        var bad = []
        zt._diffKeys("pal", zt.lightPal, zt.darkPal, bad)
        zt._diffMap("tyBadge",  zt.lightTy,  zt.darkTy,  bad)
        zt._diffMap("visBadge", zt.lightVis, zt.darkVis, bad)
        zt._diffMap("finBadge", zt.lightFin, zt.darkFin, bad)
        zt._diffMap("verBadge", zt.lightVer, zt.darkVer, bad)
        zt._diffKeys("ctl", zt.lightCtl, zt.darkCtl, bad)
        return bad
    }
    function _diffKeys(where, a, b, bad) {
        var k
        for (k in a) if (!(k in b)) bad.push(where + ".dark is MISSING " + k)
        for (k in b) if (!(k in a)) bad.push(where + ".light is MISSING " + k)
    }
    function _diffMap(where, a, b, bad) {
        zt._diffKeys(where, a, b, bad)
        for (var k in a) if (b[k]) zt._diffKeys(where + "." + k, a[k], b[k], bad)
    }

    // Three values in the dark set are DERIVED from other dark values, and JS object literals
    // cannot reference their own siblings, so they are written out by hand. Nothing in the
    // language ties them together - only this check does.
    function _assertDerived() {
        var bad = []
        function eq(what, a, b) { if (String(a) !== String(b)) bad.push(what + " (" + a + " != " + b + ")") }
        eq("darkFin.fin.fg !== darkPal.green",  zt.darkFin.fin.fg,   zt.darkPal.green)
        eq("darkTy.guess.bd !== darkPal.line2", zt.darkTy.guess.bd,  zt.darkPal.line2)
        eq("darkPal.bdgFaintBd !== line2",      zt.darkPal.bdgFaintBd, zt.darkPal.line2)
        eq("lightFin.fin.fg !== lightPal.green",  zt.lightFin.fin.fg,  zt.lightPal.green)
        eq("lightTy.guess.bd !== lightPal.line2", zt.lightTy.guess.bd, zt.lightPal.line2)
        eq("lightPal.bdgFaintBd !== line2",       zt.lightPal.bdgFaintBd, zt.lightPal.line2)
        return bad
    }

    Component.onCompleted: {
        var bad = zt._assertKeys().concat(zt._assertDerived())
        if (bad.length) {
            zt.paletteFault = bad.join("; ")
            console.error("ZTheme: PALETTE BROKEN - " + bad.length + " fault(s). The app will "
                        + "still run, but some surfaces will not flip:")
            for (var i = 0; i < bad.length; i++) console.error("ZTheme:   " + bad[i])
        }
        zt._apply(zt.effective)
    }
    onEffectiveChanged: zt._apply(zt.effective)
}
