import QtQuick
import "../theme"
import "../theme.js" as ZT

// "Channel activity" explainer panel (mirrors activityPanel): shown for a zone
// that has activity but no user-tx rows. Three honest states — finalizing /
// clock-only / raw — each with a finality badge, headline, slot range, inscriber
// keys, tip hash, balance and an explainer paragraph.
Rectangle {
    id: root
    property var seq: ({})
    property var state: null
    readonly property string st: seq && seq.activity_state ? seq.activity_state : ""
    visible: st.length > 0
    height: visible ? col.implicitHeight : 0
    color: ZTheme.panel
    radius: 12
    border.width: 1
    border.color: ZTheme.line

    readonly property int lib: (state && state.l1 && state.l1.lib_slot) || 0
    readonly property int tip: (seq && seq.l1_tip_slot) || 0
    readonly property int start: (seq && seq.l1_tip_start_slot) || 0
    readonly property int nInsc: (seq && seq.inscriptions_seen) || 0
    readonly property var keys: (seq && seq.accredited_keys) || []

    // per-state descriptors
    readonly property var desc: {
        if (st === "finalizing") {
            var gap = tip > lib ? tip - lib : 0;
            var eta = gap > 0 ? (ZT.num(gap) + " slot" + (gap === 1 ? "" : "s") + " to finalize (~" + Math.max(1, Math.round(gap / 60)) + " min)") : "finalizing now";
            return { tier: "safe", badge: "on L1 · finalizing",
                headline: (nInsc > 0 ? ZT.num(nInsc) + " " : "") + "inscription" + (nInsc === 1 ? "" : "s") + " · finalizing",
                note: "Recent inscriptions are settled on the L1 but not yet finalized. Their contents become visible once finalized - they may be clock heartbeats or user transactions; unknown until then. New inscriptions appear live.",
                eta: eta };
        }
        if (st === "clock-only") {
            return { tier: "pend", badge: "idle · clock-only",
                headline: "clock-only · " + (nInsc > 0 ? ZT.num(nInsc) + " " : "") + "heartbeat inscription" + (nInsc === 1 ? "" : "s") + " · no user txs",
                note: "This channel has settled only clock heartbeats in the scanned window - no user transactions. Clock ticks are hidden from the feed.",
                eta: "" };
        }
        return { tier: "safe", badge: "raw inscriptions",
            headline: (nInsc > 0 ? ZT.num(nInsc) + " " : "") + "raw inscription" + (nInsc === 1 ? "" : "s") + " · not a sequencer block",
            note: "This channel settles raw text/data inscriptions rather than sequencer blocks. Each is listed below as its own inscription row - open one to read its content (decoded UTF-8 text, or a hex dump). New inscriptions appear live.",
            eta: "" };
    }

    Column {
        id: col
        width: parent.width
        // phead
        Rectangle {
            width: parent.width; height: 46
            gradient: Gradient { GradientStop { position: 0; color: ZTheme.pheadA } GradientStop { position: 1; color: ZTheme.pheadB } }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZTheme.line }
            Row {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter; leftMargin: 16 }
                spacing: 10
                Text { text: "Channel activity"; color: ZTheme.navy; font.pixelSize: 14; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    property var fc: ZTheme.finBadge[root.desc.tier]
                    width: bl.implicitWidth + 12; height: bl.implicitHeight + 4; radius: 5; color: fc.bg
                    Text { id: bl; anchors.centerIn: parent; text: root.desc.badge; color: parent.fc.fg; font.pixelSize: 10; font.weight: Font.Bold }
                }
            }
        }
        // headline
        Text {
            x: 18; topPadding: 14; width: parent.width - 36
            text: root.desc.headline; color: ZTheme.navy; font.pixelSize: 13; font.weight: Font.DemiBold; wrapMode: Text.WordWrap
        }
        // kv grid
        Grid {
            x: 18; width: parent.width - 36; columns: 2; columnSpacing: 18; rowSpacing: 7
            topPadding: 12; bottomPadding: 4
            property real kw: 150
            Text { width: parent.kw; text: "Activity (L1 slots)"; color: ZTheme.soft; font.pixelSize: 12 }
            Text { width: parent.width - parent.kw - 18; text: ZT.num(root.start) + " → " + ZT.num(root.tip); color: ZTheme.fg; font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace"; wrapMode: Text.WrapAnywhere }
            // finality eta (finalizing only)
            Text { visible: root.desc.eta.length > 0; width: parent.kw; text: "Finality"; color: ZTheme.soft; font.pixelSize: 12 }
            Text { visible: root.desc.eta.length > 0; width: parent.width - parent.kw - 18; text: root.desc.eta + "  (tip slot " + ZT.num(root.tip) + " vs last-final " + ZT.num(root.lib) + ")"; color: ZTheme.fg; font.pixelSize: 13; wrapMode: Text.WordWrap }
            Text { width: parent.kw; text: "Inscriber"; color: ZTheme.soft; font.pixelSize: 12 }
            Text { width: parent.width - parent.kw - 18
                text: root.keys.length ? root.keys.map(function (k) { return ZT.sh(k, 10, 6); }).join(", ") + (root.seq && root.seq.config_threshold != null ? "  · " + ZT.num(root.seq.config_threshold) + " of " + (root.keys.length || "?") + " to inscribe" : "") : "-"
                color: ZTheme.fg; font.pixelSize: 12; font.family: "ui-monospace, Menlo, Consolas, monospace"; wrapMode: Text.WrapAnywhere }
            Text { width: parent.kw; text: "Tip hash"; color: ZTheme.soft; font.pixelSize: 12 }
            Text { width: parent.width - parent.kw - 18; text: root.seq && root.seq.tip_message ? ZT.sh(root.seq.tip_message, 10, 6) : "-"; color: ZTheme.fg; font.pixelSize: 12; font.family: "ui-monospace, Menlo, Consolas, monospace" }
            Text { width: parent.kw; text: "Channel balance"; color: ZTheme.soft; font.pixelSize: 12 }
            Text { width: parent.width - parent.kw - 18; text: root.seq && root.seq.l1_balance != null ? ZT.num(root.seq.l1_balance) : "-"; color: ZTheme.fg; font.pixelSize: 13; font.family: "ui-monospace, Menlo, Consolas, monospace" }
        }
        // note
        Text {
            x: 18; topPadding: 6; bottomPadding: 16; width: parent.width - 36
            text: root.desc.note; color: ZTheme.muted; font.pixelSize: 12; lineHeight: 1.4; wrapMode: Text.WordWrap
        }
    }
}
