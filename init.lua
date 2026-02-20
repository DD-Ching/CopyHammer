-- CopyHammer bootstrap.
-- Keep init.lua tiny; main logic lives in clipboard_winv.lua.

local ok, err = pcall(require, "clipboard_winv")
if not ok then
  hs.printf("CopyHammer: failed to load clipboard_winv (%s)", tostring(err))
end
