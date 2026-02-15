-- Minimal clipboard history for Hammerspoon (personal use)

local config = {
  pollInterval = 0.5,
  maxItems = 30,
  maxChars = 100000,
  previewChars = 80,
  autoPasteOnSelect = true,
  showMenubarUsage = true,
  showChooserActions = true,
  historyFile = os.getenv("HOME") .. "/.hammerspoon/clipboard.json",
}

local history = {}
local chooser
local lastChangeCount = hs.pasteboard.changeCount()
local lastFocusedApp
local chooserMode = "paste"
local menubar
local menuButton
local updateMenuBar

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
      if choice.action == "copy_all" then
        copyAllHistory()
        return
      end
      if choice.action == "clear_all" then
        clearHistory("manual clear from chooser")
        return
      end
      if choice.action == "delete_mode" then
        hs.timer.doAfter(0.01, function()
          openChooser("delete")
        end)
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
  end

  chooserMode = mode or "paste"
  lastFocusedApp = hs.application.frontmostApplication()

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
      subText = "Open delete mode and pick an item",
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

  local placeholder = chooserMode == "delete" and "Delete mode: pick an item to remove" or "Clipboard history"
  chooser:placeholderText(placeholder)
  chooser:choices(choices)
  chooser:show()
  printMemoryUsage()
end

local function showChooser()
  openChooser("paste")
end

local function showDeleteChooser()
  openChooser("delete")
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
        { title = "Open History (cmd+shift+v)", fn = showChooser },
        { title = "Delete One Item (cmd+ctrl+shift+v)", fn = showDeleteChooser },
        { title = "Copy All Items (cmd+ctrl+shift+c)", fn = copyAllHistory },
        { title = "Clear All (cmd+shift+delete)", fn = function() clearHistory("manual clear") end },
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
setupMenubar()
startClipboardMonitor()
hs.hotkey.bind({"cmd", "shift"}, "v", showChooser)
hs.hotkey.bind({"cmd", "ctrl", "shift"}, "v", showDeleteChooser)
hs.hotkey.bind({"cmd", "ctrl", "shift"}, "c", copyAllHistory)
hs.hotkey.bind({"cmd", "shift"}, "delete", function() clearHistory("manual clear hotkey") end)

hs.printf("Clipboard history ready. Hotkeys: cmd+shift+v (open), cmd+ctrl+shift+v (delete mode), cmd+ctrl+shift+c (copy all), cmd+shift+delete (clear all)")
printMemoryUsage()
