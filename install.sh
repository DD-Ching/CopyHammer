#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HAM_DIR="$HOME/.hammerspoon"
TARGET_MODULE="$HAM_DIR/clipboard_winv.lua"
INIT_FILE="$HAM_DIR/init.lua"
REQUIRE_LINE='require("clipboard_winv")'
LOCAL_MODULE="$ROOT_DIR/clipboard_winv.lua"
REMOTE_MODULE_URL="https://raw.githubusercontent.com/DD-Ching/CopyHammer/main/clipboard_winv.lua"

if [[ ! -d "/Applications/Hammerspoon.app" && ! -d "$HOME/Applications/Hammerspoon.app" ]]; then
  echo "Hammerspoon is not installed."
  echo "Install first: brew install --cask hammerspoon"
  exit 1
fi

mkdir -p "$HAM_DIR"
if [[ -f "$LOCAL_MODULE" ]]; then
  cp "$LOCAL_MODULE" "$TARGET_MODULE"
elif command -v curl >/dev/null 2>&1; then
  curl -fsSL "$REMOTE_MODULE_URL" -o "$TARGET_MODULE"
else
  echo "clipboard_winv.lua not found locally and curl is unavailable."
  exit 1
fi

if [[ ! -f "$INIT_FILE" ]]; then
  printf "%s\n" "$REQUIRE_LINE" > "$INIT_FILE"
elif ! grep -Fq "$REQUIRE_LINE" "$INIT_FILE"; then
  printf "\n%s\n" "$REQUIRE_LINE" >> "$INIT_FILE"
fi

echo "Installed clipboard_winv.lua to $TARGET_MODULE"
echo "Next: open Hammerspoon -> Reload Config"
