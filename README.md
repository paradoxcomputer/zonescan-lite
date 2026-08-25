# ZoneScan Lite

A block explorer for [Logos Execution Zones](https://logos.co) (LEZ), packaged as a
`ui_qml` Logos module and rendered inside Logos Basecamp. It shows L1/L2 liveness, the
tracked sequencer zones, and a live transaction feed with account, token, program and
transaction detail views — plus an optional **local zone**: a sequencer running on your own
machine, read over JSON-RPC and shown alongside the tracked ones.

<!-- Screenshot intentionally omitted: the module renders inside Basecamp, not standalone. -->

## Quick start

```sh
just build          # nix build  -> result/lib/*.so + the module bundle
just run            # preview the UI standalone via the builder
just test           # nix flake check -> the Qt-MCP integration suite
just develop        # builder dev shell
```

You need [Nix](https://nixos.org/download) with flakes enabled. Nothing else — the Qt 6
toolchain, `repc`, and the test framework all come from the flake.

## Install

**From the Paradox Computer repository** — the normal way, and the one to give users:

1. Open **Logos Basecamp** → **Settings → Repositories → Add a repository**.
2. Paste:
   ```
   https://paradoxcomputer.github.io/logos-modules/repo.json
   ```
3. Open the **Package Manager**, find **ZoneScan Lite**, and **Install**.
4. Launch it from the sidebar.

It has no dependencies — nothing else is pulled in — and Basecamp picks the build for your
platform automatically (`linux-amd64`, `darwin-arm64`; `linux-amd64-dev` is the Nix dev
Basecamp).

### Installing a local build instead

For a build from this checkout:

```sh
nix build .#lgx-portable -o result-portable     # -> variants/linux-amd64  (what you publish)
nix build .#lgx          -o result              # -> variants/linux-amd64-dev (Nix dev Basecamp)
```

Then either install the `.lgx` from Basecamp's Package Manager, or unpack it over the plugin
directory Basecamp reads:

```sh
P=~/.local/share/Logos/LogosBasecampDev/plugins/zonescan_lite
mv "$P" "$P.bak-$(date +%F-%H%M%S)"            # keep a rollback, OUTSIDE plugins/
mkdir -p "$P" && t=$(mktemp -d) && tar xzf result/*.lgx -C "$t"
cp -a "$t/variants/linux-amd64-dev/." "$P/" && cp -a "$t/manifest.json" "$P/"
printf linux-amd64-dev > "$P/variant" && chmod -R u+w "$P"
```

Then **restart Basecamp** — a running `ui-host` keeps the old plugin `.so` mapped.

> Move the backup **out of `plugins/`**. Anything under it with a `manifest.json` is a
> registered app, so a `zonescan_lite.bak-*` directory left there declares a second app named
> `zonescan_lite` and Basecamp may load that one instead.

## Pointing it at a different zonescan

The backend reads its REST origin from `$ZONESCAN_BASE_URL`, defaulting to
`https://zonescan.paradox.computer`:

```sh
ZONESCAN_BASE_URL=http://localhost:8080 just run
```

The origin is republished to the view as the `baseUrl` property, so external links (the
guest-ELF download) follow it rather than being pinned to production.

## How it is put together

| Path | What it is |
| --- | --- |
| `metadata.json` | The module manifest. **The version here is the only one** — CMake reads it and defines `ZONESCAN_LITE_VERSION`. |
| `src/zonescan_lite.rep` | The QtRO view contract: PROPs, SLOTs and the `error` signal that C++ and QML share. |
| `src/zonescan_lite_backend.{h,cpp}` | The only hand-written C++. Blocking HTTP against zonescan's REST API, a 2 s poll loop, JSON → QVariant. |
| `src/qml/Main.qml` | Topbar, hero + search, the router (history stack + a page cache), keyboard shortcuts, clipboard, notices. |
| `src/qml/theme.js` | Palette plus every formatter, classifier and decoder, ported 1:1 from the web dashboard. |
| `src/qml/pages/` | `Home`, `Zone`, `Tx`, `Account`, `Token`, `Program`. |
| `src/qml/components/` | The shared feed table, rows, badges, filter bar, local-zone panel. |
| `tests/ui-tests.mjs` | The integration suite, driven through the Qt MCP inspector. |

### Call results

Every SLOT that can fail returns a map carrying an explicit outcome:

```js
{ ok: true,  items: [...] }                       // or the endpoint's own payload
{ ok: false, error: "request timed out after 15s", status: 0 }
```

Branch on `ok`, and use `status === 404` to tell "this does not exist" from "the request did
not land". A bare `[]` or `{}` never means failure — that ambiguity previously made a
timeout render as an empty chain.

In QML every SLOT returns a **pending token**, not a value. Resolve it through
`explorer.watch(...)` (which wraps `logos.watch`); reading `.result` off the call directly
always yields `undefined`.

### The poll loop

`poll()` runs every 2 s on a **single-shot timer re-armed when it finishes**, and is guarded
by `m_busy`. Both matter: each blocking request spins a nested `QEventLoop` that keeps
delivering timer events, so a repeating timer would re-enter `poll()` inside a request that
is still blocked.

## Keyboard

| Key | Action |
| --- | --- |
| `/`, `Ctrl+F` | Focus the search field |
| `Enter` | Search / open the focused row |
| `Esc` | Dismiss search focus, else Back |
| `Alt+←` | Back |
| `Alt+→` | Forward |
| `Alt+Home` | Home |
| `Ctrl+R`, `F5` | Refresh |
| `Tab` | Walk the zone and transaction rows |
| `Ctrl+C` | Copy the focused row's hash |

## Tests

```sh
just test       # tests/  — sandboxed, no network. This is the CI gate.
just test-app   # drive the REAL app in Basecamp against sitometres.yaml (13 steps)
just smoke      # crawl the app with no spec
```

`just` is not required — every recipe is one command; `nix shell nixpkgs#just` if you want it.

Both drive the built module under `-platform offscreen` through the inspector socket, and
assert on **rendered text copied verbatim from the QML** — so keep the two in sync when you
change a label.

`tests/` runs under `nix flake check`, which has no network. That is where most of the
interesting behaviour lives anyway: a request that fails has to say so rather than render an
empty chain.

`tests-live/` is driven by the Qt-MCP framework and does **not** launch anything itself —
point it at a binary that starts the app with the QML inspector
(`just test-live-with ./run-standalone`). It walks Tx → Account → Zone with Back and Forward,
and asserts after every navigation that the router reports no page-load error — the assertion that caught `TxPage`
shadowing `QQuickItem`'s FINAL `z` property, which had stopped that page loading in every build.
It is deliberately **outside** `tests/`. The builder globs every `.mjs` in `tests/`
into the sandboxed check, so a network-dependent suite placed there fails every build. It is
separate because the detail routes cannot be reached any other way: the inspector can click,
read the tree and query properties, but it cannot type into the search field or call a QML
method — so the only way onto a Zone, Tx or Account page is to click a real row. CI does not run it:
reaching those routes needs a Basecamp or standalone binary that CI has no access to, and a job
that always failed would be worse than no job.

## Licence

Dual-licensed under [MIT](LICENSE-MIT) or [Apache 2.0](LICENSE-APACHE-v2), at your option.
