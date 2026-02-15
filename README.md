# CopyHammer

A minimal Win+V-style clipboard history for macOS using only Hammerspoon (Lua).

## Requirement

- macOS
- Hammerspoon (required)

Install Hammerspoon:

```bash
brew install --cask hammerspoon
```

## Features

- Clipboard history monitor via `NSPasteboard` change count
- In-memory history with duplicate removal
- FIFO limit (`maxItems`, default 30)
- Persist to `~/.hammerspoon/clipboard.json`
- Load persisted history on startup
- Auto-clear when total chars exceed `maxChars`
- Menubar file-size indicator (`B/KB/MB/GB`) for `~/.hammerspoon/clipboard.json`
- Click the size indicator to open clipboard chooser (same as `cmd + shift + v`)
- Extra `OPT` menubar item for settings/actions
- One-item delete mode
- Clear-all action
- Copy-all action (merge all history entries)
- Optional auto-paste after selecting an item

## Hotkeys

- `cmd + shift + v`: Open clipboard chooser
- `cmd + ctrl + shift + v`: Delete-one-item mode
- `cmd + ctrl + shift + c`: Copy all history items
- `cmd + shift + delete`: Clear all history

Inside chooser (`cmd + shift + v`), top actions are:

- `Copy All Items`
- `Clear All Items`
- `Delete One Item...`

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

## Uninstall

```bash
./uninstall.sh
```

## Auto Launch at Login

Use the menubar item `Launch Hammerspoon at Login`.

## Manual Console Commands

In Hammerspoon Console:

```lua
clearClipboardHistory()
showClipboardMemoryUsage()
copyAllClipboardHistory()
toggleClipboardAutoLaunch()
```

## Customize

Edit `~/.hammerspoon/clipboard_winv.lua`:

- `maxItems`
- `maxChars`
- `previewChars`
- `pollInterval`
- `autoPasteOnSelect`
- `showMenubarUsage`
- `showChooserActions`
