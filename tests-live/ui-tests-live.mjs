import { resolve } from "node:path";
const root = process.env.LOGOS_QT_MCP || new URL("../result-mcp", import.meta.url).pathname;
const { test, run } = await import(resolve(root, "test-framework/framework.mjs"));

// LIVE suite: needs network and a reachable zonescan.
//
// It lives in tests-live/, NOT tests/, on purpose. logos-module-builder's mkLogosQmlModule
// globs every .mjs in tests/ into the `integration-test` check, which runs inside the nix
// sandbox with no network — so a live suite placed there fails every build, and (because the
// runner stops at the first failing file, and "ui-tests-live.mjs" sorts before "ui-tests.mjs")
// it also prevents the sandboxed suite from running at all.
//
// It exists because the detail routes cannot be reached any other way: the inspector exposes
// findAndClick / findByProperty / getTree / listInteractive and nothing that types into a field
// or calls a QML method, so the only way onto a Zone, Tx or Account page is to click a real row.
//
//   just test-live
//
// In CI it is a separate, non-blocking job: a zonescan outage must not block a merge.

const SEC = 1000;

// The active route comes from the router itself (Main.qml's navType), not from rendered text.
// Text is not a usable oracle: the router caches page instances and only toggles visibility,
// and the inspector's findByProperty ignores visibility — so once a zone page has been opened,
// its "Channel id" label answers forever.
const ROUTE = { home: "home", zone: "zone", tx: "tx", wallet: "wallet", token: "token", program: "program" };

// Navigation here is deliberately deterministic rather than shape-guessing. A channel_short
// label like "8808968d…7d6e" appears BOTH as a zones-sidebar title and as the ZONE cell of
// every feed row — and the whole feed row is clickable — so clicking one lands on the tx route
// about as often as the zone route. Only the transaction hash cell is unambiguous, so the flow
// enters at the tx route and reaches the zone route through TxPage's breadcrumb.
const TX_LABEL = /^[0-9a-f]{12}…[0-9a-f]{8}$/i;            // ZT.sh(hash, 12, 8)
const ZONE_CRUMB = /^Zone [0-9a-f]{12}…[0-9a-f]{8}$/i;     // TxPage's breadcrumb
const BASE58_ACCOUNT = /^[1-9A-HJ-NP-Za-km-z]{32,44}$/;

// Content assertions, checked once the route oracle says we are in the right place.
const TX_CONTENT = ["Txn Hash", "Visibility"];
const ZONE_CONTENT = ["Channel id", "Chain check", "Inscriptions seen"];
const ACCOUNT_CONTENT = ["Address"];

async function texts(app) {
  const res = await app.findByProperty("text");
  return (res.matches || []).map((m) => String(m.value)).filter(Boolean);
}

async function rootProps(app) {
  const res = await app.findByProperty("histIndex");
  const m = (res.matches || [])[0];
  if (!m) throw new Error("explorer root not found");
  const p = await app.getProperties(m.id);
  const raw = p.properties || [];
  const arr = Array.isArray(raw) ? raw : Object.entries(raw).map(([name, value]) => ({ name, value }));
  const out = {};
  for (const e of arr) out[e.name] = e.value;
  return out;
}
async function route(app) { return (await rootProps(app)).navType; }
async function atRoute(app, want) { try { return (await route(app)) === want; } catch { return false; } }

// The router reports a page that failed to compile in `pageError`. This is the assertion that
// matters most in this file: a fatal QML error in a detail page is invisible to the sandboxed
// suite (which cannot navigate) and used to be invisible in the app too — TxPage shadowed
// QQuickItem's FINAL `z` property and never loaded at all, which is why no recorded run ever
// opened a transaction.
async function assertNoPageError(app) {
  const err = (await rootProps(app)).pageError;
  if (err) throw new Error(`the page failed to load: ${String(err).trim()}`);
}

// Re-issue a click until it visibly takes effect. The inspector clicks an item's CURRENT
// mapped position and reports clicked:true whether or not anything received the event, so a
// click issued while the layout is still settling silently misses. Cached hidden pages also
// contribute clickable-looking labels that no longer sit anywhere on screen.
async function clickUntil(app, text, settled, { timeout = 8 * SEC, interval = 600 } = {}) {
  const start = Date.now();
  while (Date.now() - start < timeout) {
    if (await settled()) return true;
    try { await app.click(text, { exact: true }); } catch { /* not laid out, or gone */ }
    await new Promise((r) => setTimeout(r, interval));
  }
  return await settled();
}

async function goHome(app) {
  if (await atRoute(app, ROUTE.home)) return;
  if (!(await clickUntil(app, "<b>zone</b>scan", () => atRoute(app, ROUTE.home))))
    throw new Error("could not get back to home");
}

test("live: the feed loads real rows", async (app) => {
  // Precondition for the walk below. If zonescan is unreachable this fails here, loudly,
  // rather than letting the walk pass without asserting anything.
  await app.waitFor(async () => {
    await app.expectTexts(["TXN HASH"]);
    if (!(await texts(app)).some((t) => TX_LABEL.test(t))) throw new Error("no transaction row rendered yet");
  }, { timeout: 60 * SEC, interval: 1000, description: "the network feed to deliver rows" });
});

test("live: walks tx -> account -> zone and back through history", async (app) => {
  // One walk rather than a test per route. Every re-entry from home is a chance to click a
  // stale position (see clickUntil), and each visited page stays cached and keeps offering
  // labels that are no longer on screen — so repeatedly returning home to reach the next route
  // is the flakiest possible shape for this. Walking straight through touches the same four
  // routes plus Back and Forward, and only enters from home once.

  // ── tx route ──────────────────────────────────────────────────────────────
  // Try successive rows: a transaction with no listed accounts (private or raw) cannot serve
  // the account step below, so keep going until one can.
  await goHome(app);
  const candidates = (await texts(app)).filter((t) => TX_LABEL.test(t));
  let acct = null;
  for (let i = 0; i < Math.min(8, candidates.length) && !acct; i++) {
    await goHome(app);
    await new Promise((r) => setTimeout(r, 700));   // let the feed re-create its delegates
    if (!(await clickUntil(app, candidates[i], () => atRoute(app, ROUTE.tx), { timeout: 10 * SEC }))) continue;
    await assertNoPageError(app);
    await app.expectTexts(TX_CONTENT);
    // Chips carrying a full base58 id exist only on TxPage, and only home is cached besides it
    // at this point, so this cannot pick up a stale label from elsewhere.
    acct = (await texts(app)).find((t) => BASE58_ACCOUNT.test(t)) || null;
  }
  if (!(await atRoute(app, ROUTE.tx))) throw new Error("no row opened the tx route");
  if (!acct) throw new Error("no transaction with a listed account found");

  // ── account route ─────────────────────────────────────────────────────────
  if (!(await clickUntil(app, acct, () => atRoute(app, ROUTE.wallet), { timeout: 30 * SEC })))
    throw new Error("the account chip did not open the account route");
  await assertNoPageError(app);
  await app.expectTexts(ACCOUNT_CONTENT);

  // ── back to the transaction ───────────────────────────────────────────────
  if (!(await clickUntil(app, "←", () => atRoute(app, ROUTE.tx), { timeout: 20 * SEC })))
    throw new Error("Back did not return to the tx route");
  const mid = await rootProps(app);
  // Forward entries used to sit above the cursor with nothing able to reach them.
  if (!mid.canForward) throw new Error("Back did not leave a forward entry");

  // ── forward again ─────────────────────────────────────────────────────────
  if (!(await clickUntil(app, "→", () => atRoute(app, ROUTE.wallet), { timeout: 20 * SEC })))
    throw new Error("Forward did not return to the account route");

  // ── zone route, via TxPage's breadcrumb ───────────────────────────────────
  if (!(await clickUntil(app, "←", () => atRoute(app, ROUTE.tx), { timeout: 20 * SEC })))
    throw new Error("Back did not return to the tx route");
  const crumb = (await texts(app)).find((t) => ZONE_CRUMB.test(t));
  if (!crumb) throw new Error("no zone breadcrumb on the tx page");
  if (!(await clickUntil(app, crumb, () => atRoute(app, ROUTE.zone), { timeout: 20 * SEC })))
    throw new Error("the breadcrumb did not open the zone route");
  await assertNoPageError(app);
  await app.expectTexts(ZONE_CONTENT);
});

run();
