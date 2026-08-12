-- pip_manager.lua
-- Handles Picture-in-Picture toggling with correct fullscreen and ontop behavior.
--
-- Fixes two bugs with Tethys's built-in toggle-pip:
--   1. PiP → Fullscreen: `ontop` property remained set, floating over fullscreen.
--   2. Fullscreen → PiP: geometry was applied before fullscreen exited, leaving
--      a full-size window repositioned to the bottom-left corner.
--
-- How it works:
--   - Receives the "pip-managed" script-message (bound to p/P in input.conf).
--   - Tracks PiP state internally.
--   - On ENTER PiP from fullscreen: exits fullscreen first, waits for the window
--     manager to finish the transition (via property observer), then applies PiP.
--   - On EXIT PiP via fullscreen key (Enter/F): a fullscreen property observer
--     detects the transition and clears ontop automatically.
--
-- Placement: ~~/scripts/pip_manager.lua

local mp = require "mp"

-- ── Config ────────────────────────────────────────────────────────────────────
-- Match your tethys.conf pipGeometry. Negative offsets = from right/bottom edge.
local PIP_GEOMETRY    = "33%-10-10"

-- Position to restore when leaving PiP (matches mpv.conf geometry=50%:50%).
-- window-scale=1.0 resets the window size to native video resolution,
-- clamped by your autofit-larger=70%x70% setting in mpv.conf.
local NORMAL_GEOMETRY = "50%:50%"
-- ──────────────────────────────────────────────────────────────────────────────

local pip_active = false

-- ── Enter PiP ─────────────────────────────────────────────────────────────────
local function do_pip_enter()
    mp.set_property("geometry", PIP_GEOMETRY)
    mp.set_property_bool("ontop", true)
    mp.osd_message("▣  PiP: On", 2)
end

local function enter_pip()
    pip_active = true

    if mp.get_property_bool("fullscreen") then
        -- Must exit fullscreen first, then wait for the WM to finish the
        -- transition before applying geometry — otherwise the window is
        -- resized while still in FS mode and lands at full-size bottom-left.
        mp.set_property_bool("fullscreen", false)

        -- Observe the fullscreen property until it flips to false.
        local observer
        observer = function(_, is_fs)
            if not is_fs then
                mp.unobserve_property(observer)
                -- Tiny extra delay for the window manager to settle the frame.
                mp.add_timeout(0.05, do_pip_enter)
            end
        end
        mp.observe_property("fullscreen", "bool", observer)
    else
        do_pip_enter()
    end
end

-- ── Exit PiP ──────────────────────────────────────────────────────────────────
local function exit_pip()
    pip_active = false
    mp.set_property_bool("ontop", false)
    -- Reset window size back to native (clamped by autofit-larger in mpv.conf),
    -- then re-center via geometry.
    mp.set_property_number("window-scale", 1.0)
    mp.set_property("geometry", NORMAL_GEOMETRY)
    mp.osd_message("▣  PiP: Off", 2)
end

-- ── Public toggle (bound via input.conf: script-message-to pip_manager pip-managed) ──
mp.register_script_message("pip-managed", function()
    if pip_active then
        exit_pip()
    else
        enter_pip()
    end
end)

-- ── Safety net: fullscreen activated while PiP is on ─────────────────────────
-- Handles the case where the user presses Enter/F to go fullscreen while PiP
-- is active — without this, ontop=yes would persist over the fullscreen window.
mp.observe_property("fullscreen", "bool", function(_, is_fs)
    if is_fs and mp.get_property_bool("ontop") then
        mp.set_property_bool("ontop", false)
        -- Sync our state — PiP is implicitly over when fullscreen takes hold.
        if pip_active then
            pip_active = false
            mp.msg.info("pip_manager: fullscreen triggered, PiP state cleared")
        end
    end
end)
