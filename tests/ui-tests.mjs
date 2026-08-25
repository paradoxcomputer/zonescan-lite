import { resolve } from "node:path";
const root = process.env.LOGOS_QT_MCP || new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(root, "test-framework/framework.mjs"));

// expectTexts matches a Text item's `text` property EXACTLY (the inspector's findByProperty
// compares values, not substrings), so every string below is copied from the QML verbatim -
// not from the website. The original two assertions ("ZoneScan", "Recent Transactions") were
// taken from the web dashboard's wording and match nothing in the QML, so that suite failed
// from the day it was written and caught none of the three fatal QML load errors that shipped
// in zonescan_ui 0.1.0. Keep these in sync with the QML.
//
// click() is the opposite: the inspector's findAndClick defaults to a CASE-INSENSITIVE
// SUBSTRING match and takes the first hit in tree order. Plain click("Search") therefore lands
// on the search field's placeholder ("Search by Txn Hash / Account / Channel") and
// click("Connect") lands on the loading overlay ("Connecting to zonescan…"). Every click below
// passes { exact: true }.
//
// The suite runs sandboxed, WITHOUT network. That is deliberate: it is the state in which
// most of the interesting behaviour lives (a request that fails must say so rather than
// rendering an empty chain), and it is the only state CI can reproduce. Anything that can
// legitimately differ with network available is asserted through `either()` below.

const SEC = 1000;

// Assert that at least one of several alternatives renders. Used where the outcome depends on
// whether zonescan is reachable, so the suite passes both in the sandbox and on a dev box.
// Re-issue a click until it visibly takes effect.
//
// The inspector clicks an item's CURRENT mapped scene position, and reports clicked:true
// whether or not anything received the event. Right after a panel is revealed the layout below
// it has not settled, so the position can be stale — measured: a click on the local-zone
// Connect button reported success at y=374 while the settled button was at y=458, and the
// MouseArea never saw it. Property assertions (expectTexts) do not wait for layout, so they
// cannot be used to gate the click either. Retrying is the reliable fix.
async function clickUntil(app, text, settled, { timeout = 30 * SEC, interval = 800, description = "click to take effect" } = {}) {
  const start = Date.now();
  let lastErr = null;
  while (Date.now() - start < timeout) {
    if (await settled()) return;
    try { await app.click(text, { exact: true }); } catch (e) { lastErr = e; }
    await new Promise((r) => setTimeout(r, interval));
  }
  if (await settled()) return;
  throw new Error(`${description}: "${text}" never took effect${lastErr ? ` (last click error: ${lastErr.message})` : ""}`);
}

async function either(app, alternatives, description) {
  const errors = [];
  for (const texts of alternatives) {
    try { await app.expectTexts(texts); return texts; }
    catch (e) { errors.push(e.message); }
  }
  throw new Error(`none of the alternatives rendered (${description}):\n  ${errors.join("\n  ")}`);
}

test("zonescan_lite: loads the view", async (app) => {
  // topbar brand, Main.qml (StyledText, so the markup is part of the property value)
  await app.waitFor(async () => { await app.expectTexts(["<b>zone</b>scan"]); },
    { timeout: 30 * SEC, interval: 500, description: "the explorer view to load" });
});

test("zonescan_lite: renders the home page", async (app) => {
  // Phead titles + a ZStatCard label. ZStatCard renders k.toUpperCase(), hence the case.
  // These are static, so they render even with no network and no backend state.
  await app.waitFor(async () => {
    await app.expectTexts(["Latest Transactions", "Zones", "L1 BLOCK HEIGHT"]);
  }, { timeout: 15 * SEC, interval: 500, description: "the home page to render" });
});

test("zonescan_lite: topbar reports the module version", async (app) => {
  // Main.qml renders "v" + backend.version, published from the compile-time
  // ZONESCAN_LITE_VERSION that CMake reads out of metadata.json - so the pill cannot drift
  // from the manifest. The expected string is discovered rather than read from metadata.json:
  // the suite runs from the nix store, where the repo layout is not around it.
  await app.waitFor(async () => {
    const res = await app.findByProperty("text");
    const hit = (res.matches || []).some((m) => /^v\d+\.\d+\.\d+/.test(String(m.value)));
    if (!hit) throw new Error("no v<version> pill rendered");
  }, { timeout: 15 * SEC, interval: 500, description: "the version pill" });
});

test("zonescan_lite: connection pill reports reachability, not silence", async (app) => {
  // The pill is keyed on connectionStatus first and the L1's own health second. With zonescan
  // unreachable it must say so; connectionStatus used to be published and read by nothing, so
  // an outage rendered as a healthy green "L1 synced".
  await app.waitFor(async () => {
    await either(app, [["connecting…"], ["zonescan unreachable"], ["L1 synced"], ["L1 online"],
                       ["L1 unreachable"]], "connection pill");
  }, { timeout: 20 * SEC, interval: 500, description: "the connection pill to report a state" });
});

test("zonescan_lite: transaction feed reaches a resolved state", async (app) => {
  // Either rows and their column header render, or the feed reports the failure with a Retry.
  // What must NOT happen is the third thing it used to do: stay blank, then claim the chain is
  // empty. "Retry" here can only be the feed's own error bar - the stale banner needs
  // connectionStatus === "Error", which requires at least one poll to have succeeded first.
  await app.waitFor(async () => {
    await either(app, [["TXN HASH", "BLOCK"], ["Retry"]], "tx feed");
  }, { timeout: 30 * SEC, interval: 500, description: "the feed to load or report a failure" });
});

test("zonescan_lite: filter bar renders its controls", async (app) => {
  // FilterBar labels are uppercase literals; the Type button's default label is "All types".
  await app.waitFor(async () => {
    await app.expectTexts(["VISIBILITY", "SORT", "All types"]);
  }, { timeout: 15 * SEC, interval: 500, description: "the filter bar to render" });
});

test("zonescan_lite: zones sidebar states why it is empty", async (app) => {
  // With no sequencers in state, the list must explain itself rather than render nothing.
  // Which message depends on state.discovering, so accept the whole set.
  await app.waitFor(async () => {
    await either(app, [["no sequencers found"], ["scanning the L1 for sequencers…"],
                       ["CHANNEL ID"]], "zones sidebar");
  }, { timeout: 20 * SEC, interval: 500, description: "the zones sidebar to resolve" });
});

test("zonescan_lite: local sequencer panel opens and reports an outcome", async (app) => {
  // The framework runs every test against ONE app process, so this is a single test rather
  // than two: the "Add your local sequencer" control toggles, and clicking it twice would
  // close the panel it just opened.
  //
  // Opening it is the one interaction a recorded exercise run confirmed working, and it puts
  // the panel's privacy claim under test - the module's only outbound-data statement.
  await app.click("Add your local sequencer", { exact: true });
  await app.waitFor(async () => {
    await app.expectTexts([
      "SEQUENCER ADDRESS",
      "http://127.0.0.1:3070",
      "Connect",
      "Reads a sequencer on your own machine. Only the encoded blocks are sent to the zonescan server, to be decoded; nothing about your chain is stored.",
    ]);
  }, { timeout: 15 * SEC, interval: 500, description: "the local-zone panel to open" });

  // Nothing listens on 127.0.0.1:3070 in the sandbox, so this normally exercises the failure
  // branch - the only branch of this feature a recorded run has ever reached. If a sequencer
  // IS running on a dev box, the success branch is accepted instead. The regression guarded
  // here is silence: Connect must never leave the panel with nothing to say.
  const OUTCOMES = [
    ["could not reach a sequencer at http://127.0.0.1:3070"],
    ["connected, but no blocks were returned"],
    ["blocks were read but none decoded as LEZ blocks"],
    ["Disconnect"],
  ];
  await clickUntil(app, "Connect",
    async () => { try { await either(app, OUTCOMES, "local connect outcome"); return true; } catch { return false; } },
    { timeout: 60 * SEC, description: "the local connect attempt" });
});

test("zonescan_lite: empty search explains itself", async (app) => {
  // Clicking Search with an empty field used to return silently, which is indistinguishable
  // from a broken button - a recorded run logged exactly that as "nothing".
  await clickUntil(app, "Search",
    async () => {
      try { await app.expectTexts(["Enter a transaction hash, account, token, channel id or zone name."]); return true; }
      catch { return false; }
    },
    { timeout: 20 * SEC, description: "search to report the empty input" });
});

run();
