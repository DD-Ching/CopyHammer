-- CopyHammer (Simple)
-- Win+V-style clipboard history for macOS using only Hammerspoon.
-- Note: Text-only history (non-text clipboard items can't be stored/restored).

local config = {
  pollInterval = 0.5,
  maxItems = 200,
  maxChars = 200000,
  previewChars = 80,
  autoPasteOnSelect = true,
  showChooserActions = true,
  disableChooserDefaultKeys = true, -- hides cmd+1..cmd+9 hints
  historyFile = os.getenv("HOME") .. "/.hammerspoon/clipboard.json",
}

local history = {}
local chooser
local chooserMode = "paste" -- paste | delete
local lastFocusedApp
local lastChangeCount = hs.pasteboard.changeCount()

local function totalChars()
  local n = 0
  for _, s in ipairs(history) do
    n = n + #s
  end
  return n
end

local function printMemoryUsage()
  hs.printf("CopyHammer: %d items, %d chars", #history, totalChars())
end

local function readPasteboardText()
  local s = hs.pasteboard.getContents()
  if type(s) == "string" and s ~= "" then
    return s
  end
  return nil
end

local function saveHistory()
  local encoded = hs.json.encode(history) or "[]"
  local f = io.open(config.historyFile, "w")
  if not f then
    return
  end
  f:write(encoded)
  f:close()
end

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

  while totalChars() > config.maxChars and #history > 0 do
    table.remove(history)
  end
end

local function addToHistory(text)
  if type(text) ~= "string" or text == "" then
    return false
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

  while totalChars() > config.maxChars and #history > 0 do
    table.remove(history)
  end

  saveHistory()
  return true
end

local function clearHistory(reason)
  history = {}
  saveHistory()
  hs.printf("CopyHammer: cleared%s", reason and (" (" .. reason .. ")") or "")
  printMemoryUsage()
end

local function removeOne(text)
  for i, item in ipairs(history) do
    if item == text then
      table.remove(history, i)
      saveHistory()
      hs.printf("CopyHammer: removed 1 item")
      printMemoryUsage()
      return true
    end
  end
  return false
end

local function copyAllHistory()
  if #history == 0 then
    hs.printf("CopyHammer: nothing to copy")
    return
  end
  hs.pasteboard.setContents(table.concat(history, "\n"))
  hs.printf("CopyHammer: copied all %d items", #history)
end

-- Reliable capture per pasteboard change (some apps update pasteboard content asynchronously)
local capture = { count = nil, retries = 0, timer = nil }

local function stopCapture()
  if capture.timer then
    capture.timer:stop()
    capture.timer = nil
  end
end

local function finishCapture()
  stopCapture()
  capture.count = nil
  capture.retries = 0
end

local function tryCapture()
  local s = readPasteboardText()
  if s then
    addToHistory(s)
    lastChangeCount = capture.count or lastChangeCount
    finishCapture()
    return
  end

  capture.retries = capture.retries - 1
  if capture.retries <= 0 then
    lastChangeCount = capture.count or lastChangeCount
    finishCapture()
    return
  end

  capture.timer = hs.timer.doAfter(0.06, tryCapture)
end

local function captureChange(newCount)
  if type(newCount) ~= "number" then
    return
  end
  if newCount == lastChangeCount then
    return
  end

  stopCapture()
  capture.count = newCount
  capture.retries = 10
  tryCapture()
end

local function captureLatest()
  captureChange(hs.pasteboard.changeCount())
end

local function preview(text)
  local p = text:sub(1, config.previewChars):gsub("[%c]+", " "):gsub("%s+", " ")
  if #text > config.previewChars then
    return p .. "..."
  end
  return p
end

local function buildChoices()
  local choices = {}

  if chooserMode == "paste" and config.showChooserActions then
    table.insert(choices, {
      text = "Copy All Items",
      subText = "Copy whole history into clipboard (newline-separated)",
      action = "copy_all",
    })
    table.insert(choices, {
      text = "Clear All Items",
      subText = "Delete every history item",
      action = "clear_all",
    })
    table.insert(choices, {
      text = "Delete One Item...",
      subText = "Pick an item to delete",
      action = "delete_mode",
    })
  end

  for i, item in ipairs(history) do
    table.insert(choices, {
      text = preview(item),
      subText = string.format("#%d  %d chars%s", i, #item, chooserMode == "delete" and "  (click to delete)" or ""),
      full = item,
    })
  end

  return choices
end

local function openChooser(mode)
  chooserMode = mode or "paste"

  if not chooser then
    chooser = hs.chooser.new(function(choice)
      if not choice then
        return
      end

      if choice.action == "copy_all" then
        copyAllHistory()
        return
      end
      if choice.action == "clear_all" then
        clearHistory("manual clear")
        hs.timer.doAfter(0.01, function()
          openChooser("paste")
        end)
        return
      end
      if choice.action == "delete_mode" then
        hs.timer.doAfter(0.01, function()
          openChooser("delete")
        end)
        return
      end

      if chooserMode == "delete" then
        removeOne(choice.full)
        hs.timer.doAfter(0.01, function()
          openChooser("delete")
        end)
        return
      end

      -- Safety net: stash current clipboard text before overwriting.
      local current = readPasteboardText()
      if current and current ~= choice.full then
        addToHistory(current)
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
    if config.disableChooserDefaultKeys and chooser.enableDefaultKeys then
      chooser:enableDefaultKeys(false)
    end
  end

  chooser:placeholderText(chooserMode == "delete" and "Delete mode: pick an item to remove" or "Clipboard history")
  chooser:choices(buildChoices())
  chooser:show()
end

local function showHistory()
  lastFocusedApp = hs.application.frontmostApplication()
  openChooser("paste")
  captureLatest()
  hs.timer.doAfter(0.07, function()
    if chooser and chooserMode == "paste" then
      chooser:choices(buildChoices())
    end
  end)
end

local function startMonitor()
  hs.timer.doEvery(config.pollInterval, function()
    local c = hs.pasteboard.changeCount()
    if c ~= lastChangeCount then
      captureChange(c)
    end
  end)
end

-- Console helpers
_G.clearClipboardHistory = function()
  clearHistory("manual")
end
_G.showClipboardMemoryUsage = function()
  printMemoryUsage()
end

loadHistory()
startMonitor()

-- Main hotkey (Win+V equivalent)
hs.hotkey.bind({ "cmd", "shift" }, "v", showHistory)

hs.printf("CopyHammer (Simple) ready. Hotkey: cmd+shift+v")
printMemoryUsage()
