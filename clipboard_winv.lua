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
  showHelpOverlay = false,
  helpOverlaySeconds = 2.4,
  helpOverlayEdge = 1,
  showStatusPanel = true,
  statusPanelWidth = 420,
  statusPanelHeight = 206,
  statusPanelMargin = 16,
  statusPanelPosition = "bottomRight", -- bottomRight | topRight
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
  togglePanel = "cmd+shift+h",
}

local history = {}
local chooser
local actionChooser
local hotkeyChooser
local lastChangeCount = hs.pasteboard.changeCount()
local lastFocusedApp
local chooserMode = "paste"
local menubar
local optionsMenu
local updateMenuBar
local hotkeys = {}
local boundHotkeys = {}
local bindHotkeys
local showHotkeyChooser
local hotkeyCaptureTap
local activeHelpAlertId
local statusPanel
local screenWatcher
local updateStatusPanel
local hideAllChoosers

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

local function statusPanelFrame()
  local screenFrame = hs.screen.mainScreen():frame()
  local w = config.statusPanelWidth
  local h = config.statusPanelHeight
  local x = screenFrame.x + screenFrame.w - w - config.statusPanelMargin
  local y = screenFrame.y + screenFrame.h - h - config.statusPanelMargin

  if config.statusPanelPosition == "topRight" then
    y = screenFrame.y + config.statusPanelMargin
  end

  return { x = x, y = y, w = w, h = h }
end

local function statusPanelText()
  local historyHotkey = defaultHotkeys.openHistory .. " (fixed)"
  if hotkeys.openHistory and hotkeys.openHistory ~= defaultHotkeys.openHistory then
    historyHotkey = historyHotkey .. " / " .. hotkeys.openHistory
  end
  return table.concat({
    "CopyHammer",
    string.format("History: %d items | %s file | %d chars", #history, formatBytes(historyFileSize()), totalChars()),
    "",
    "Current Hotkeys",
    string.format("History: %s", historyHotkey),
    string.format("Actions: %s", hotkeys.openActions or "-"),
    string.format("Delete One: %s", hotkeys.deleteMode or "-"),
    string.format("Copy All: %s", hotkeys.copyAll or "-"),
    string.format("Clear All: %s", hotkeys.clearAll or "-"),
    string.format("Hotkey Settings: %s", hotkeys.hotkeyConfig or "-"),
    string.format("Toggle Panel: %s", hotkeys.togglePanel or "-"),
  }, "\n")
end

-- Keep panel in sync with the active chooser window (show/hide together)
local uiVisible = false
local uiHideTimer
local function setUIVisible(visible)
  if uiHideTimer then
    uiHideTimer:stop()
    uiHideTimer = nil
  end

  if visible then
    uiVisible = true
    if updateStatusPanel then
      updateStatusPanel()
    end
    return
  end

  -- Small debounce to prevent flicker when switching choosers (actions -> hotkeys, etc.)
  uiHideTimer = hs.timer.doAfter(0.08, function()
    uiVisible = false
    uiHideTimer = nil
    if updateStatusPanel then
      updateStatusPanel()
    end
  end)
end

hideAllChoosers = function()
  if chooser then
    chooser:hide()
  end
  if actionChooser then
    actionChooser:hide()
  end
  if hotkeyChooser then
    hotkeyChooser:hide()
  end
  setUIVisible(false)
end

local function ensureStatusPanel()
  if not config.showStatusPanel or not uiVisible then
    if statusPanel then
      statusPanel:hide()
    end
    return
  end

  local frame = statusPanelFrame()
  if not statusPanel then
    statusPanel = hs.canvas.new(frame)
    statusPanel:level(hs.canvas.windowLevels.floating)
    statusPanel:behaviorAsLabels({ "canJoinAllSpaces", "stationary" })
    if statusPanel.canvasMouseEvents then
      statusPanel:canvasMouseEvents(false, false, true, false) -- down/up only
    end
    if statusPanel.clickActivating then
      statusPanel:clickActivating(false)
    end
    if statusPanel.mouseCallback then
      statusPanel:mouseCallback(function(_, msg)
        if msg == "mouseUp" then
          -- Click the panel to dismiss the whole UI (chooser + panel)
          if hideAllChoosers then
            hideAllChoosers()
          else
            setUIVisible(false)
          end
        end
      end)
    end
    statusPanel[1] = {
      type = "rectangle",
      action = "fill",
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
      fillColor = { white = 0, alpha = 0.72 },
    }
    statusPanel[2] = {
      type = "rectangle",
      action = "stroke",
      roundedRectRadii = { xRadius = 10, yRadius = 10 },
      strokeColor = { white = 1, alpha = 0.18 },
      strokeWidth = 1,
    }
    statusPanel[3] = {
      type = "text",
      frame = { x = 12, y = 10, w = frame.w - 24, h = frame.h - 20 },
      text = "",
      textSize = 12,
      textColor = { white = 1, alpha = 0.95 },
      textFont = ".AppleSystemUIFont",
      textAlignment = "left",
      textLineBreak = "wordWrap",
    }
  end

  statusPanel:frame(frame)
  statusPanel[3].frame = { x = 12, y = 10, w = frame.w - 24, h = frame.h - 20 }
  statusPanel[3].text = statusPanelText()
  statusPanel:show()
end

local function showHelpOverlay(text)
  if not config.showHelpOverlay then
    return
  end

  if activeHelpAlertId then
    hs.alert.closeSpecific(activeHelpAlertId, 0)
    activeHelpAlertId = nil
  end

  activeHelpAlertId = hs.alert.show(
    text,
    {
      textSize = 12,
      radius = 8,
      padding = 10,
      fillColor = { white = 0, alpha = 0.75 },
      strokeColor = { white = 1, alpha = 0.15 },
      strokeWidth = 1,
      textColor = { white = 1, alpha = 0.95 },
      atScreenEdge = config.helpOverlayEdge,
      fadeInDuration = 0.08,
      fadeOutDuration = 0.12,
    },
    hs.screen.mainScreen(),
    config.helpOverlaySeconds
  )
end

local function showUsageHint(context)
  if context == "history" then
    showHelpOverlay(string.format(
      "History: %s  |  Actions: %s  |  Hotkeys: %s",
      defaultHotkeys.openHistory,
      hotkeys.openActions,
      hotkeys.hotkeyConfig
    ))
  elseif context == "actions" then
    showHelpOverlay(string.format(
      "Actions: %s  |  Delete: %s  |  Copy All: %s  |  Clear: %s",
      hotkeys.openActions,
      hotkeys.deleteMode,
      hotkeys.copyAll,
      hotkeys.clearAll
    ))
  elseif context == "delete" then
    showHelpOverlay("Delete mode: click one item to remove")
  elseif context == "hotkeys" then
    showHelpOverlay("Select one action, then press your new key combo")
  end
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
local modifierLikeKeyNames = {
  command = true,
  rightcommand = true,
  leftcommand = true,
  shift = true,
  rightshift = true,
  leftshift = true,
  control = true,
  rightcontrol = true,
  leftcontrol = true,
  alt = true,
  option = true,
  rightoption = true,
  leftoption = true,
  ["function"] = true,
  fn = true,
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

local function specFromFlagsAndKey(flags, key)
  local parts = {}
  for _, m in ipairs(modOrder) do
    if flags[m] then
      table.insert(parts, m)
    end
  end
  table.insert(parts, key)
  return table.concat(parts, "+")
end

local function actionTitle(actionId)
  local titles = {
    openHistory = "Open History",
    openActions = "Open Actions Window",
    deleteMode = "Delete One",
    copyAll = "Copy All",
    clearAll = "Clear All",
    hotkeyConfig = "Hotkey Settings",
    togglePanel = "Toggle Panel",
  }
  return titles[actionId] or actionId
end

local function sanitizeHotkeys()
  local used = {}
  local changed = false
  local _, _, _, reservedHistory = parseHotkeySpec(defaultHotkeys.openHistory)

  for actionId, defaultSpec in pairs(defaultHotkeys) do
    local current = hotkeys[actionId]
    local _, _, err, normalized = parseHotkeySpec(current or "")
    if err then
      hotkeys[actionId] = defaultSpec
      current = defaultSpec
      _, _, _, normalized = parseHotkeySpec(current)
      changed = true
    else
      hotkeys[actionId] = normalized
    end

    if actionId ~= "openHistory" and hotkeys[actionId] == reservedHistory then
      hotkeys[actionId] = defaultSpec
      changed = true
    end

    local owner = used[hotkeys[actionId]]
    if owner then
      hotkeys[actionId] = defaultSpec
      changed = true
    end
    used[hotkeys[actionId]] = actionId
  end

  return changed
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

  if sanitizeHotkeys() then
    saveHotkeys()
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
  if updateStatusPanel then
    updateStatusPanel()
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
      if updateStatusPanel then
        updateStatusPanel()
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

local function resetHotkeysToDefault()
  for k, v in pairs(defaultHotkeys) do
    hotkeys[k] = v
  end
  saveHotkeys()
  if bindHotkeys then
    bindHotkeys()
  end
  hs.alert.show("Hotkeys reset to defaults")
end

-- Exposed helpers in Hammerspoon console:
--   clearClipboardHistory()
--   showClipboardMemoryUsage()
--   copyAllClipboardHistory()
_G.clearClipboardHistory = clearHistory
_G.showClipboardMemoryUsage = printMemoryUsage
_G.copyAllClipboardHistory = copyAllHistory
_G.resetClipboardHotkeys = resetHotkeysToDefault
_G.toggleClipboardStatusPanel = function()
  config.showStatusPanel = not config.showStatusPanel
  if updateStatusPanel then
    updateStatusPanel()
  end
  hs.printf("Clipboard status panel: %s", config.showStatusPanel and "ON" or "OFF")
end
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
  if updateStatusPanel then
    updateStatusPanel()
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
      setUIVisible(false)
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
  setUIVisible(true)
  chooser:show(chooserPoint(config.chooserWidth))
  printMemoryUsage()
end

local function showChooser()
  openChooser("paste")
  showUsageHint("history")
end

local function showDeleteChooser()
  openChooser("delete")
  showUsageHint("delete")
end

local function showActionChooser()
  if not actionChooser then
    actionChooser = hs.chooser.new(function(choice)
      setUIVisible(false)
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
  setUIVisible(true)
  actionChooser:show(chooserPoint(config.chooserWidth))
  showUsageHint("actions")
end

local hotkeyMeta = {
  { id = "openHistory", title = "Open History (Extra)", help = "Extra hotkey (cmd+shift+v is always available)" },
  { id = "openActions", title = "Open Actions Window", help = "Show action window" },
  { id = "deleteMode", title = "Delete One Mode", help = "Open delete chooser" },
  { id = "copyAll", title = "Copy All Items", help = "Copy all saved entries" },
  { id = "clearAll", title = "Clear All Items", help = "Clear whole history" },
  { id = "hotkeyConfig", title = "Hotkey Settings", help = "Open hotkey config" },
  { id = "togglePanel", title = "Toggle Status Panel", help = "Show/hide persistent panel" },
}

local function findHotkeyMeta(id)
  for _, item in ipairs(hotkeyMeta) do
    if item.id == id then
      return item
    end
  end
  return nil
end

local function stopHotkeyCapture()
  if hotkeyCaptureTap then
    hotkeyCaptureTap:stop()
    hotkeyCaptureTap = nil
  end
end

local function startHotkeyCapture(actionId)
  local meta = findHotkeyMeta(actionId)
  if not meta then
    return
  end

  stopHotkeyCapture()
  showHelpOverlay(string.format("%s: press new hotkey now (ESC to cancel)", meta.title))

  hotkeyCaptureTap = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
    local keyName = hs.keycodes.map[event:getKeyCode()]
    if type(keyName) ~= "string" then
      return false
    end

    keyName = keyName:lower()
    if keyName == "escape" then
      stopHotkeyCapture()
      hs.alert.show("Hotkey update cancelled", { atScreenEdge = config.helpOverlayEdge, textSize = 12 }, hs.screen.mainScreen(), 1.0)
      hs.timer.doAfter(0.03, showHotkeyChooser)
      return true
    end

    if modifierLikeKeyNames[keyName] then
      return true
    end

    local flags = event:getFlags()
    local spec = specFromFlagsAndKey(flags, keyName)
    local _, _, err, normalized = parseHotkeySpec(spec)
    if err then
      hs.alert.show("Invalid hotkey: " .. err, { atScreenEdge = config.helpOverlayEdge, textSize = 12 }, hs.screen.mainScreen(), 1.2)
      return true
    end

    local _, _, _, reservedHistory = parseHotkeySpec(defaultHotkeys.openHistory)
    if actionId ~= "openHistory" and normalized == reservedHistory then
      hs.alert.show("Reserved for History: " .. reservedHistory, { atScreenEdge = config.helpOverlayEdge, textSize = 12 }, hs.screen.mainScreen(), 1.2)
      return true
    end

    for otherAction, otherSpec in pairs(hotkeys) do
      if otherAction ~= actionId and otherSpec == normalized then
        hs.alert.show(
          string.format("Already used by %s", actionTitle(otherAction)),
          { atScreenEdge = config.helpOverlayEdge, textSize = 12 },
          hs.screen.mainScreen(),
          1.2
        )
        return true
      end
    end

    hotkeys[actionId] = normalized
    saveHotkeys()
    bindHotkeys()
    if updateStatusPanel then
      updateStatusPanel()
    end
    stopHotkeyCapture()
    hs.alert.show(meta.title .. ": " .. normalized, { atScreenEdge = config.helpOverlayEdge, textSize = 12 }, hs.screen.mainScreen(), 1.2)
    hs.timer.doAfter(0.03, showHotkeyChooser)
    return true
  end)

  hotkeyCaptureTap:start()
end

showHotkeyChooser = function()
  if not hotkeyChooser then
    hotkeyChooser = hs.chooser.new(function(choice)
      setUIVisible(false)
      if not choice then
        return
      end

      if choice.action == "restore_defaults" then
        resetHotkeysToDefault()
        hs.timer.doAfter(0.03, showHotkeyChooser)
      else
        startHotkeyCapture(choice.id)
      end
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
  setUIVisible(true)
  hotkeyChooser:show(chooserPoint(config.chooserWidth))
  showUsageHint("hotkeys")
end

local actionHandlers = {
  openHistory = showChooser,
  openActions = showActionChooser,
  deleteMode = showDeleteChooser,
  copyAll = copyAllHistory,
  clearAll = function() clearHistory("manual clear hotkey") end,
  hotkeyConfig = showHotkeyChooser,
  togglePanel = function()
    _G.toggleClipboardStatusPanel()
  end,
}

bindHotkeys = function()
  if sanitizeHotkeys() then
    saveHotkeys()
  end

  local _, _, _, reservedHistory = parseHotkeySpec(defaultHotkeys.openHistory)

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

  local reservedIsBound = false
  for _, spec in pairs(hotkeys) do
    if spec == reservedHistory then
      reservedIsBound = true
      break
    end
  end
  if not reservedIsBound then
    local mods, key = parseHotkeySpec(reservedHistory)
    boundHotkeys.primaryHistory = hs.hotkey.bind(mods, key, showChooser)
  end
  if not boundHotkeys.openHistory then
    -- As long as history has a hotkey bound, we are fine (cmd+shift+v is always active as "fixed").
    hotkeys.openHistory = defaultHotkeys.openHistory
    saveHotkeys()
    hs.printf("Clipboard history: restored openHistory to default %s", defaultHotkeys.openHistory)
  end

  if updateStatusPanel then
    updateStatusPanel()
  end
end

updateMenuBar = function()
  if not menubar then
    return
  end
  menubar:setTitle(string.format("OPT %s", formatBytes(historyFileSize())))
end

updateStatusPanel = function()
  ensureStatusPanel()
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

  optionsMenu = hs.menubar.new(false)
  if optionsMenu then
    optionsMenu:setMenu(function()
      return {
        { title = string.format("File: %s", formatBytes(historyFileSize())), disabled = true },
        { title = string.format("Memory: %d chars (~%s)", totalChars(), formatChars(totalChars())), disabled = true },
        { title = string.format("Items: %d/%d", #history, config.maxItems), disabled = true },
        { title = "-" },
        { title = string.format("Open History (%s)", defaultHotkeys.openHistory), fn = showChooser },
        { title = string.format("Open Actions Window (%s)", hotkeys.openActions), fn = showActionChooser },
        { title = string.format("Hotkey Settings (%s)", hotkeys.hotkeyConfig), fn = showHotkeyChooser },
        { title = "Reset Hotkeys to Default", fn = resetHotkeysToDefault },
        { title = "-" },
        {
          title = "Status Panel (Bottom Right)",
          checked = config.showStatusPanel and config.statusPanelPosition == "bottomRight",
          fn = function()
            config.showStatusPanel = true
            config.statusPanelPosition = "bottomRight"
            updateStatusPanel()
          end,
        },
        {
          title = "Status Panel (Top Right)",
          checked = config.showStatusPanel and config.statusPanelPosition == "topRight",
          fn = function()
            config.showStatusPanel = true
            config.statusPanelPosition = "topRight"
            updateStatusPanel()
          end,
        },
        {
          title = "Hide Status Panel",
          checked = not config.showStatusPanel,
          fn = function()
            config.showStatusPanel = false
            updateStatusPanel()
          end,
        },
        { title = "-" },
        {
          title = "Help Overlay (Top)",
          checked = config.showHelpOverlay and config.helpOverlayEdge == 1,
          fn = function()
            config.showHelpOverlay = true
            config.helpOverlayEdge = 1
            showHelpOverlay("Help overlay position: top")
          end,
        },
        {
          title = "Help Overlay (Bottom)",
          checked = config.showHelpOverlay and config.helpOverlayEdge == 2,
          fn = function()
            config.showHelpOverlay = true
            config.helpOverlayEdge = 2
            showHelpOverlay("Help overlay position: bottom")
          end,
        },
        {
          title = "Disable Help Overlay",
          checked = not config.showHelpOverlay,
          fn = function()
            config.showHelpOverlay = false
            if activeHelpAlertId then
              hs.alert.closeSpecific(activeHelpAlertId, 0)
              activeHelpAlertId = nil
            end
          end,
        },
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

  menubar:setTooltip("CopyHammer: click to show chooser+panel, click again to hide panel. Option-click for menu.")
  menubar:setClickCallback(function(mods)
    if mods and mods.alt and optionsMenu then
      local f = menubar:frame()
      if f then
        optionsMenu:popupMenu({ x = f.x, y = f.y + f.h })
      else
        optionsMenu:popupMenu(hs.mouse.absolutePosition())
      end
      return
    end

    if uiVisible then
      hideAllChoosers()
      return
    end
    showChooser()
  end)

  updateMenuBar()
end

local function setupStatusPanel()
  updateStatusPanel()
  if not screenWatcher then
    screenWatcher = hs.screen.watcher.new(function()
      if updateStatusPanel then
        updateStatusPanel()
      end
    end)
    screenWatcher:start()
  end
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
setupStatusPanel()
startClipboardMonitor()
bindHotkeys()

hs.printf(
  "Clipboard history ready. Hotkeys: %s (history, fixed), %s (actions), %s (hotkey settings), %s (toggle panel)",
  defaultHotkeys.openHistory,
  hotkeys.openActions,
  hotkeys.hotkeyConfig,
  hotkeys.togglePanel
)
printMemoryUsage()
