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
      qmldir=$(dirname $(dirname $(dirname $(readlink -f $(command -v qmllint)))))/lib/qt-6/qml
      fail=0
      for f in src/qml/Main.qml src/qml/pages/*.qml src/qml/components/*.qml; do
        out=$(qmllint -I "$qmldir" -I src/qml "$f" 2>&1 || true)
        if echo "$out" | grep -qE "\[syntax\]"; then echo "$f:"; echo "$out" | grep -E "\[syntax\]"; fail=1; fi
      done
      [ $fail -eq 0 ] && echo "qmllint: no syntax errors"
      exit $fail'

# Everything CI runs.
check: lint build test

clean:
    rm -rf build result result-* rocksdb-*

# Format the C++ backend.
prettify:
    nix shell nixpkgs#clang-tools -c clang-format -i src/*.cpp src/*.h
