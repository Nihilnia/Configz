-- premium_toggle.lua
-- Toggles YouTube Premium "Enhanced Bitrate" mode on/off.
--
-- Requirements:
--   1. A YouTube Premium subscription.
--   2. Cookies configured in mpv.conf (one of):
--        ytdl-raw-options-append=cookies-from-browser=chrome
--        ytdl-raw-options-append=cookies-from-browser=firefox
--        ytdl-raw-options-append=cookies-from-browser=edge
--
-- Keybinds:
--   F6     → opens the combined Resolution + Premium menu (via toggle_1080p.lua)
--   Alt+y  → direct toggle alias (no menu)

local mp = require "mp"

-- ─────────────────────────────────────────────────────────────────────────────
-- CENTERED OSD OVERLAY
-- ─────────────────────────────────────────────────────────────────────────────
local overlay       = mp.create_osd_overlay("ass-events")
overlay.res_x       = 1920
overlay.res_y       = 1080
local overlay_timer = nil
local FONT          = "Montserrat ExtraBold"

local function show_center(line1, line2, duration)
    if overlay_timer then overlay_timer:kill(); overlay_timer = nil end
    overlay:remove()

    local ow, oh = mp.get_osd_size()
    overlay.res_x = (ow and ow > 0) and ow or 1920
    overlay.res_y = (oh and oh > 0) and oh or 1080

    local cx = math.floor(overlay.res_x / 2)
    local cy = math.floor(overlay.res_y / 2)
    local body
    if line2 then
        body = string.format(
            "{\\an5\\pos(%d,%d)\\fn%s\\fs48\\bord2.5\\1c&HFFFFFF&\\3c&H000000&}%s"  ..
            "\\N{\\fn%s\\fs40\\bord1.5\\1c&HBBBBBB&\\3c&H000000&}%s",
            cx, cy, FONT, line1, FONT, line2
        )
    else
        body = string.format(
            "{\\an5\\pos(%d,%d)\\fn%s\\fs48\\bord2.5\\1c&HFFFFFF&\\3c&H000000&}%s",
            cx, cy, FONT, line1
        )
    end

    overlay.data = body
    overlay:update()
    overlay_timer = mp.add_timeout(duration, function()
        overlay:remove()
        overlay_timer = nil
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- FORMAT STRINGS-- ─────────────────────────────────────────────────────────────────────────────
-- FORMAT STRINGS
-- FIX: FORMAT_NORMAL now exactly mirrors the global ytdl-format in mpv.conf.
-- The previous version capped at height<=1080 and dropped the acodec^=opus
-- preference, so "premium OFF" silently gave lower quality than never touching
-- the toggle at all.
-- ─────────────────────────────────────────────────────────────────────────────
local FORMAT_NORMAL = table.concat({
    "bestvideo[vcodec^=av01]+bestaudio[acodec^=opus]",
    "bestvideo[vcodec^=vp9]+bestaudio[acodec^=opus]",
    "bestvideo+bestaudio",
    "best"
}, "/")

local FORMAT_PREMIUM = table.concat({
    "bestvideo[format_note~='Premium'][height<=1080]+bestaudio",
    "bestvideo[format_note~='Premium'][height<=1440]+bestaudio",
    "bestvideo[format_id=616]+bestaudio",
    "bestvideo[height<=1080][vcodec^=av01]+bestaudio",
    "bestvideo[height<=1080][vcodec^=vp9]+bestaudio",
    "bestvideo[height<=1080]+bestaudio",
    "best"
}, "/")

-- ─────────────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────────────
local premium_active  = false
local confirm_on_load = false
local saved_pos       = 0

-- ─────────────────────────────────────────────────────────────────────────────
-- HELPERS
-- ─────────────────────────────────────────────────────────────────────────────
local function is_network_url(path)
    return path and path:match("^https?://") ~= nil
end

local was_paused = false  -- tracks pause state before reload

local function reload_current()
    local path = mp.get_property("path")
    if not path then return false end
    if not is_network_url(path) then
        show_center("Premium", "Only affects network streams", 3)
        return false
    end
    saved_pos  = mp.get_property_number("time-pos") or 0
    was_paused = mp.get_property_bool("pause")
    mp.commandv("loadfile", path, "replace", "start=" .. tostring(saved_pos) .. ",pause=" .. (was_paused and "yes" or "no"))
    return true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- POST-RELOAD: POSITION RESTORE + STREAM-INFO BANNER
-- ─────────────────────────────────────────────────────────────────────────────
local function on_file_loaded()
    if not confirm_on_load then return end
    confirm_on_load = false

    mp.add_timeout(2.0, function()
        local h     = mp.get_property_number("video-params/h") or 0
        local w     = mp.get_property_number("video-params/w") or 0
        local codec = mp.get_property("video-codec-name") or "?"
        local bps   = mp.get_property_number("video-bitrate") or 0
        local brate = bps > 0 and string.format("%.1f Mbps", bps / 1e6) or "live bitrate"
        saved_pos   = 0

        if premium_active then
            show_center(
                "★  Premium  —  ACTIVE",
                string.format("%d × %d   %s   %s", w, h, codec:upper(), brate),
                6
            )
        else
            show_center(
                "Premium  —  OFF",
                string.format("%d × %d   %s   %s", w, h, codec:upper(), brate),
                5
            )
        end
    end)
end

mp.register_event("file-loaded", on_file_loaded)

-- ─────────────────────────────────────────────────────────────────────────────
-- TOGGLE
-- ─────────────────────────────────────────────────────────────────────────────
local function toggle_premium()
    premium_active = not premium_active
    mp.commandv("script-message", "premium-state-changed", premium_active and "yes" or "no")

    if premium_active then
        mp.set_property("ytdl-format", FORMAT_PREMIUM)
        show_center("★  Premium Mode  —  ON", "Switching stream  ·  resuming position…", 3)
        confirm_on_load = reload_current()
    else
        mp.set_property("ytdl-format", FORMAT_NORMAL)
        show_center("Premium Mode  —  OFF", "Switching to standard quality…", 3)
        confirm_on_load = reload_current()
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- STATUS QUERY
-- ─────────────────────────────────────────────────────────────────────────────
local function show_status()
    if premium_active then
        show_center("★  Premium Mode  —  ACTIVE", "Enhanced bitrate  ·  F6 or Alt+y to disable", 4)
    else
        show_center("Premium Mode  —  OFF", "Standard quality  ·  F6 or Alt+y to enable", 4)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HOOKS
-- ─────────────────────────────────────────────────────────────────────────────
mp.register_script_message("premium-toggle", toggle_premium)
mp.register_script_message("premium-status", show_status)
