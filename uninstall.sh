#!/usr/bin/env bash
set -euo pipefail

HAM_DIR="$HOME/.hammerspoon"
TARGET_MODULE="$HAM_DIR/clipboard_winv.lua"
INIT_FILE="$HAM_DIR/init.lua"
REQUIRE_LINE='require("clipboard_winv")'

rm -f "$TARGET_MODULE"

if [[ -f "$INIT_FILE" ]]; then
  tmp_file="$(mktemp)"
  grep -Fvx "$REQUIRE_LINE" "$INIT_FILE" > "$tmp_file" || true
  mv "$tmp_file" "$INIT_FILE"
fi

echo "Uninstalled clipboard_winv.lua"
