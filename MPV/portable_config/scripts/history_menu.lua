-- history_menu.lua
-- Persistent watch history with an in-player OSD menu.
-- Placement: ~~/scripts/history_menu.lua

local mp    = require "mp"
local utils = require "mp.utils"

-- 1. Margin Tracking Observer
local margin_b = 0
mp.observe_property("user-data/osc/margins", "native", function(name, val)
    margin_b = (val and val.b) and val.b or 0
    if menu_open then draw_menu() end
end)

local config_dir   = mp.command_native({"expand-path", "~~/"})
config_dir         = config_dir:gsub("[/\\]+$", "")
local history_file = config_dir .. "/mpv-history.txt"
local thumb_dir    = config_dir .. "/cache/history_thumbnails"

local ytdlp          = "yt-dlp.exe"
local max_entries    = 300

-- ── Ensure thumbnail cache directory exists ───────────────────────────────────
-- Without this, ffmpeg silently fails to write thumbnails on first run.
os.execute('if not exist "' .. thumb_dir:gsub("/", "\\") .. '" mkdir "' .. thumb_dir:gsub("/", "\\") .. '"')

-- ── Path-based thumbnail filename hash ───────────────────────────────────────
-- Using the path (not title) as the hash source avoids collisions between two
-- different local files that share the same title prefix.
local function thumb_id(path)
    local h = 5381
    for i = 1, #path do
        h = ((h * 33) + string.byte(path, i)) % 0x7fffffff
    end
    return string.format("%08x", h)
end

local menu_open          = false
local history            = {}
local selected           = 1
local record_timer       = nil
local status_msg         = ""
local status_timer       = nil
local temp_overlay_timer = nil

local overlay   = mp.create_osd_overlay("ass-events")
overlay.z       = 1000

local THUMB_W = 300
local THUMB_H = 168
local CARD_W  = 320
local CARD_H  = 240
local GRID_PAD = 20
local BASE_OVERLAY_ID = 50

local function get_grid_dimensions()
    local ww, wh = mp.get_osd_size()
    local cols = math.max(1, math.floor((ww - 120) / (CARD_W + GRID_PAD)))
    local rows = math.max(1, math.floor((wh - 200) / (CARD_H + GRID_PAD)))
    return cols, rows, cols * rows, ww, wh
end

local function clean_text(s)
    if not s then return "" end
    s = tostring(s)
    s = s:gsub("[\r\n\t]", " ")
    s = s:gsub("%s+", " ")
    return s
end

local function ass_escape(s)
    s = clean_text(s)
    s = s:gsub("\\", "\\\\")
    s = s:gsub("{",  "\\{")
    s = s:gsub("}",  "\\}")
    return s
end

local function basename(path)
    if not path then return "Unknown" end
    local name = path:gsub("\\", "/"):match("([^/]+)$")
    return name or path
end

local function strip_ytdl_prefix(url)
    if not url then return "" end
    return url:gsub("^ytdl://", "")
end

local function normalize_url(url)
    if not url then return "" end
    url = strip_ytdl_prefix(url)

    if not url:match("^https?://") then
        return url:gsub("\\", "/"):lower()
    end

    local strip_list = { "si", "pp", "fbclid", "t", "start" }
    for _, param in ipairs(strip_list) do
        url = url:gsub("%?" .. param .. "=[^&]*&", "?")
        url = url:gsub("%?" .. param .. "=[^&]*$", "")
        url = url:gsub("&" .. param .. "=[^&]*",   "")
    end
    url = url:gsub("%?utm_[^=]+=[^&]*&", "?")
    url = url:gsub("%?utm_[^=]+=[^&]*$", "")
    url = url:gsub("&utm_[^=]+=[^&]*",   "")
    return url
end

local function source_from_url(path)
    path = strip_ytdl_prefix(path or "")
    local host = path:match("^https?://([^/%?]+)")
    if host then
        host = host:gsub("^www%.", "")
        return host
    end
    if path:match("^%a:[/\\]") or path:match("^/") then
        return "Local file"
    end
    return ""
end

local function source_from_ytdlp_json(json)
    if type(json) ~= "table" then return "" end
    local keys = { "channel", "uploader", "creator", "artist", "uploader_id", "channel_id" }
    for _, key in ipairs(keys) do
        local value = json[key]
        if value and tostring(value) ~= "" then return clean_text(value) end
    end
    return ""
end

local function title_from_ytdlp_json(json)
    if type(json) ~= "table" then return "" end
    local value = json["title"]
    if value and tostring(value) ~= "" then return clean_text(value) end
    return ""
end

local function get_source_name(path)
    local ytdl_json = mp.get_property_native("user-data/mpv/ytdl/json", nil)
    if type(ytdl_json) == "table" then
        local source = source_from_ytdlp_json(ytdl_json)
        if source ~= "" then return source end
    end
    local meta = mp.get_property_native("metadata", {})
    if type(meta) == "table" then
        local keys = { "channel", "uploader", "artist", "author", "creator", "album_artist" }
        for _, key in ipairs(keys) do
            local value = meta[key]
            if value and tostring(value) ~= "" then return clean_text(value) end
        end
    end
    return source_from_url(path)
end

local function clear_thumbnails()
    for i = 0, 40 do
        mp.command_native({"overlay-remove", BASE_OVERLAY_ID + i})
    end
end

local function clear_overlay()
    if temp_overlay_timer then temp_overlay_timer:kill(); temp_overlay_timer = nil end
    overlay.data = ""
    overlay:update()
    clear_thumbnails()
end

local function show_overlay(lines, seconds)
    if temp_overlay_timer then temp_overlay_timer:kill(); temp_overlay_timer = nil end
    local ww, wh = mp.get_osd_size()
    overlay.res_x = ww
    overlay.res_y = wh
    local ass = {}
    local pos_x = 40
    local pos_y = 40
    table.insert(ass, string.format("{\\an7\\pos(%d,%d)\\q2\\fs24\\bord2\\shad1\\1c&HFFFFFF&\\3c&H000000&}", pos_x, pos_y))
    for _, line in ipairs(lines) do table.insert(ass, ass_escape(line)) end
    overlay.data = table.concat(ass, "\\N")
    overlay:update()
    if seconds and seconds > 0 then
        temp_overlay_timer = mp.add_timeout(seconds, clear_overlay)
    end
end

local function read_history()
    local list = {}
    local f = io.open(history_file, "r")
    if not f then return list end
    for line in f:lines() do
        local item = utils.parse_json(line)
        if type(item) == "table" and item.path and item.title then
            if not item.source or item.source == "" then
                item.source = source_from_url(item.path)
            end
            if not item.count then item.count = 1 end
            table.insert(list, item)
        end
    end
    f:close()
    return list
end

local function write_history(list)
    local f = io.open(history_file, "w")
    if not f then
        show_overlay({ "History error:", "Cannot write file:", history_file }, 5)
        return
    end
    for _, item in ipairs(list) do
        f:write(utils.format_json(item), "\n")
    end
    f:close()
end

local function add_to_history(path, title, source, thumb)
    if not path or path == "" then return end

    path = normalize_url(path)
    title = clean_text(title)
    if title == "" then title = clean_text(basename(path)) end
    source = clean_text(source)
    if source == "" then source = source_from_url(path) end

    local old_list  = read_history()
    local new_list  = {}
    local norm_path = normalize_url(path)

    local existing_count = 0
    local existing_thumb = nil
    for _, item in ipairs(old_list) do
        if normalize_url(item.path) == norm_path then
            existing_count = item.count or 1
            existing_thumb = item.thumb
            break
        end
    end
    local new_count = existing_count + 1
    local final_thumb = thumb or existing_thumb

    table.insert(new_list, {
        title  = title,
        source = source,
        path   = path,
        time   = os.time(),
        count  = new_count,
        thumb  = final_thumb,
    })

    for _, item in ipairs(old_list) do
        if normalize_url(item.path) ~= norm_path then
            table.insert(new_list, item)
        end
        if #new_list >= max_entries then break end
    end

    write_history(new_list)
end

local function record_current()
    local path = strip_ytdl_prefix(mp.get_property("path", ""))
    if path == "" then return end

    local fallback_title  = mp.get_property("media-title", "")
    if fallback_title == "" then fallback_title = mp.get_property("filename", "") end
    local fallback_source = get_source_name(path)

    if not path:match("^https?://") then
        local thumb_path = thumb_dir .. "/" .. thumb_id(path) .. ".bgra"

        -- Generate thumbnail for local file
        mp.command_native_async({
            name = "subprocess",
            playback_only = false,
            args = { "ffmpeg", "-y", "-loglevel", "error", "-ss", "00:00:10", "-i", path, 
                     "-frames:v", "1", "-vf", string.format("scale=%d:%d", THUMB_W, THUMB_H), 
                     "-pix_fmt", "bgra", "-f", "rawvideo", thumb_path }
        }, function()
            add_to_history(path, fallback_title, fallback_source, thumb_path)
        end)
        return
    end

    mp.command_native_async({
        name           = "subprocess",
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = false,
        args = { ytdlp, "--skip-download", "--dump-single-json",
                 "--no-warnings", "--no-playlist", path }
    }, function(success, result, _)
        local title  = fallback_title
        local source = fallback_source
        local thumb_url = nil
        if success and result and result.stdout and result.stdout ~= "" then
            local json = utils.parse_json(result.stdout)
            local yt   = title_from_ytdlp_json(json)
            local ys   = source_from_ytdlp_json(json)
            if yt ~= "" then title  = yt end
            if ys ~= "" then source = ys end
            thumb_url = json.thumbnail
        end

        if thumb_url then
            local thumb_path = thumb_dir .. "/" .. thumb_id(path) .. ".bgra"

            mp.command_native_async({
                name = "subprocess",
                playback_only = false,
                args = { "ffmpeg", "-y", "-loglevel", "error", "-i", thumb_url, 
                         "-vf", string.format("scale=%d:%d", THUMB_W, THUMB_H), 
                         "-pix_fmt", "bgra", "-f", "rawvideo", thumb_path }
            }, function()
                add_to_history(path, title, source, thumb_path)
            end)
        else
            add_to_history(path, title, source)
        end
    end)
end

local function schedule_record()
    if record_timer then record_timer:kill(); record_timer = nil end
    record_timer = mp.add_timeout(2.0, record_current)
end

local function close_menu()
    if not menu_open then return end
    menu_open = false
    local binds = {
        "history_up", "history_down", "history_left", "history_right",
        "history_enter", "history_kp_enter", "history_esc", "history_bs",
        "history_delete",
    }
    for _, b in ipairs(binds) do mp.remove_key_binding(b) end
    clear_overlay()
end

local function draw_menu()
    if not menu_open then return end

    if #history == 0 then
        show_overlay({ "Played History", "", "History is empty." }, 5)
        return
    end

    local grid_cols, grid_rows, visible_items, ww, wh = get_grid_dimensions()

    if selected < 1 then selected = 1 end
    if selected > #history then selected = #history end

    local page = math.floor((selected - 1) / visible_items)
    local first = page * visible_items + 1
    local last  = math.min(#history, first + visible_items - 1)

    local ass = {}
    overlay.res_x = ww
    overlay.res_y = wh

    -- Main background
    table.insert(ass, string.format("{\\an7\\pos(0,0)\\bord0\\1c&H000000&\\alpha&H44&\\p1}m 0 0 l %d 0 l %d %d l 0 %d{\\p0}", ww, ww, wh, wh))

    -- Header
    table.insert(ass, string.format("{\\an7\\pos(60,40)\\q2\\fs30\\b1\\1c&HFFFFFF&}History Grid{\\b0\\fs20\\1c&HBBBBBB&}  [%d/%d]  —  Use Arrows to navigate, Enter to play, Del to remove", selected, #history))

    if status_msg ~= "" then
        table.insert(ass, string.format("{\\an7\\pos(60,80)\\fs20\\1c&H00FFFF&}%s", ass_escape(status_msg)))
    end

    clear_thumbnails()

    local start_x = 60
    local start_y = 120

    for i = first, last do
        local idx = i - first
        local col = idx % grid_cols
        local row = math.floor(idx / grid_cols)

        local x = start_x + col * (CARD_W + GRID_PAD)
        local y = start_y + row * (CARD_H + GRID_PAD)

        local item = history[i]
        local is_selected = (i == selected)

        -- Selection highlight
        if is_selected then
            table.insert(ass, string.format("{\\an7\\pos(%d,%d)\\bord0\\1c&H00FFFF&\\alpha&H66&\\p1}m 0 0 l %d 0 l %d %d l 0 %d{\\p0}", x - 5, y - 5, CARD_W + 10, CARD_W + 10, CARD_H + 10, CARD_H + 10))
        end

        -- Card background
        table.insert(ass, string.format("{\\an7\\pos(%d,%d)\\bord0\\1c&H222222&\\alpha&H22&\\p1}m 0 0 l %d 0 l %d %d l 0 %d{\\p0}", x, y, CARD_W, CARD_W, CARD_H, CARD_H))

        -- Thumbnail
        local has_thumb = false
        if item.thumb and item.thumb ~= "" then
            local f = io.open(item.thumb, "rb")
            if f then
                f:close()
                has_thumb = true
                local tx = x + (CARD_W - THUMB_W) / 2
                local ty = y + 10
                mp.command_native({
                    "overlay-add", BASE_OVERLAY_ID + idx,
                    math.floor(tx), math.floor(ty),
                    item.thumb, 0, "bgra", THUMB_W, THUMB_H, THUMB_W * 4
                })
            end
        end

        if not has_thumb then
            table.insert(ass, string.format("{\\an7\\pos(%d,%d)\\fs16\\1c&H888888&}No Thumbnail", x + CARD_W/2 - 40, y + THUMB_H/2))
        end

        -- Metadata
        local source = item.source or "Unknown"
        local title  = item.title  or basename(item.path)
        if #title > 55 then title = title:sub(1, 52) .. "..." end
        if #source > 30 then source = source:sub(1, 27) .. "..." end

        -- Source badge
        table.insert(ass, string.format("{\\an7\\pos(%d,%d)\\fs16\\b1\\1c&H00AAAA&}%s", x + 10, y + THUMB_H + 20, ass_escape(source)))

        -- Title
        local title_color = is_selected and "H00FFFF" or "HFFFFFF"
        table.insert(ass, string.format("{\\an7\\pos(%d,%d)\\q2\\fs18\\1c&%s&}%s", x + 10, y + THUMB_H + 45, title_color, ass_escape(title)))

        -- Count badge
        if item.count and item.count > 1 then
            table.insert(ass, string.format("{\\an9\\pos(%d,%d)\\fs14\\1c&HFFAA00&}×%d", x + CARD_W - 10, y + THUMB_H + 20, item.count))
        end
    end

    overlay.data = table.concat(ass, "\n")
    overlay:update()
end

local function set_status(msg, seconds)
    status_msg = msg or ""
    if status_timer then status_timer:kill(); status_timer = nil end
    if seconds and seconds > 0 then
        status_timer = mp.add_timeout(seconds, function()
            status_msg = ""
            draw_menu()
        end)
    end
    draw_menu()
end

local function move_selection(dx, dy)
    if #history == 0 then return end
    local grid_cols, _, _, _, _ = get_grid_dimensions()
    local new_sel = selected + dx + (dy * grid_cols)
    if new_sel < 1 then new_sel = 1 end
    if new_sel > #history then new_sel = #history end
    selected = new_sel
    draw_menu()
end
local function play_selected()
    if #history == 0 then close_menu(); return end
    local item = history[selected]
    if not item or not item.path then close_menu(); return end
    local path = item.path
    close_menu()
    mp.commandv("loadfile", path, "replace")
end

local function delete_selected()
    if #history == 0 then return end
    local item = history[selected]
    local removed = item.title or item.path
    if item.thumb and item.thumb ~= "" then
        os.remove(item.thumb)
    end
    table.remove(history, selected)
    if selected > #history then selected = math.max(1, #history) end
    write_history(history)
    set_status("Removed: " .. clean_text(removed):sub(1, 60), 2)
end

local function show_history()
    history = read_history()

    if #history == 0 then
        show_overlay({ "Played History", "", "History is empty." }, 5)
        return
    end

    menu_open = true
    selected  = 1
    status_msg = ""

    mp.add_forced_key_binding("UP",    "history_up",    function() move_selection(0, -1) end, { repeatable = true })
    mp.add_forced_key_binding("DOWN",  "history_down",  function() move_selection(0, 1)  end, { repeatable = true })
    mp.add_forced_key_binding("LEFT",  "history_left",  function() move_selection(-1, 0) end, { repeatable = true })
    mp.add_forced_key_binding("RIGHT", "history_right", function() move_selection(1, 0)  end, { repeatable = true })
    mp.add_forced_key_binding("ENTER",    "history_enter",    play_selected)
    mp.add_forced_key_binding("KP_ENTER", "history_kp_enter", play_selected)
    mp.add_forced_key_binding("DEL", "history_delete", delete_selected)
    mp.add_forced_key_binding("ESC", "history_esc", close_menu)
    mp.add_forced_key_binding("BS",  "history_bs",  close_menu)

    draw_menu()
end

local function toggle_history()
    if menu_open then close_menu() else show_history() end
end

mp.register_event("file-loaded", schedule_record)
mp.add_key_binding(nil, "show_history", toggle_history)