# CopyHammer

A minimal Win+V-style clipboard history for macOS using only **Hammerspoon (Lua)**.

This is intentionally simple:

- One hotkey: `ctrl + shift + v`
- One list (Hammerspoon chooser)
- Text-only clipboard history (no images/files)

## Requirement

- macOS
- Hammerspoon (required)

Install Hammerspoon:

```bash
brew install --cask hammerspoon
```

## Install

One-line install:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/DD-Ching/CopyHammer/main/install.sh)"
```

Or clone this repo and run:

```bash
./install.sh
```

This script:

- Copies `clipboard_winv.lua` to `~/.hammerspoon/clipboard_winv.lua`
- Ensures `require("clipboard_winv")` is present in `~/.hammerspoon/init.lua`

Then open Hammerspoon and click `Reload Config`.

## Usage

- `ctrl + shift + v`: open clipboard history (Win+V equivalent)

The chooser shows:

- `Copy All Items`: copies all history entries (newline-separated)
- `Clear All Items`: clears history
- `Delete One Item...`: enter delete mode (click an item to remove it)
- Clipboard items: click to copy back to clipboard (and auto-paste if enabled)

## Notes

- **Text-only**: if you copy files/images, they won't appear.
- The chooser does **not** show `cmd+1..cmd+9` shortcuts (disabled by default).

## Customize

Edit `~/.hammerspoon/clipboard_winv.lua` (or `~/.hammerspoon/init.lua` if you pasted the script directly):

- `maxItems`
- `maxChars`
- `previewChars`
- `pollInterval`
- `autoPasteOnSelect`

## Console Helpers

In Hammerspoon Console:

```lua
clearClipboardHistory()
showClipboardMemoryUsage()
```
