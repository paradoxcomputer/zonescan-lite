# Changelog

All notable changes to ZoneScan Lite. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions track `metadata.json`.

## [0.3.0] — 2026-08-25

A pass over everything an audit of the module turned up. The happy path was already
complete; almost all of this is the unhappy path, which previously had no surface at all.

### Fixed

- **The transaction page never loaded, in any build.** `TxPage.qml` declared
  `readonly property string z`, shadowing `QQuickItem::z`, which is FINAL — so the whole page
  failed with *"Cannot override FINAL property"* and rendered as an empty rectangle. This is a
  fourth fatal QML error of the same family as the three fixed in `59d4bfd`, and it explains
  why the recorded exercise run listed every transaction hash as untested. The property is now
  `zoneId`. It was found by the page-load error surface added below, and there is now a repo-wide
  check that no property shadows a FINAL `QQuickItem` name.
- **`poll()` re-entered itself.** Each blocking request spins a nested `QEventLoop`, which
  kept delivering the 2 s repeating poll timer, so a 15 s stall stacked roughly seven nested
  polls and let an older one publish state after a newer one. The timer is now single-shot,
  re-armed when a poll finishes, and guarded by `m_busy`.
- **A failed request looked like an empty chain.** List endpoints collapsed any failure into
  `[]`, which every feed reads as "the last page" — one dropped request showed "no
  transactions" on a busy chain and switched pagination off permanently. Results now carry
  `{ ok, items | error, status }`.
- **"Not found" doubled as the failure message** on the transaction, account and token pages,
  so a network blip stated a falsehood about the chain. 404 and transport failure are now
  separate, and the failure branch offers Retry.
- **`resetFeed()` could issue no request at all** — it cleared the rows but not `feedLoading`,
  and `loadMore()` returns early while that is set. It also had no generation token, so a
  reply for the previous filter could land in the list the new filter had just emptied.
- **Live rows bypassed the active filter** on the account and token pages: both mount a
  `FilterBar` and send its params on fetches, but neither gated polled rows, so with
  Visibility = Private set, public rows appeared at the top within 2 s.
- **Newest rows were prepended to oldest-first lists.** With Sort = Oldest, `prependLive()`
  jammed freshly polled (newest) rows onto the top of a list ordered the other way.
- **Cross-zone duplicate hashes were dropped.** Feeds deduped on the hash alone, but a hash
  is not unique across zones — identical genesis transactions repeat verbatim. Rows are now
  keyed on `channel:hash`, matching the server's own cursor.
- **Back threw away the page.** Navigation called `Loader.setSource()`, destroying and
  rebuilding the item: scroll position, filters, the loaded feed and a local-zone walk of up
  to 20 000 blocks all went with it. Pages are cached per descriptor and swapped by
  visibility, LRU-capped at six.
- **The transaction panel was blank for the whole first fetch.** The empty label was gated on
  `!loading` and the loading footer on `count > 0`, so the first-load case had no branch.
- **A local-zone row led to a permanent "not found"**, and its breadcrumb to a phantom zone
  page. Decoded rows are registered in-process and resolved from there; the breadcrumb no
  longer offers a zone that does not exist.
- **A zonescan decoder outage was blamed on the user's chain.** `decodeBlocks` could not tell
  "the decoder is unreachable" from "this batch held no LEZ blocks", so the walk climbed to
  its 20 000-block ceiling and then reported the wrong cause.
- **The guest-ELF link ignored `$ZONESCAN_BASE_URL`.** `theme.js` hardcoded the production
  origin under a comment claiming it mirrored the backend. The origin is now published as the
  `baseUrl` property and the link follows it.
- **Every "final" / "on L1 · finalizing" status pill rendered as a black box.** `theme.js`
  carried CSS colour strings (`rgba(19,169,123,.14)`), which QML's `color` type cannot parse;
  an unparseable colour is an invalid `QColor` and paints black. Now `#AARRGGBB`.
- **The zones list overflowed its panel.** `ZoneRow` sized its middle column by hand and then
  placed an unconstrained row inside it — ~300px of content in a 340px panel — so the channel
  id and version caption escaped the panel and were clipped mid-word, while the title reserved
  a hardcoded 130px for badges that are usually absent and truncated with room to spare. Now
  laid out with Layouts, every flexible cell eliding.
- **A page that failed to compile rendered as an empty rectangle** — three such errors shipped
  in 0.1.0, and a fourth was still live (see the `z` entry above). The router now reports the
  load error, with Copy error and Go home.
- **A cached page could serve rows fetched under a different filter.** `ZT.FLT` is engine-wide
  and `FilterBar` read it once, at construction; with pages now kept alive rather than rebuilt,
  a re-shown page displayed one filter while paging and gating live rows by another. `FilterBar`
  gained `sync()`, and each page re-syncs and refetches on re-show when the filter signature it
  recorded at fetch time no longer matches.
- **The poll timer restarted itself during shutdown.** `QCoreApplication::closingDown()` is
  false for the whole quit sequence, so the re-arm guard undid the `stop()` that `aboutToQuit`
  had just performed — reinstating the synchronous-call-during-teardown freeze it exists to
  prevent. An explicit shutdown flag replaces it.
- **The 600-row cap left an unrecoverable hole in the feed.** Trimming the tail without moving
  the cursor meant the next page resumed below rows that were no longer in the list. The cursor
  and `seen` are now rewound to the new tail.
- **ProgramPage stopped prepending live rows whenever the shared Sort was Oldest** — its query
  never sends `sort`, so the server always answers newest-first, and the page has no filter bar
  that could clear the condition.
- **`doneNote` was a dependency-free binding**, evaluated once and never again, so the
  oldest-first footer either never appeared or never went away.
- **Zone, Account and Program pages issued two to three identical first-page fetches on open**,
  because `createObject` applies initial properties before completion and the reset no longer
  short-circuited the burst.
- **The first `error()` reached no listener and then silenced the rest of the outage.** The
  first poll runs inside `onContextReady()`, before the generated glue attaches the replica, and
  the dedupe latched on that message. It now decays and repeats every ~30 s.
- **The stale-data banner's age froze at "0 secs ago"** — `Date.now()` is invisible to the
  binding engine and `lastOkUnix` stops changing during an outage. A one-second tick drives it.
- **Detail panels lost drag-to-scroll** when values became selectable `TextEdit`s, which consume
  press-and-drag. The page Flickables now carry a `ScrollBar`, keeping both selection and scrolling.
- **The feed row's copy button starved its own hover**, so its highlight and tooltip never
  rendered; a non-blocking `HoverHandler` on the cell drives its visibility instead.

### Added

- **The zones list shows settling state.** `settling` is published on every sequencer and was
  never rendered anywhere in the port — a zone that had stopped inscribing to the L1 looked
  identical to one that was still going. It is three-state (`true` / `false` / `null`), so
  "unknown" is a real answer and shows no badge rather than a false one. The zone page gains a
  matching **Settling** row.

- Manual **Refresh** (toolbar button, `Ctrl+R`). `refresh()` was implemented and documented
  from the start with nothing in the view able to call it.
- A **stale-data banner**: `connectionStatus` was published by the backend and read by
  nothing, so an outage kept rendering the last good snapshot as though it were live. It now
  says how old the snapshot is and offers Retry. `lastOkUnix` was added to support it.
- **Error surfacing.** The contract's `error(QString)` signal is emitted (deduplicated for
  the duration of an outage) and shown as a toast; failures are also `qCWarning`'d under the
  `zonescan.lite` logging category. The backend previously had no logging at all.
- **Copy and selection.** Detail values are selectable, each has a copy button, and feed rows
  copy their hash on hover or with `Ctrl+C`.
- **Keyboard support** — see the table in the README. There was none: every control was a
  bare `MouseArea` and the search field could not be focused without a pointer.
- **Forward navigation** (`Alt+→` and a button). History entries above the cursor existed but
  nothing could reach them.
- `navType` / `navChannel` / `navId` on the router: the active route as observable strings.
  `nav` is a `var` holding a JS object, which nothing outside QML can read — including the
  integration suite, which otherwise has to infer the route from rendered text (unreliable now
  that pages are cached and keep their text while hidden).
- **Cancel** for a local-sequencer walk, which previously ran to its ceiling with the button
  inert and the URL field disabled throughout.
- **Search feedback** for empty, in-flight and unmatched input, instead of silence or a guess.
- Schema submission now refreshes the registry immediately via `getSchemas()` rather than
  leaving decodes stale for up to ~30 s while claiming to reload.
- Responsive layouts on Home and in the feed table; the feed panel's width previously went
  negative below ~356 px and columns were clipped with no way to scroll to them.
- `README.md`, this changelog, and a `ci` workflow running `nix flake check` on push and PR.
  There was no CI gate and not one tracked `.md` file.
- Integration coverage for the local-zone panel, search feedback, the filter bar, the empty
  zones list and the connection pill (9 sandboxed tests, up from 2).
- A second suite in `tests-live/` covering the Tx, Account and Zone routes, Back and Forward,
  and — the assertion that found the `z` bug — that no navigation leaves the router reporting a
  page-load error. It is separate because the detail routes can only be reached by clicking a
  real row, which needs a reachable zonescan; CI runs it as a non-blocking job.

### Changed

- **The version is single-sourced.** CMake reads `metadata.json` and defines
  `ZONESCAN_LITE_VERSION`; the User-Agent was previously hand-typed in two places. The module
  version is shown in the topbar so a bug report can quote it.
- `metadata.json` declares `author` and `license`; the shipped manifest carried `"author": ""`
  and no terms. (`license` cannot reach the `.lgx` manifest yet — see the README.)
- `TxTable.showZone` is honoured by the rows, not just the header, and is set to `false` on
  every single-zone feed, which used to repeat one identical channel down the widest column.
- `ZoneRow.selected` marks the zone you last opened. It, and the `pal.rowSel` colour it alone
  uses, were never assigned by anything.
- Feeds cap retained rows at 600, now that cached pages keep prepending while hidden.

### Removed

- **The `aliases` property.** Nothing could ever populate it: zonescan exposes no alias
  endpoint (`/api/aliases` is the SPA HTML fallback) and no alias field on a sequencer, so
  `CHAN_ALIAS` was permanently empty and every alias branch was dead. `chanLabel` and
  `zoneTitle` keep working on the channel's short hex.
- Seven unreferenced icons (`copy`, `home`, `arrow-left`, `arrow-right`, `activity`, `box`,
  `file-text`) that shipped in every bundle. The affordances they were drawn for are now
  built with text glyphs.
- `result-it`, a build symlink into one developer's Nix store that was tracked in git and
  rewritten by three separate commits.

## [0.2.0]

- Merged the `zonescan_bridge` module in and renamed to `zonescan_lite`.
- Rewrote the local-zone walk in continuation-passing style; released the feed source pin
  when the local zone stops being live.
- Fixed three fatal QML load errors and repointed the test suite at real rendered text.
- Caught up to zonescan v0.7.0: corrected amounts, added the local zone.
