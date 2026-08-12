-- rgx_enhance.lua
-- Toggles "RGX Enhance" mode — Opera GX-style video enhancement via mpv's
-- native GPU post-processing pipeline (no external filters, hwdec-safe).
--
-- What it does:
--   Sharpness  +18  →  Edges crisper, fine detail recovered
--   Saturation +15  →  Colours more vivid
--   Contrast    +6  →  Mild lift — punches up perceived depth
--   Gamma       −4  →  Slight negative gamma pulls out shadow detail
--
-- Toggle key: Alt+e  (set in input.conf)
-- Persists across files in the same session; resets on mpv restart.

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

    local body
    if line2 then
        body = string.format(
            "{\\an5\\pos(960,540)\\fn%s\\fs48\\bord2.5\\1c&HFFFFFF&\\3c&H000000&}%s"  ..
            "\\N{\\fn%s\\fs40\\bord1.5\\1c&HBBBBBB&\\3c&H000000&}%s",
            FONT, line1, FONT, line2
        )
    else
        body = string.format(
            "{\\an5\\pos(960,540)\\fn%s\\fs48\\bord2.5\\1c&HFFFFFF&\\3c&H000000&}%s",
            FONT, line1
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
-- ENHANCEMENT PROFILE
-- ─────────────────────────────────────────────────────────────────────────────
local PROFILE = {
    sharpness  =  18,
    saturation =  15,
    contrast   =   6,
    gamma      =  -4,
}

-- ─────────────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────────────
local enhanced = false
local baseline = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- APPLY / RESTORE
-- ─────────────────────────────────────────────────────────────────────────────
local props = { "sharpness", "saturation", "contrast", "gamma" }

local function apply_enhance()
    for _, prop in ipairs(props) do
        baseline[prop] = mp.get_property_number(prop) or 0
    end
    for prop, value in pairs(PROFILE) do
        mp.set_property_number(prop, value)
    end
    enhanced = true
    show_center(
        "RGX Enhance  —  ON",
        string.format("Sharp +%d  ·  Sat +%d  ·  Con +%d  ·  Gam %d",
            PROFILE.sharpness, PROFILE.saturation, PROFILE.contrast, PROFILE.gamma),
        3
    )
end

local function restore_baseline()
    for _, prop in ipairs(props) do
        mp.set_property_number(prop, baseline[prop] or 0)
    end
    enhanced = false
    show_center("RGX Enhance  —  OFF", "Baseline restored", 2)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- PUBLIC TOGGLE
-- ─────────────────────────────────────────────────────────────────────────────
local function toggle_enhance()
    if not enhanced then apply_enhance() else restore_baseline() end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- HOOKS
-- ─────────────────────────────────────────────────────────────────────────────
mp.register_script_message("rgx-toggle", toggle_enhance)

-- Re-apply when a new file loads mid-session (mode persists across files)
mp.register_event("file-loaded", function()
    if enhanced then
        for prop, value in pairs(PROFILE) do
            mp.set_property_number(prop, value)
        end
    end
end)
