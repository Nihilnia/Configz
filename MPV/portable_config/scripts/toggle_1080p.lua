-- toggle_1080p.lua  (F6 menu — Resolution + Premium Toggle)
-- F6: open/close menu | UP/DOWN: navigate | ENTER: select | ESC: close
--
-- Two sections:
--   ① RESOLUTION  — scale the video output
--   ② PREMIUM     — toggle YouTube Premium enhanced-bitrate streams
--
-- Premium row reads its state from the "premium-state-changed" broadcast
-- sent by premium_toggle.lua on every toggle.
--
-- FIX: apply_res() now uses hwdec=d3d11va-copy instead of hwdec=no when a
-- scale filter is active. Previously, selecting any non-source resolution
-- disabled hardware decoding entirely, forcing full software decode of
-- AV1/VP9 — a significant CPU hit. d3d11va-copy keeps GPU-assisted decoding
-- active at the cost of one GPU→CPU frame copy per frame, which is
-- dramatically cheaper than pure software decode.
-- When returning to source resolution (no vf filter), hwdec reverts to the
-- zero-copy d3d11va path automatically.

local mp = require "mp"

-- ─────────────────────────────────────────────────────────────────────────────
-- FONT — must match osd-font in mpv.conf for visual consistency
-- ─────────────────────────────────────────────────────────────────────────────
local FONT = "Montserrat ExtraBold"

-- ─────────────────────────────────────────────────────────────────────────────
-- CENTERED OSD OVERLAY  (used for selection confirmations)
-- ─────────────────────────────────────────────────────────────────────────────
local _overlay       = mp.create_osd_overlay("ass-events")
_overlay.res_x       = 1920
_overlay.res_y       = 1080
_overlay.z           = 500    -- above Lyra bg (100), below Tethys (1000)
local _overlay_timer = nil

local function show_center(line1, line2, duration)
    if _overlay_timer then _overlay_timer:kill(); _overlay_timer = nil end
    _overlay:remove()

    local ow, oh = mp.get_osd_size()
    _overlay.res_x = (ow and ow > 0) and ow or 1920
    _overlay.res_y = (oh and oh > 0) and oh or 1080

    local cx = math.floor(_overlay.res_x / 2)
    local cy = math.floor(_overlay.res_y / 2)
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

    _overlay.data = body
    _overlay:update()
    _overlay_timer = mp.add_timeout(duration, function()
        _overlay:remove()
        _overlay_timer = nil
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- RESOLUTION TABLE-- ─────────────────────────────────────────────────────────────────────────────
-- RESOLUTION TABLE
-- ─────────────────────────────────────────────────────────────────────────────
local function get_original_label()
    local w = mp.get_property_number("video-params/w")
    local h = mp.get_property_number("video-params/h")
    if w and h then
        return string.format("Source  (%d × %d)", w, h)
    end
    return "Source  (Original)"
end

local all_resolutions = {
    { label = get_original_label, w = nil,  h = nil  },
    { label = "2560 × 1440",      w = 2560, h = 1440 },
    { label = "1920 × 1080",      w = 1920, h = 1080 },
    { label = "1280 × 720",       w = 1280, h = 720  },
    { label = "854 × 480",        w = 854,  h = 480  },
}

local function get_available_resolutions()
    local src_h = mp.get_property_number("video-params/h")
    local result = {}
    for _, r in ipairs(all_resolutions) do
        if r.h == nil or src_h == nil or r.h < src_h then
            table.insert(result, r)
        end
    end
    return result
end

local function get_label(r)
    if type(r.label) == "function" then return r.label() else return r.label end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MENU ITEMS
-- Flat list: type="res" | type="sep" | type="premium"
-- Separator is non-selectable — navigation skips it.
-- ─────────────────────────────────────────────────────────────────────────────
local function build_items(resolutions)
    local items = {}
    for _, r in ipairs(resolutions) do
        table.insert(items, { type = "res", res = r })
    end
    table.insert(items, { type = "sep" })
    table.insert(items, { type = "premium" })
    table.insert(items, { type = "sep" })
    table.insert(items, { type = "lyra" })
    return items
end

local function is_selectable(items, idx)
    return items[idx] and items[idx].type ~= "sep"
end

local function next_selectable(items, idx, dir)
    local n = idx + dir
    while n >= 1 and n <= #items do
        if is_selectable(items, n) then return n end
        n = n + dir
    end
    return idx
end

-- ─────────────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────────────
local selected  = 1
local current   = 1
local visible   = false
local overlay   = mp.create_osd_overlay("ass-events")
overlay.z       = 500    -- above Lyra bg (100), below Tethys (1000)
local items     = {}
local render

-- ─────────────────────────────────────────────────────────────────────────────
-- PREMIUM STATE — local mirror, kept in sync via "premium-state-changed" event
-- ─────────────────────────────────────────────────────────────────────────────
local premium_state = false

mp.register_script_message("premium-state-changed", function(state)
    premium_state = (state == "yes")
    if visible then render() end
end)

local function is_premium_active()
    return premium_state
end

-- ─────────────────────────────────────────────────────────────────────────────
-- LYRA STATE — local mirror, kept in sync via "lyra-state-changed" event
-- ─────────────────────────────────────────────────────────────────────────────
local lyra_state = false

mp.register_script_message("lyra-state-changed", function(state)
    lyra_state = (state == "yes")
    if visible then render() end
end)

local function is_lyra_active()
    return lyra_state
end

-- ─────────────────────────────────────────────────────────────────────────────
-- MENU RENDER
-- Layout:
--   y=14  ── RESOLUTION / QUALITY  (header)
--   y=36  ── ─────────────────     (header divider)
--   items start at y=60, spacing=26
-- ─────────────────────────────────────────────────────────────────────────────
local ITEM_Y_START  = 60
local ITEM_Y_STEP   = 26
local MENU_X        = 22

local function item_y(i)
    return ITEM_Y_START + i * ITEM_Y_STEP
end

local function build_menu()
    local lines = {}

    -- ── Header ───────────────────────────────────────────────────────────────
    table.insert(lines, string.format(
        "{\\an7\\pos(%d,14)\\fn%s\\fs11\\bord1\\1c&H888888&}RESOLUTION  /  QUALITY  /  LYRA",
        MENU_X, FONT
    ))
    table.insert(lines, string.format(
        "{\\an7\\pos(%d,34)\\fn%s\\fs9\\bord0\\1c&H444444&}%s",
        MENU_X, FONT, ("─"):rep(30)
    ))

    local res_idx = 0

    for i, item in ipairs(items) do
        local y      = item_y(i)
        local is_sel = (i == selected)

        if item.type == "sep" then
            -- ── Visual divider between sections ──────────────────────────────
            table.insert(lines, string.format(
                "{\\an7\\pos(%d,%d)\\fn%s\\fs9\\bord0\\1c&H3A3A3A&}%s",
                MENU_X, y, FONT, ("─"):rep(30)
            ))

        elseif item.type == "res" then
            -- ── Resolution row ───────────────────────────────────────────────
            res_idx = res_idx + 1
            local cursor = is_sel and "▶  " or "    "
            local active = (res_idx == current)

            local color
            if active and is_sel then
                color = "\\1c&H00FF88&"   -- bright green  (selected + applied)
            elseif active then
                color = "\\1c&H00AA55&"   -- muted green   (applied, not selected)
            elseif is_sel then
                color = "\\1c&H00FFFF&"   -- cyan          (selected)
            else
                color = "\\1c&HDDDDDD&"   -- off-white     (inactive)
            end

            local tick = active and "  ✓" or ""
            table.insert(lines, string.format(
                "{\\an7\\pos(%d,%d)\\fn%s\\fs15\\bord1.5%s}%s%s%s",
                MENU_X, y, FONT, color, cursor, get_label(item.res), tick
            ))

        elseif item.type == "premium" then
            -- ── Premium toggle row ───────────────────────────────────────────
            local prem   = is_premium_active()
            local cursor = is_sel and "▶  " or "    "
            local icon   = prem and "★" or "☆"
            local state  = prem and "ON   (enhanced bitrate)" or "OFF  (standard quality)"
            local label  = string.format("%s  Premium Mode   %s", icon, state)

            local color
            if prem and is_sel then
                color = "\\1c&H00AAFF&"   -- bright gold/orange (active + selected)
            elseif prem then
                color = "\\1c&H006699&"   -- muted gold         (active, not selected)
            elseif is_sel then
                color = "\\1c&H00FFFF&"   -- cyan               (selected, off)
            else
                color = "\\1c&HBBBBBB&"   -- grey               (inactive, not selected)
            end

            table.insert(lines, string.format(
                "{\\an7\\pos(%d,%d)\\fn%s\\fs15\\bord1.5%s}%s%s",
                MENU_X, y, FONT, color, cursor, label
            ))

        elseif item.type == "lyra" then
            -- ── Lyra audio-only toggle row ───────────────────────────────────
            local lyr    = is_lyra_active()
            local cursor = is_sel and "▶  " or "    "
            local icon   = lyr and "♫" or "♪"
            local state  = lyr and "ON   (audio only)" or "OFF"
            local label  = string.format("%s  Lyra Mode   %s", icon, state)

            local color
            if lyr and is_sel then
                color = "\\1c&H00FF88&"   -- bright green (active + selected)
            elseif lyr then
                color = "\\1c&H00CC66&"   -- muted green  (active, not selected)
            elseif is_sel then
                color = "\\1c&H00FFFF&"   -- cyan         (selected, off)
            else
                color = "\\1c&HBBBBBB&"   -- grey         (inactive, not selected)
            end

            table.insert(lines, string.format(
                "{\\an7\\pos(%d,%d)\\fn%s\\fs15\\bord1.5%s}%s%s",
                MENU_X, y, FONT, color, cursor, label
            ))
        end
    end

    -- ── Footer hint ──────────────────────────────────────────────────────────
    local hint_y = item_y(#items + 1)
    table.insert(lines, string.format(
        "{\\an7\\pos(%d,%d)\\fn%s\\fs9\\bord0\\1c&H555555&}ENTER  select     ESC  close",
        MENU_X, hint_y, FONT
    ))

    return table.concat(lines, "\n")
end

render = function()
    local ow, oh = mp.get_osd_size()
    overlay.res_x = (ow and ow > 0) and ow or 1920
    overlay.res_y = (oh and oh > 0) and oh or 1080
    overlay.data = build_menu()
    overlay:update()
end

-- ─────────────────────────────────────────────────────────────────────────────
-- APPLY RESOLUTION-- ─────────────────────────────────────────────────────────────────────────────
-- APPLY RESOLUTION
-- ─────────────────────────────────────────────────────────────────────────────
local function apply_res(res_item_index)
    local rank = 0
    for i = 1, res_item_index do
        if items[i] and items[i].type == "res" then
            rank = rank + 1
        end
    end
    current = rank

    local r = items[res_item_index].res
    if r.w == nil then
        -- Source resolution: no vf filter needed.
        -- Use the zero-copy hwdec path — frames stay entirely in GPU memory.
        mp.set_property("hwdec", "d3d11va")
        mp.commandv("vf", "clr", "")
        show_center(get_label(r), "hwdec: d3d11va  (zero-copy)", 2)
    else
        -- Scaled resolution: a vf=scale filter is required.
        -- FIX: Use d3d11va-copy instead of hwdec=no.
        --   hwdec=no  → pure software decode. For AV1/VP9 1080p this costs
        --               significant CPU (full decode in software).
        --   d3d11va-copy → GPU still decodes the bitstream; one GPU→CPU copy
        --                  per frame is done so the vf filter chain can run.
        --                  Much cheaper than software decode.
        mp.set_property("hwdec", "d3d11va-copy")
        mp.commandv("vf", "set", string.format("scale=%d:%d", r.w, r.h))
        show_center(get_label(r), "Scaled output  ·  hwdec: d3d11va-copy", 2)
    end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- SHOW / HIDE
-- ─────────────────────────────────────────────────────────────────────────────
local function hide()
    visible = false
    overlay:remove()
    mp.remove_key_binding("res-up")
    mp.remove_key_binding("res-down")
    mp.remove_key_binding("res-enter")
    mp.remove_key_binding("res-esc")
end

local function show()
    local resolutions = get_available_resolutions()
    items = build_items(resolutions)

    if not is_selectable(items, selected) then selected = 1 end
    if selected > #items then selected = 1 end
    if current > #resolutions then current = 1 end

    visible = true

    -- Sync Lyra state from lyra_mode.lua before rendering the menu
    mp.command("script-message-to lyra_mode lyra-state-query")

    render()

    mp.add_forced_key_binding("UP",    "res-up",    function()
        selected = next_selectable(items, selected, -1)
        render()
    end)
    mp.add_forced_key_binding("DOWN",  "res-down",  function()
        selected = next_selectable(items, selected, 1)
        render()
    end)
    mp.add_forced_key_binding("ENTER", "res-enter", function()
        local item = items[selected]
        if not item then hide(); return end

        if item.type == "res" then
            apply_res(selected)
            hide()
        elseif item.type == "premium" then
            -- Delegate to premium_toggle.lua; close menu first so the
            -- premium OSD banner is clearly visible.
            hide()
            mp.command("script-message-to premium_toggle premium-toggle")
        elseif item.type == "lyra" then
            -- Delegate to lyra_mode.lua; close menu first so the
            -- Lyra overlay has a clean transition.
            hide()
            mp.command("script-message-to lyra_mode lyra-toggle")
        end
    end)
    mp.add_forced_key_binding("ESC", "res-esc", hide)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- FILE-LOADED RESET
-- Resets to source resolution and restores zero-copy hwdec path on every
-- new file load. Clears any vf filter left from a previous scaled selection.
-- ─────────────────────────────────────────────────────────────────────────────
mp.register_event("file-loaded", function()
    current  = 1
    selected = 1
    mp.set_property("hwdec", "d3d11va")   -- always reset to zero-copy on new file
    mp.commandv("vf", "clr", "")
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- ENTRY POINT
-- ─────────────────────────────────────────────────────────────────────────────
mp.register_script_message("toggle-res-menu", function()
    if visible then hide() else show() end
end)
