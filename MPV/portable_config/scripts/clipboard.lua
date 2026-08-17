-- clipboard.lua
-- Loads a URL or file path from the clipboard into the CURRENT mpv window.
-- Triggered via input.conf: Ctrl+v → script-message clipboard-paste
--
-- Behaviour:
--   • Strips all known tracking garbage (si, pp, fbclid, utm_*, etc.)
--   • Detects YouTube/generic ?t= / ?start= timestamp → strips from URL,
--     stores the clean base URL, then seeks AFTER the file has loaded.
--   • History deduplication works on the clean base URL (no timestamp drift).
--   • All paste notifications appear CENTERED on screen (both axes).

local mp = require 'mp'

-- ─────────────────────────────────────────────────────────────────────────────
-- CENTERED OSD OVERLAY
-- Uses a fixed 1920×1080 coordinate space so \pos(960,540) is always center,
-- regardless of the actual video resolution. mpv scales the overlay to fit.
-- ─────────────────────────────────────────────────────────────────────────────
local overlay       = mp.create_osd_overlay("ass-events")
overlay.res_x       = 1920
overlay.res_y       = 1080
local overlay_timer = nil

local FONT     = "Montserrat ExtraBold"
local CX, CY   = 960, 540   -- screen center in overlay coordinate space

-- Dismiss any active overlay immediately (used before showing a new one)
local function overlay_clear()
    if overlay_timer then
        overlay_timer:kill()
        overlay_timer = nil
    end
    overlay:remove()
end

-- Show a one- or two-line message centered on screen.
-- line1  : primary text  (larger, white)
-- line2  : secondary text (smaller, grey) — pass nil to omit
-- duration : seconds before auto-dismiss
local function show_center(line1, line2, duration)
    overlay_clear()

    local body
    if line2 then
        body = string.format(
            "{\\an5\\pos(%d,%d)\\fn%s\\fs48\\bord2.5\\1c&HFFFFFF&\\3c&H000000&}%s" ..
            "\\N{\\fn%s\\fs40\\bord1.5\\1c&HBBBBBB&\\3c&H000000&}%s",
            CX, CY, FONT, line1, FONT, line2
        )
    else
        body = string.format(
            "{\\an5\\pos(%d,%d)\\fn%s\\fs21\\bord2.5\\1c&HFFFFFF&\\3c&H000000&}%s",
            CX, CY, FONT, line1
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
-- URL DISPLAY HELPER
-- Truncates long URLs to a readable domain + ellipsis for on-screen display.
-- The full URL is still passed to mpv/yt-dlp — only the display string is cut.
-- ─────────────────────────────────────────────────────────────────────────────
local function display_url(url)
    if #url <= 55 then return url end
    local domain = url:match("^https?://([^/]+)") or ""
    return domain .. "/…"
end

-- ─────────────────────────────────────────────────────────────────────────────
-- TIMESTAMP PARSER
-- Handles all YouTube timestamp formats:
--   ?t=120        → plain seconds
--   ?t=120s       → seconds with suffix
--   ?t=2m30s      → minutes + seconds
--   ?t=1h20m30s   → hours + minutes + seconds
--   ?start=90     → alternate param name
-- Returns: number (seconds) or nil
-- ─────────────────────────────────────────────────────────────────────────────
local function extract_timestamp(url)
    local raw = url:match("[?&]t=([^&]+)") or url:match("[?&]start=([^&]+)")
    if not raw then return nil end

    local plain = tonumber(raw)
    if plain then return plain end

    local s_only = raw:match("^(%d+)s$")
    if s_only then return tonumber(s_only) end

    local h, m, s = raw:match("^(%d+)h(%d+)m(%d+)s$")
    if h then return tonumber(h) * 3600 + tonumber(m) * 60 + tonumber(s) end

    local hh, mm = raw:match("^(%d+)h(%d+)m$")
    if hh then return tonumber(hh) * 3600 + tonumber(mm) * 60 end

    local m2, s2 = raw:match("^(%d+)m(%d+)s$")
    if m2 then return tonumber(m2) * 60 + tonumber(s2) end

    local m3 = raw:match("^(%d+)m$")
    if m3 then return tonumber(m3) * 60 end

    local s3 = raw:match("^(%d+)s$")
    if s3 then return tonumber(s3) end

    return nil
end

-- ─────────────────────────────────────────────────────────────────────────────
-- URL CLEANER
-- Returns: clean_url (string), timestamp_secs (number or nil)
--
-- Pass 1 – extract timestamp params (t, start); we seek manually.
-- Pass 2 – strip tracking garbage (si, pp, fbclid, utm_*).
-- ─────────────────────────────────────────────────────────────────────────────
local function clean_url(url)
    if not url:match("^https?://") then
        return url, nil
    end

    local timestamp_secs = extract_timestamp(url)

    local strip_list = { "si", "pp", "fbclid", "t", "start", "list", "index" }
    for _, param in ipairs(strip_list) do
        url = url:gsub("%?" .. param .. "=[^&]*&", "?")
        url = url:gsub("%?" .. param .. "=[^&]*$", "")
        url = url:gsub("&" .. param .. "=[^&]*", "")
    end

    url = url:gsub("%?utm_[^=]+=[^&]*&", "?")
    url = url:gsub("%?utm_[^=]+=[^&]*$", "")
    url = url:gsub("&utm_[^=]+=[^&]*", "")

    return url, timestamp_secs
end

-- ─────────────────────────────────────────────────────────────────────────────
-- CLIPBOARD PASTE HANDLER
-- ─────────────────────────────────────────────────────────────────────────────
local last_clipboard_url = nil

local function play_url(raw)
    local final_url, timestamp_secs = clean_url(raw)
    last_clipboard_url = final_url
    local durl = display_url(final_url)

    if timestamp_secs and timestamp_secs > 0 then
        -- Register a ONE-SHOT file-loaded listener to seek after stream is ready.
        if _G.clipboard_pending_seek then
            mp.unregister_event(_G.clipboard_pending_seek)
        end
        _G.clipboard_pending_seek = function()
            mp.add_timeout(0.5, function()
                mp.commandv("seek", tostring(timestamp_secs), "absolute")
                mp.set_property("pause", "no")
                -- Replace the loading banner with a seek confirmation
                local mins = math.floor(timestamp_secs / 60)
                local secs = timestamp_secs % 60
                show_center(
                    string.format("⏩  Seeked to  %d:%02d", mins, secs),
                    durl,
                    3
                )
            end)
            mp.unregister_event(_G.clipboard_pending_seek)
            _G.clipboard_pending_seek = nil
        end
        mp.register_event("file-loaded", _G.clipboard_pending_seek)

        local mins = math.floor(timestamp_secs / 60)
        local secs = timestamp_secs % 60
        show_center(
            string.format("Loading  —  seek to  %d:%02d", mins, secs),
            durl,
            4
        )
    else
        show_center("Loading…", durl, 3)
    end

    mp.commandv("loadfile", final_url)
end

local function get_clipboard()
    local result = mp.command_native({
        name           = "subprocess",
        capture_stdout = true,
        playback_only  = false,
        args           = { "powershell", "-NoProfile", "-Command", "Get-Clipboard" }
    })

    if not result or result.status ~= 0 then return nil end
    local raw = result.stdout:match("([^\r\n]+)")
    if raw then raw = raw:match("^%s*(.-)%s*$") end
    return raw
end

mp.register_script_message("clipboard-paste", function()
    local raw = get_clipboard()
    if not raw then
        show_center("✗  Clipboard Read Failed", nil, 3)
        return
    end
    if raw == "" then
        show_center("✗  Clipboard is Empty", nil, 3)
        return
    end
    play_url(raw)
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- CLIPBOARD AUTO-OPEN HANDLER
-- ─────────────────────────────────────────────────────────────────────────────
local prompt_timer = nil

local function unbind_prompt()
    mp.remove_key_binding("clip-open-y")
    mp.remove_key_binding("clip-open-Y")
    mp.remove_key_binding("clip-open-enter")
    mp.remove_key_binding("clip-open-n")
    mp.remove_key_binding("clip-open-N")
    mp.remove_key_binding("clip-open-esc")
    if prompt_timer then
        prompt_timer:kill()
        prompt_timer = nil
    end
    overlay_clear()
end

local function ask_to_open(url)
    local durl = display_url(url)
    show_center("Link detected in clipboard", durl .. "\\N\\NPress [Y] to open, [N] to ignore", 10)
    
    if prompt_timer then prompt_timer:kill() end
    prompt_timer = mp.add_timeout(10, function()
        unbind_prompt()
    end)
    
    local function do_open()
        unbind_prompt()
        play_url(url)
    end
    
    local function do_ignore()
        unbind_prompt()
    end

    mp.add_forced_key_binding("y", "clip-open-y", do_open)
    mp.add_forced_key_binding("Y", "clip-open-Y", do_open)
    mp.add_forced_key_binding("ENTER", "clip-open-enter", do_open)
    
    mp.add_forced_key_binding("n", "clip-open-n", do_ignore)
    mp.add_forced_key_binding("N", "clip-open-N", do_ignore)
    mp.add_forced_key_binding("ESC", "clip-open-esc", do_ignore)
end

local function check_auto_clipboard()
    mp.command_native_async({
        name           = "subprocess",
        capture_stdout = true,
        playback_only  = false,
        args           = { "powershell", "-NoProfile", "-Command", "Get-Clipboard" }
    }, function(success, result, error)
        if not success or not result or result.status ~= 0 then return end
        
        local raw = result.stdout:match("([^\r\n]+)")
        if not raw then return end
        raw = raw:match("^%s*(.-)%s*$")
        if raw == "" then return end
        
        if raw:match("^https?://") then
            local final_url, _ = clean_url(raw)
            if final_url ~= last_clipboard_url then
                last_clipboard_url = final_url
                ask_to_open(raw)
            end
        end
    end)
end

mp.observe_property("focused", "bool", function(name, value)
    if value then
        check_auto_clipboard()
    end
end)

-- Dismiss the prompt if the user opens another file (e.g., from history)
mp.register_event("file-loaded", function()
    if prompt_timer then
        unbind_prompt()
    end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- CLIPBOARD COPY HANDLER
-- ─────────────────────────────────────────────────────────────────────────────
mp.add_forced_key_binding("ctrl+c", "clipboard-copy", function()
    local path = mp.get_property("path")
    if not path or path == "" then
        show_center("✗ No media to copy", nil, 2)
        return
    end

    -- Escape single quotes for PowerShell
    local escaped_path = path:gsub("'", "''")
    
    mp.command_native_async({
        name           = "subprocess",
        capture_stdout = false,
        playback_only  = false,
        args           = { "powershell", "-NoProfile", "-Command", "Set-Clipboard -Value '" .. escaped_path .. "'" }
    }, function(success, result, error)
        if success and result.status == 0 then
            show_center("Copied to clipboard", display_url(path), 3)
        else
            show_center("✗ Copy Failed", nil, 3)
        end
    end)
end)

