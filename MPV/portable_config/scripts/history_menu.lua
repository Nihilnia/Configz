-- history_menu.lua
-- Persistent watch history with an in-player OSD menu.
-- Placement: ~~/scripts/history_menu.lua

local mp    = require "mp"
local utils = require "mp.utils"
local options = require "mp.options"

-- 1. Margin Tracking Observer
local margin_b = 0
local menu_open          = false
local redraw_timer       = nil
local draw_menu
local play_selected
local layout_origin_x    = 0
local layout_origin_y    = 0
local layout_cols        = 1
local layout_page_start  = 1

local function schedule_layout_redraw()
    if not menu_open or not draw_menu then return end
    if redraw_timer then redraw_timer:kill() end
    redraw_timer = mp.add_timeout(0.12, function()
        redraw_timer = nil
        local ww, wh = mp.get_osd_size()
        if menu_open and ww >= 360 and wh >= 240 then
            draw_menu(true)
        end
    end)
end

mp.observe_property("user-data/osc/margins", "native", function(name, val)
    margin_b = (val and val.b) and val.b or 0
    schedule_layout_redraw()
end)
mp.observe_property("osd-width", "native", function()
    schedule_layout_redraw()
end)
mp.observe_property("osd-height", "native", function()
    schedule_layout_redraw()
end)

local config_dir   = mp.command_native({"expand-path", "~~/"})
config_dir         = config_dir:gsub("[/\\]+$", "")
local history_file = config_dir .. "/mpv-history.txt"
local thumb_dir    = config_dir .. "/cache/history_thumbnails"
local ffmpeg       = mp.command_native({"expand-path", "~~/../ffmpeg.exe"})
if not utils.file_info(ffmpeg) then ffmpeg = "ffmpeg" end

local ytdlp          = "yt-dlp.exe"
local history_options = { max_entries = 300 }
options.read_options(history_options, "history_menu")
local max_entries = math.max(1, tonumber(history_options.max_entries) or 300)

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

local history            = {}
local selected           = 1
local record_timer       = nil
local status_msg         = ""
local status_timer       = nil
local temp_overlay_timer = nil
local loading_timer      = nil
local loading_overlay    = mp.create_osd_overlay("ass-events")
loading_overlay.z        = 1001

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

local function is_idle_logo_path(path)
    if not path then return false end
    path = strip_ytdl_prefix(path):gsub("\\", "/"):lower()
    return path == "logo.png" or path:match("/logo%.png$") ~= nil
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

local function clear_overlay(remove_thumbnails)
    if temp_overlay_timer then temp_overlay_timer:kill(); temp_overlay_timer = nil end
    overlay.data = ""
    overlay:update()
    if remove_thumbnails ~= false then clear_thumbnails() end
end

local function stop_loading()
    if loading_timer then loading_timer:kill(); loading_timer = nil end
    loading_overlay.data = ""
    loading_overlay:update()
end

local function start_loading()
    stop_loading()
    local frame = 0
    local function render_loading()
        local ww, wh = mp.get_osd_size()
        if ww < 320 or wh < 180 then return end
        frame = (frame % 3) + 1
        local dots = string.rep(".", frame)
        loading_overlay.res_x = ww
        loading_overlay.res_y = wh
        loading_overlay.data = string.format(
            "{\\an5\\pos(%d,%d)\\q2\\fs24\\b1\\1c&HFFFFFF&\\3c&H000000&\\bord2}LOADING MEDIA%s\\N{\\fs14\\b0\\1c&HE5B64A&}Please wait",
            math.floor(ww / 2), math.floor(wh / 2), dots)
        loading_overlay:update()
    end
    render_loading()
    loading_timer = mp.add_periodic_timer(0.35, render_loading)
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
        if type(item) == "table" and item.path and item.title and not is_idle_logo_path(item.path) then
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
    if not path or path == "" or is_idle_logo_path(path) then return end

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
            args = { ffmpeg, "-y", "-loglevel", "error", "-ss", "00:00:10", "-i", path, 
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
                args = { ffmpeg, "-y", "-loglevel", "error", "-i", thumb_url, 
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
    if redraw_timer then redraw_timer:kill(); redraw_timer = nil end
    local binds = {
        "history_up", "history_down", "history_left", "history_right",
        "history_enter", "history_kp_enter", "history_mouse_click", "history_esc", "history_bs",
        "history_delete",
    }
    for _, b in ipairs(binds) do mp.remove_key_binding(b) end
    clear_overlay(true)
end

draw_menu = function(rebuild_thumbnails)
    if rebuild_thumbnails == nil then rebuild_thumbnails = true end
    if not menu_open then return end

    if #history == 0 then
        show_overlay({ "WATCH HISTORY", "", "No recently played items yet." }, 5)
        return
    end

    local grid_cols, grid_rows, visible_items, ww, wh = get_grid_dimensions()
    local panel_x, panel_y = 26, 22
    local panel_w, panel_h = math.max(1, ww - 52), math.max(1, wh - 44)
    local outer_x = 52
    local header_y = 42
    local grid_y = 126
    local grid_w = grid_cols * CARD_W + (grid_cols - 1) * GRID_PAD
    local start_x = math.max(outer_x, math.floor((ww - grid_w) / 2))
    local page_start = math.floor((selected - 1) / visible_items) * visible_items + 1
    layout_origin_x = start_x
    layout_origin_y = grid_y
    layout_cols = grid_cols
    layout_page_start = page_start
    local page_end = math.min(#history, page_start + visible_items - 1)

    clear_overlay(rebuild_thumbnails)

    local ass = {}
    local function add(value)
        ass[#ass + 1] = value
    end

    local function box(x, y, w, h, fill, alpha, border, border_color)
        local stroke = "\\bord0"
        if border and border > 0 then
            stroke = string.format("\\bord%d\\3c&H%s&", border, border_color or fill)
        end
        add(string.format(
            "{\\an7\\pos(%d,%d)\\p1\\1c&H%s&\\1a&H%s&%s}m 0 0 l %d 0 l %d %d l 0 %d",
            x, y, fill, alpha or "00", stroke, w, w, h, h
        ))
    end

    local function text(x, y, value, size, color, align, alpha, bold)
        local weight = bold and "\\b1" or "\\b0"
        add(string.format(
            "{\\an%d\\pos(%d,%d)\\fnSegoe UI\\fs%d\\q2\\1c&H%s&\\alpha&H%s&\\bord0\\shad0%s}%s",
            align or 7, x, y, size, color, alpha or "00", weight, ass_escape(value or "")
        ))
    end

    local function shorten(value, limit)
        value = clean_text(value or "")
        if #value > limit then return value:sub(1, limit - 3) .. "..." end
        return value
    end

    local function time_label(value)
        local timestamp = tonumber(value)
        if not timestamp then return "Unknown date" end
        local age = math.max(0, os.time() - timestamp)
        if age < 60 then return "Just now" end
        if age < 3600 then return string.format("%dm ago", math.floor(age / 60)) end
        if age < 86400 then return string.format("%dh ago", math.floor(age / 3600)) end
        if age < 604800 then return string.format("%dd ago", math.floor(age / 86400)) end
        return os.date("%b %d, %Y", timestamp)
    end

    local C = {
        panel = "171A20", card = "20242B", card_selected = "29251C",
        thumb = "0D1015", white = "F2F4F7", muted = "A9B0BB",
        dim = "6F7784", line = "343A45", amber = "E5B64A",
        amber_dark = "3A2C14", black = "0A0C0F", green = "6CCB9F",
    }

    -- Full-surface panel and restrained header.
    box(panel_x, panel_y, panel_w, panel_h, C.panel, "08", 1, C.line)
    box(panel_x + 1, panel_y + 1, panel_w - 2, 84, C.black, "45")
    box(panel_x + 34, 108, panel_w - 68, 1, C.line, "20")

    text(outer_x, header_y, "WATCH HISTORY", 12, C.amber, 7, "00", true)
    text(outer_x, header_y + 22, "Recently played", 30, C.white, 7, "00", true)
    text(outer_x, header_y + 57, "Your latest videos and local media", 13, C.muted, 7, "00", false)

    local range_text = string.format("%02d–%02d  /  %d ITEMS", page_start, page_end, #history)
    box(ww - outer_x - 190, header_y + 4, 190, 30, C.card, "00", 1, C.line)
    text(ww - outer_x - 95, header_y + 11, range_text, 10, C.muted, 5, "00", true)

    for slot = 1, visible_items do
        local index = page_start + slot - 1
        if index > #history then break end

        local item = history[index]
        local col = (slot - 1) % grid_cols
        local row = math.floor((slot - 1) / grid_cols)
        local x = start_x + col * (CARD_W + GRID_PAD)
        local y = grid_y + row * (CARD_H + GRID_PAD)
        local is_selected = index == selected

        box(x, y, CARD_W, CARD_H, is_selected and C.card_selected or C.card, is_selected and "00" or "12", is_selected and 2 or 1, is_selected and C.amber or C.line)
        box(x + 10, y + 10, THUMB_W, THUMB_H, C.thumb, "00")

        local has_thumb = item.thumb and item.thumb ~= "" and utils.file_info(item.thumb) ~= nil
        if has_thumb then
            if rebuild_thumbnails then
            mp.command_native({
                "overlay-add", BASE_OVERLAY_ID + slot,
                x + 10, y + 10, item.thumb, 0,
                "bgra", THUMB_W, THUMB_H, THUMB_W * 4
            })
            end
        else
            box(x + 10, y + 10, THUMB_W, THUMB_H, C.thumb, "00")
            text(x + 160, y + 68, "▶", 28, is_selected and C.amber or C.muted, 5, "00", true)
            text(x + 160, y + 105, "THUMBNAIL UNAVAILABLE", 9, C.dim, 5, "00", true)
        end

        -- A quiet lower scrim makes titles readable over real thumbnails.
        box(x + 10, y + 128, THUMB_W, 50, C.black, "52")
        if is_selected then
            box(x + 20, y + 20, 78, 20, C.amber, "00", 0)
            text(x + 59, y + 25, "SELECTED", 9, C.black, 5, "00", true)
        end

        local source = clean_text(item.source or "")
        if source == "" then source = source_from_url(item.path) end
        if source == "" then source = "Local file" end
        source = shorten(source, 22)
        local title = item.title or basename(item.path)
        if title == "" then title = "Untitled media" end
        title = shorten(title, 42)

        local pill_w = math.max(82, math.min(190, (#source * 7) + 26))
        box(x + 18, y + 188, pill_w, 20, is_selected and C.amber_dark or C.black, "08", 1, is_selected and C.amber or C.line)
        text(x + 30, y + 193, source, 9, is_selected and C.amber or C.muted, 7, "00", true)
        text(x + 18, y + 216, title, 14, C.white, 7, "00", is_selected)
        text(x + 18, y + 234, time_label(item.time), 10, C.dim, 7, "00", false)

        local count = tonumber(item.count) or 1
        if count > 1 then
            box(x + CARD_W - 66, y + 229, 48, 20, C.black, "10", 1, C.line)
            text(x + CARD_W - 42, y + 234, "×" .. tostring(count), 10, C.muted, 5, "00", true)
        end
    end

    local footer_y = wh - math.max(36, margin_b + 20)
    box(panel_x + 34, footer_y - 12, panel_w - 68, 1, C.line, "20")
    text(outer_x, footer_y, "ARROWS", 10, C.amber, 1, "00", true)
    text(outer_x + 58, footer_y, "Navigate", 10, C.muted, 1, "00", false)
    text(outer_x + 138, footer_y, "ENTER", 10, C.amber, 1, "00", true)
    text(outer_x + 194, footer_y, "Play", 10, C.muted, 1, "00", false)
    text(outer_x + 252, footer_y, "DEL", 10, C.amber, 1, "00", true)
    text(outer_x + 292, footer_y, "Remove", 10, C.muted, 1, "00", false)
    text(ww - outer_x, footer_y, status_msg ~= "" and shorten(status_msg, 60) or "ESC  Close", 10, status_msg ~= "" and C.green or C.dim, 3, "00", false)

    overlay.res_x = ww
    overlay.res_y = wh
    overlay.data = table.concat(ass, "\n")
    overlay:update()
end

local function move_selection(dx, dy)
    if #history == 0 then return end
    local grid_cols, _, _, _, _ = get_grid_dimensions()
    local new_sel = selected + dx + (dy * grid_cols)
    if new_sel < 1 then new_sel = 1 end
    if new_sel > #history then new_sel = #history end
    local _, _, page_size = get_grid_dimensions()
    local old_page = math.floor((selected - 1) / math.max(1, page_size))
    if new_sel == selected then return end
    selected = new_sel
    local new_page = math.floor((selected - 1) / math.max(1, page_size))
    draw_menu(old_page ~= new_page)
end
play_selected = function()
    if #history == 0 then close_menu(); return end
    local item = history[selected]
    if not item or not item.path then close_menu(); return end
    local path = item.path
    close_menu()
    start_loading()
    mp.commandv("loadfile", path, "replace")
end

local function mouse_select_or_play()
    if not menu_open then return end
    local pos = mp.get_property_native("mouse-pos")
    if type(pos) ~= "table" or not pos.x or not pos.y then return end
    local mx, my = tonumber(pos.x), tonumber(pos.y)
    local step_x, step_y = CARD_W + GRID_PAD, CARD_H + GRID_PAD
    local rel_x, rel_y = mx - layout_origin_x, my - layout_origin_y
    if rel_x < 0 or rel_y < 0 then return end
    local col, row = math.floor(rel_x / step_x), math.floor(rel_y / step_y)
    if col < 0 or col >= layout_cols or row < 0 then return end
    if (rel_x % step_x) > CARD_W or (rel_y % step_y) > CARD_H then return end
    local index = layout_page_start + row * layout_cols + col
    if index < 1 or index > #history then return end
    if selected == index then
        play_selected()
    else
        selected = index
        draw_menu(false)
    end
end
local function set_status(message, seconds)
    status_msg = clean_text(message or "")
    if status_timer then status_timer:kill(); status_timer = nil end
    if menu_open then
        draw_menu(false)
    else
        show_overlay({ status_msg }, seconds or 3)
    end
    status_timer = mp.add_timeout(seconds or 3, function()
        status_msg = ""
        status_timer = nil
        if menu_open then draw_menu(false) end
    end)
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
    draw_menu(true)
    set_status("Removed: " .. clean_text(removed):sub(1, 60), 2)
end

local function clear_all_history()
local old_list = read_history()
for _, item in ipairs(old_list) do
if item.thumb and item.thumb ~= "" then os.remove(item.thumb) end
end
write_history({})
history = {}
selected = 1
close_menu()
set_status("History and thumbnails cleared", 4)
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
    mp.add_forced_key_binding("MOUSE_BTN0", "history_mouse_click", mouse_select_or_play)
    mp.add_forced_key_binding("DEL", "history_delete", delete_selected)
    mp.add_forced_key_binding("ESC", "history_esc", close_menu)
    mp.add_forced_key_binding("BS",  "history_bs",  close_menu)

    draw_menu(true)
end

local function toggle_history()
    if menu_open then close_menu() else show_history() end
end

mp.register_event("start-file", start_loading)
mp.register_event("file-loaded", function()
    stop_loading()
    schedule_record()
end)
mp.register_event("end-file", stop_loading)
mp.add_key_binding(nil, "history_clear_all", clear_all_history)
mp.add_key_binding(nil, "show_history", toggle_history)
