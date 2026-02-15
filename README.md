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
- Single menubar button: `OPT <size>` (shows file size `B/KB/MB/GB` for `~/.hammerspoon/clipboard.json`)
- Click menubar button: show chooser + status panel (click again: hide panel)
- Option-click menubar button: open menu
- Chooser opens near top-right corner
- Separate **Actions window** (not mixed into clipboard item rows)
- Separate **Hotkey settings window** (press combo to record, persisted)
- Persistent **Status Panel** in right corner (always visible, non-disappearing)
- Click the status panel to hide it
- Auto-fallback if hotkey settings are invalid
- Hotkey duplicate prevention
- One-item delete mode
- Clear-all action
- Copy-all action
- Optional auto-paste after selecting an item
- Optional lightweight help overlay (top/bottom edge)

## Default Hotkeys

- `cmd + shift + v`: Open clipboard history
- `cmd + shift + a`: Open actions window
- `cmd + ctrl + shift + v`: Delete-one-item mode
- `cmd + ctrl + shift + c`: Copy all history items
- `cmd + shift + delete`: Clear all history
- `cmd + shift + k`: Open hotkey settings window
- `cmd + shift + h`: Toggle persistent status panel

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

Option-click the menubar button -> `Launch Hammerspoon at Login`.

## Hotkey Customization

Open hotkey settings window (`cmd + shift + k`), pick an action, then press your desired key combo directly.
Examples:

```text
cmd+shift+v
cmd+ctrl+shift+c
cmd+alt+v
```

Custom hotkeys are stored at:

- `~/.hammerspoon/clipboard_hotkeys.json`

Notes:

- `cmd + shift + v` is always reserved for **History** (fixed). Even if you change `openHistory`, `cmd + shift + v` still works.

If hotkeys become confusing:

- Use the menubar menu -> `Reset Hotkeys to Default`
- Or run in Hammerspoon console: `resetClipboardHotkeys()`

## Help Overlay

Menubar menu includes:

- `Help Overlay (Top)`
- `Help Overlay (Bottom)`
- `Disable Help Overlay`

## Persistent Status Panel

Menubar menu includes:

- `Status Panel (Bottom Right)`
- `Status Panel (Top Right)`
- `Hide Status Panel`

`OPT` means **Options**.

Console helper:

```lua
toggleClipboardStatusPanel()
```

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
- `chooserWidth`
- `chooserRows`
- `chooserMargin`
