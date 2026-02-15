-- Minimal clipboard history for Hammerspoon (personal use)

local config = {
  pollInterval = 0.5,
  maxItems = 30,
  maxChars = 100000,
  previewChars = 80,
  autoPasteOnSelect = true,
  showMenubarUsage = true,
  chooserWidth = 42,
  chooserRows = 12,
  chooserMargin = 16,
  historyFile = os.getenv("HOME") .. "/.hammerspoon/clipboard.json",
  hotkeyFile = os.getenv("HOME") .. "/.hammerspoon/clipboard_hotkeys.json",
}

local defaultHotkeys = {
  openHistory = "cmd+shift+v",
  openActions = "cmd+shift+a",
  deleteMode = "cmd+ctrl+shift+v",
  copyAll = "cmd+ctrl+shift+c",
  clearAll = "cmd+shift+delete",
  hotkeyConfig = "cmd+shift+k",
}

local history = {}
local chooser
local actionChooser
local hotkeyChooser
local lastChangeCount = hs.pasteboard.changeCount()
local lastFocusedApp
local chooserMode = "paste"
local menubar
local menuButton
local updateMenuBar
local hotkeys = {}
local boundHotkeys = {}
local bindHotkeys
local showHotkeyChooser

-- Sum of characters across stored entries (approx memory usage)
local function totalChars()
  local n = 0
  for _, item in ipairs(history) do
    n = n + #item
  end
  return n
end

local function printMemoryUsage()
  hs.printf("Clipboard history memory: %d chars (%d items)", totalChars(), #history)
end

local function formatChars(n)
  if n >= 1000000 then
    return string.format("%.1fM", n / 1000000)
  end
  if n >= 1000 then
    return string.format("%.1fK", n / 1000)
  end
  return tostring(n)
end

local function formatBytes(n)
  if n >= 1024 * 1024 * 1024 then
    return string.format("%.1fGB", n / (1024 * 1024 * 1024))
  end
  if n >= 1024 * 1024 then
    return string.format("%.1fMB", n / (1024 * 1024))
  end
  if n >= 1024 then
    return string.format("%.1fKB", n / 1024)
  end
  return string.format("%dB", n)
end

local function historyFileSize()
  local attr = hs.fs.attributes(config.historyFile)
  if type(attr) == "table" and type(attr.size) == "number" then
    return attr.size
  end
  return 0
end

local function chooserPoint(widthPercent)
  local screenFrame = hs.screen.mainScreen():frame()
  local width = math.floor(screenFrame.w * (widthPercent / 100))
  local x = screenFrame.x + screenFrame.w - width - config.chooserMargin
  local y = screenFrame.y + config.chooserMargin
  return { x = x, y = y }
end

local function canUseAutoLaunch()
  return hs.autoLaunch and hs.autoLaunch.get and hs.autoLaunch.set
end

local function getAutoLaunch()
  if canUseAutoLaunch() then
    return hs.autoLaunch.get()
  end
  return false
end

local function setAutoLaunch(enabled)
  if canUseAutoLaunch() then
    hs.autoLaunch.set(enabled)
    return true
  end
  hs.printf("Clipboard history: hs.autoLaunch not available in this version")
  return false
end

-- Persist history as JSON
local function saveHistory()
  local encoded = hs.json.encode(history)
  if not encoded then
    hs.printf("Clipboard history: failed to encode JSON")
    return
  end

  local f, err = io.open(config.historyFile, "w")
  if not f then
    hs.printf("Clipboard history: failed to save (%s)", err or "unknown error")
    return
  end

  f:write(encoded)
  f:close()
end

local function saveHotkeys()
  local encoded = hs.json.encode(hotkeys)
  if not encoded then
    hs.printf("Clipboard history: failed to encode hotkeys JSON")
    return
  end

  local f, err = io.open(config.hotkeyFile, "w")
  if not f then
    hs.printf("Clipboard history: failed to save hotkeys (%s)", err or "unknown error")
    return
  end

  f:write(encoded)
  f:close()
end

local modOrder = { "cmd", "ctrl", "alt", "shift", "fn" }
local modAlias = {
  command = "cmd",
  option = "alt",
  control = "ctrl",
  ctl = "ctrl",
}

local function parseHotkeySpec(spec)
  if type(spec) ~= "string" then
    return nil, nil, "must be a string"
  end

  local s = spec:lower():gsub("%s+", "")
  if s == "" then
    return nil, nil, "empty hotkey"
  end

  local modSet = {}
  local key

  for part in s:gmatch("[^+]+") do
    local token = modAlias[part] or part
    if token == "cmd" or token == "ctrl" or token == "alt" or token == "shift" or token == "fn" then
      modSet[token] = true
    else
      if key then
        return nil, nil, "only one key is allowed"
      end
      key = token
    end
  end

  if not key then
    return nil, nil, "missing key"
  end

  local mods = {}
  for _, m in ipairs(modOrder) do
    if modSet[m] then
      table.insert(mods, m)
    end
  end

  local parts = {}
  for _, m in ipairs(mods) do
    table.insert(parts, m)
  end
  table.insert(parts, key)

  return mods, key, nil, table.concat(parts, "+")
end

local function loadHotkeys()
  hotkeys = {}
  for k, v in pairs(defaultHotkeys) do
    hotkeys[k] = v
  end

  local f = io.open(config.hotkeyFile, "r")
  if not f then
    return
  end

  local raw = f:read("*a")
  f:close()

  local decoded = hs.json.decode(raw)
  if type(decoded) ~= "table" then
    return
  end

  for action, value in pairs(decoded) do
    if type(value) == "string" and defaultHotkeys[action] then
      local _, _, err, normalized = parseHotkeySpec(value)
      if not err then
        hotkeys[action] = normalized
      end
    end
  end
end

-- Manual clear function (also exposed globally for console use)
local function clearHistory(reason)
  history = {}
  saveHistory()
  hs.printf("Clipboard history cleared%s", reason and (" (" .. reason .. ")") or "")
  printMemoryUsage()
  if updateMenuBar then
    updateMenuBar()
  end
end

local function removeOneItem(text)
  for i, item in ipairs(history) do
    if item == text then
      table.remove(history, i)
      saveHistory()
      hs.printf("Clipboard history: removed 1 item")
      printMemoryUsage()
      if updateMenuBar then
        updateMenuBar()
      end
      return true
    end
  end
  return false
end

local function copyAllHistory()
  if #history == 0 then
    hs.printf("Clipboard history: nothing to copy")
    return
  end
  local merged = table.concat(history, "\n")
  hs.pasteboard.setContents(merged)
  hs.printf("Clipboard history: copied all %d items (%d chars)", #history, #merged)
end

-- Exposed helpers in Hammerspoon console:
--   clearClipboardHistory()
--   showClipboardMemoryUsage()
--   copyAllClipboardHistory()
_G.clearClipboardHistory = clearHistory
_G.showClipboardMemoryUsage = printMemoryUsage
_G.copyAllClipboardHistory = copyAllHistory
_G.toggleClipboardAutoLaunch = function()
  if setAutoLaunch(not getAutoLaunch()) then
    if updateMenuBar then
      updateMenuBar()
    end
    hs.printf("Hammerspoon auto launch: %s", getAutoLaunch() and "ON" or "OFF")
  end
end

-- Load history from JSON file if present
local function loadHistory()
  local f = io.open(config.historyFile, "r")
  if not f then
    return
  end

  local raw = f:read("*a")
  f:close()

  local decoded = hs.json.decode(raw)
  if type(decoded) ~= "table" then
    return
  end

  local seen = {}
  for _, item in ipairs(decoded) do
    if type(item) == "string" and item ~= "" and not seen[item] then
      seen[item] = true
      table.insert(history, item)
    end
  end

  while #history > config.maxItems do
    table.remove(history)
  end

  if totalChars() > config.maxChars then
    clearHistory("exceeded maxChars on startup")
  end
end

-- Insert newest at front, dedupe, enforce max size and max total chars
local function addToHistory(text)
  if type(text) ~= "string" or text == "" then
    return
  end

  for i, item in ipairs(history) do
    if item == text then
      table.remove(history, i)
      break
    end
  end

  table.insert(history, 1, text)

  while #history > config.maxItems do
    table.remove(history)
  end

  if totalChars() > config.maxChars then
    clearHistory("exceeded maxChars")
    return
  end

  saveHistory()
  printMemoryUsage()
  if updateMenuBar then
    updateMenuBar()
  end
end

-- Normalize preview to one line and truncate to configured length
local function preview(text)
  local s = text:sub(1, config.previewChars):gsub("[%c]+", " "):gsub("%s+", " ")
  if #text > config.previewChars then
    return s .. "..."
  end
  return s
end

local function openChooser(mode)
  if not chooser then
    chooser = hs.chooser.new(function(choice)
      if not choice then
        return
      end

      if chooserMode == "delete" then
        removeOneItem(choice.full)
        return
      end

      hs.pasteboard.setContents(choice.full)
      if config.autoPasteOnSelect then
        hs.timer.doAfter(0.08, function()
          if lastFocusedApp and lastFocusedApp:isRunning() then
            lastFocusedApp:activate()
          end
          hs.eventtap.keyStroke({ "cmd" }, "v")
        end)
      end
    end)
    chooser:searchSubText(true)
    chooser:width(config.chooserWidth)
    chooser:rows(config.chooserRows)
  end

  chooserMode = mode or "paste"
  lastFocusedApp = hs.application.frontmostApplication()

  local choices = {}
  for i, item in ipairs(history) do
    table.insert(choices, {
      text = preview(item),
      subText = string.format("#%d  %d chars%s", i, #item, chooserMode == "delete" and "  (click to delete)" or ""),
      full = item,
    })
  end

  local placeholder = chooserMode == "delete" and "Delete mode: pick an item to remove" or "Clipboard history"
  chooser:placeholderText(placeholder)
  chooser:choices(choices)
  chooser:show(chooserPoint(config.chooserWidth))
  printMemoryUsage()
end

local function showChooser()
  openChooser("paste")
end

local function showDeleteChooser()
  openChooser("delete")
end

local function showActionChooser()
  if not actionChooser then
    actionChooser = hs.chooser.new(function(choice)
      if not choice then
        return
      end
      if choice.action == "copy_all" then
        copyAllHistory()
      elseif choice.action == "clear_all" then
        clearHistory("manual clear from action window")
      elseif choice.action == "delete_mode" then
        showDeleteChooser()
      elseif choice.action == "open_history" then
        showChooser()
      elseif choice.action == "open_hotkeys" then
        showHotkeyChooser()
      end
    end)
    actionChooser:width(config.chooserWidth)
    actionChooser:rows(8)
  end

  actionChooser:placeholderText("Clipboard actions")
  actionChooser:choices({
    { text = "Open Clipboard History", subText = "Show copied items list", action = "open_history" },
    { text = "Copy All Items", subText = "Copy whole history into clipboard (newline-separated)", action = "copy_all" },
    { text = "Clear All Items", subText = "Delete every history item", action = "clear_all" },
    { text = "Delete One Item...", subText = "Open delete mode and pick one", action = "delete_mode" },
    { text = "Configure Hotkeys...", subText = "Open hotkey settings window", action = "open_hotkeys" },
  })
  actionChooser:show(chooserPoint(config.chooserWidth))
end

local hotkeyMeta = {
  { id = "openHistory", title = "Open History", help = "Show clipboard list" },
  { id = "openActions", title = "Open Actions Window", help = "Show action window" },
  { id = "deleteMode", title = "Delete One Mode", help = "Open delete chooser" },
  { id = "copyAll", title = "Copy All Items", help = "Copy all saved entries" },
  { id = "clearAll", title = "Clear All Items", help = "Clear whole history" },
  { id = "hotkeyConfig", title = "Hotkey Settings", help = "Open hotkey config" },
}

local function findHotkeyMeta(id)
  for _, item in ipairs(hotkeyMeta) do
    if item.id == id then
      return item
    end
  end
  return nil
end

showHotkeyChooser = function()
  if not hotkeyChooser then
    hotkeyChooser = hs.chooser.new(function(choice)
      if not choice then
        return
      end

      if choice.action == "restore_defaults" then
        for k, v in pairs(defaultHotkeys) do
          hotkeys[k] = v
        end
        saveHotkeys()
        bindHotkeys()
        hs.alert.show("Hotkeys restored")
      else
        local meta = findHotkeyMeta(choice.id)
        if not meta then
          return
        end
        local button, value = hs.dialog.textPrompt(
          "Set Hotkey",
          string.format("%s\nFormat: cmd+shift+v", meta.title),
          hotkeys[choice.id],
          "Save",
          "Cancel"
        )
        if button == "Save" then
          local _, _, err, normalized = parseHotkeySpec(value)
          if err then
            hs.alert.show("Invalid hotkey: " .. err)
          else
            hotkeys[choice.id] = normalized
            saveHotkeys()
            bindHotkeys()
            hs.alert.show(meta.title .. ": " .. normalized)
          end
        end
      end

      hs.timer.doAfter(0.03, showHotkeyChooser)
    end)
    hotkeyChooser:width(config.chooserWidth)
    hotkeyChooser:rows(10)
  end

  local choices = {}
  for _, item in ipairs(hotkeyMeta) do
    table.insert(choices, {
      text = item.title,
      subText = string.format("Current: %s  |  %s", hotkeys[item.id], item.help),
      id = item.id,
    })
  end
  table.insert(choices, {
    text = "Restore Default Hotkeys",
    subText = "Reset all hotkeys to original values",
    action = "restore_defaults",
  })

  hotkeyChooser:placeholderText("Hotkey settings")
  hotkeyChooser:choices(choices)
  hotkeyChooser:show(chooserPoint(config.chooserWidth))
end

local actionHandlers = {
  openHistory = showChooser,
  openActions = showActionChooser,
  deleteMode = showDeleteChooser,
  copyAll = copyAllHistory,
  clearAll = function() clearHistory("manual clear hotkey") end,
  hotkeyConfig = showHotkeyChooser,
}

bindHotkeys = function()
  for _, h in pairs(boundHotkeys) do
    h:delete()
  end
  boundHotkeys = {}

  for action, spec in pairs(hotkeys) do
    local fn = actionHandlers[action]
    if fn then
      local mods, key, err = parseHotkeySpec(spec)
      if err then
        hs.printf("Clipboard history: invalid hotkey for %s (%s)", action, err)
      else
        boundHotkeys[action] = hs.hotkey.bind(mods, key, fn)
      end
    end
  end
end

updateMenuBar = function()
  if not menubar then
    return
  end
  menubar:setTitle(formatBytes(historyFileSize()))
end

local function setupMenubar()
  if not config.showMenubarUsage then
    return
  end

  menubar = hs.menubar.new()
  if not menubar then
    hs.printf("Clipboard history: failed to create menubar item")
    return
  end

  menubar:setTooltip("Clipboard history (click to open)")
  menubar:setClickCallback(showChooser)

  menuButton = hs.menubar.new()
  if menuButton then
    menuButton:setTitle("OPT")
    menuButton:setTooltip("Clipboard settings")
    menuButton:setMenu(function()
      return {
        { title = string.format("File: %s", formatBytes(historyFileSize())), disabled = true },
        { title = string.format("Memory: %d chars (~%s)", totalChars(), formatChars(totalChars())), disabled = true },
        { title = string.format("Items: %d/%d", #history, config.maxItems), disabled = true },
        { title = "-" },
        { title = string.format("Open History (%s)", hotkeys.openHistory), fn = showChooser },
        { title = string.format("Open Actions Window (%s)", hotkeys.openActions), fn = showActionChooser },
        { title = string.format("Hotkey Settings (%s)", hotkeys.hotkeyConfig), fn = showHotkeyChooser },
        { title = "-" },
        { title = string.format("Delete One Item (%s)", hotkeys.deleteMode), fn = showDeleteChooser },
        { title = string.format("Copy All Items (%s)", hotkeys.copyAll), fn = copyAllHistory },
        { title = string.format("Clear All (%s)", hotkeys.clearAll), fn = function() clearHistory("manual clear") end },
        { title = "-" },
        {
          title = "Launch Hammerspoon at Login",
          checked = getAutoLaunch(),
          disabled = not canUseAutoLaunch(),
          fn = function()
            if setAutoLaunch(not getAutoLaunch()) then
              hs.printf("Hammerspoon auto launch: %s", getAutoLaunch() and "ON" or "OFF")
              updateMenuBar()
            end
          end,
        },
      }
    end)
  end

  updateMenuBar()
end

-- Idle-efficient polling using pasteboard changeCount
local function startClipboardMonitor()
  hs.timer.doEvery(config.pollInterval, function()
    local current = hs.pasteboard.changeCount()
    if current == lastChangeCount then
      return
    end

    lastChangeCount = current
    addToHistory(hs.pasteboard.getContents())
  end)
end

loadHistory()
loadHotkeys()
setupMenubar()
startClipboardMonitor()
bindHotkeys()

hs.printf(
  "Clipboard history ready. Hotkeys: %s (history), %s (actions), %s (hotkey settings)",
  hotkeys.openHistory,
  hotkeys.openActions,
  hotkeys.hotkeyConfig
)
printMemoryUsage()
