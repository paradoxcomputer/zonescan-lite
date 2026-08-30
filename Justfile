default: build

# Build the ui_qml module plugin via logos-module-builder (-> result/lib/).
build:
    nix build

# Preview the UI standalone (ui_qml modules run via the builder).
run:
    nix run .

# Package the installable bundle (-> result-lgx/*.lgx).
lgx:
    nix build .#lgx -o result-lgx
    @ls -la result-lgx/

# Run the Qt-MCP integration suite (sandboxed, no network).
test:
    nix flake check --print-build-logs

# Run the sandboxed suite against a local build, for iterating on tests.
test-local:
    nix build .#test-framework -o result-mcp
    nix build
    node tests/ui-tests.mjs

# sitometres stages into a throwaway Basecamp and HOME, so it never touches your install.
# Drive the real app against the spec (13 steps; needs network and a reachable zonescan).
test-app:
    sitometres run sitometres.yaml

# Click through the app with no spec, to see what a crawl makes of it.
smoke:
    sitometres

# It does NOT launch anything: point it at a binary that starts the app with the QML
# inspector, e.g. a script exec'ing `logos-standalone-app -p <module>/lib`.
# Run the qt-mcp live suite (tests-live/) against that launcher.
test-live-with LAUNCHER:
    nix build .#test-framework -o result-mcp
    nix build
    node tests-live/ui-tests-live.mjs --ci {{LAUNCHER}}

# Syntax-check every QML file. Import warnings are expected outside the Basecamp host.
lint:
    #!/usr/bin/env bash
    set -euo pipefail
    nix shell nixpkgs#qt6.qtdeclarative -c bash -c '
      # dirname TWICE. qmllint lives at <qtdeclarative>/bin/qmllint and the QML modules at
      # <qtdeclarative>/lib/qt-6/qml; a third dirname yielded /nix/store, an import path that
      # resolves nothing. QtQuick was therefore unimportable and every rule that needs a
      # resolved type silently reported nothing - the gate only ever caught [syntax].
      qmldir=$(dirname $(dirname $(readlink -f $(command -v qmllint))))/lib/qt-6/qml
      fail=0
      for f in src/qml/Main.qml src/qml/pages/*.qml src/qml/components/*.qml src/qml/theme/*.qml; do
        out=$(qmllint -I "$qmldir" -I src/qml "$f" 2>&1 || true)
        if echo "$out" | grep -qE "\[syntax\]"; then echo "$f:"; echo "$out" | grep -E "\[syntax\]"; fail=1; fi
      done
      # src/qml/theme/ is held to a stricter gate than the rest of the tree, because the
      # singleton has a failure mode nothing else here has: a Settings or Loader written as a
      # BARE CHILD of QtObject does not warn at runtime, it fails the document at LOAD time and
      # takes all 24 importers down with it. qmllint reports exactly that as
      #   Cannot assign to non-existent default property [missing-property]
      # so [missing-property] and [import] are errors in this directory. Two allowlisted
      # patterns, both cosmetic and both verified correct at runtime:
      #   QQmlSettings  - qmllint cannot see properties declared inside a Settings block
      #   Logos.Theme   - HostThemeProbe is MEANT to fail that import outside Basecamp; the
      #                   Loader in ZTheme.qml is what contains it
      for f in src/qml/theme/*.qml; do
        out=$(qmllint -I "$qmldir" -I src/qml "$f" 2>&1 || true)
        strict=$(echo "$out" | grep -E "\[(missing-property|import)\]" \
                             | grep -v "QQmlSettings" | grep -v "Logos.Theme" || true)
        if [ -n "$strict" ]; then echo "$f:"; echo "$strict"; fail=1; fi
      done
      # QT VERSION SKEW - the reason this check is a grep and not a lint rule.
      # This recipe lints with whatever qmllint nix shell nixpkgs#qt6.qtdeclarative hands it
      # (6.11.1 at the time of writing). Basecamp runs Qt 6.9.2. The word public used as a BARE
      # object-literal key is accepted by 6.11 and is a [syntax] error in 6.9 - Expected token
      # rbrace - which made the whole ZTheme singleton fail to compile inside the host
      # (Type ZTheme unavailable, taking all 24 importers down with it) while every gate here
      # stayed green. Only launching the real app found it. public and import are the two words
      # the two parsers disagree about; quoted, both are happy. theme.js is exempt on purpose:
      # a .js file goes through a different, permissive parser and has always used bare public.
      res=$(grep -rnE "(^|[({,[:space:]])(public|import)[[:space:]]*:" src/qml --include="*.qml" || true)
      if [ -n "$res" ]; then
        echo "$res"
        echo "^ reserved word as a BARE object-literal key. Quote it: Qt 6.9.2 (what Basecamp runs) rejects it."
        fail=1
      fi
      [ $fail -eq 0 ] && echo "qmllint: clean (no [syntax]; theme/ also free of [missing-property]/[import]; no bare reserved-word keys)"
      exit $fail'

# Everything CI runs.
check: lint build test

clean:
    rm -rf build result result-* rocksdb-*

# Format the C++ backend.
prettify:
    nix shell nixpkgs#clang-tools -c clang-format -i src/*.cpp src/*.h
