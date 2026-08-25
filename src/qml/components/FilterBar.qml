import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import "../theme.js" as ZT

// .filtbar — Visibility select · multi-select Type dropdown · Sort select.
// Mutates the shared ZT.FLT state and emits changed() so the feed re-fetches
// (server params via ZT.filterParams) and the live prepend re-gates (filterMatches).
Rectangle {
    id: root
    signal changed()
    implicitHeight: 44
    color: "transparent"
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: ZT.pal.line }

    // Bumped by sync(); the type checkboxes and the Type button label reference it so they
    // re-read ZT.FLT (a plain JS var the binding engine cannot observe).
    property int syncTick: 0

    // Pull the controls from the shared FLT state. Called on creation AND whenever the page is
    // re-shown from the router's cache: FLT is engine-wide, so it can have changed on another
    // page while this one was merely hidden rather than destroyed.
    function sync() {
        var visModel = [ "all", "public", "private", "raw" ];
        visSel.currentIndex = Math.max(0, visModel.indexOf(ZT.FLT.vis));
        sortSel.currentIndex = ZT.FLT.sort === "oldest" ? 1 : 0;
        root.syncTick = root.syncTick + 1;
    }
    Component.onCompleted: root.sync()

    RowLayout {
        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                  leftMargin: 16; rightMargin: 16 }
        spacing: 18

        // ── Visibility ──
        RowLayout {
            spacing: 8
            Text { text: "VISIBILITY"; color: ZT.pal.soft; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.4 }
            ComboBox {
                id: visSel
                Layout.preferredWidth: 104
                model: [ {t:"All",v:"all"}, {t:"Public",v:"public"}, {t:"Private",v:"private"}, {t:"Raw",v:"raw"} ]
                textRole: "t"
                font.pixelSize: 12
                currentIndex: 0
                onActivated: { ZT.FLT.vis = model[currentIndex].v; root.changed(); }
            }
        }

        // ── Type (multi-select) ──
        RowLayout {
            spacing: 8
            Text { text: "TYPE"; color: ZT.pal.soft; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.4 }
            Button {
                id: typeBtn
                Layout.preferredWidth: 120
                font.pixelSize: 12
                text: {
                    root.syncTick;
                    var n = ZT.fltTypesCount();
                    return n ? (n + " selected") : "All types";
                }
                onClicked: typeMenu.open()
                contentItem: RowLayout {
                    Text { text: typeBtn.text; color: ZT.pal.fg; font.pixelSize: 12; Layout.fillWidth: true; elide: Text.ElideRight }
                    Text { text: "▾"; color: ZT.pal.soft; font.pixelSize: 10 }
                }
                Popup {
                    id: typeMenu
                    y: typeBtn.height + 5
                    width: 180
                    padding: 6
                    background: Rectangle { color: ZT.pal.panel; border.color: ZT.pal.line2; border.width: 1; radius: 9 }
                    ColumnLayout {
                        spacing: 0
                        Repeater {
                            model: ZT.TYPE_CHIPS
                            delegate: CheckBox {
                                required property var modelData
                                text: modelData[1]
                                font.pixelSize: 13
                                checked: { root.syncTick; return !!ZT.FLT.types[modelData[0]]; }
                                onToggled: {
                                    if (checked) ZT.FLT.types[modelData[0]] = true;
                                    else delete ZT.FLT.types[modelData[0]];
                                    root.syncTick = root.syncTick + 1;
                                    root.changed();
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── Sort ──
        RowLayout {
            spacing: 8
            Text { text: "SORT"; color: ZT.pal.soft; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.4 }
            ComboBox {
                id: sortSel
                Layout.preferredWidth: 104
                model: [ {t:"Newest",v:"newest"}, {t:"Oldest",v:"oldest"} ]
                textRole: "t"
                font.pixelSize: 12
                currentIndex: 0
                onActivated: { ZT.FLT.sort = model[currentIndex].v; root.changed(); }
            }
        }
        Item { Layout.fillWidth: true }
    }
}
