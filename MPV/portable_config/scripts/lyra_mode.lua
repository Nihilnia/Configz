-- lyra_mode.lua
-- Freeze the currently visible frame while audio keeps playing.

local mp = require "mp"

local active = false

local function broadcast(state)
    mp.commandv("script-message", "lyra-state-changed", state)
end

local function enter()
    if active then return end
    active = true

    -- Infinitely loop the current frame: VO keeps receiving frames (UI stays
    -- alive) but every frame is the same frozen image. Audio is unfiltered.
    mp.commandv("vf", "add", "@lyra:lavfi=[loop=-1:1:0]")

    mp.osd_message("Lyra Mode ON")
    broadcast("yes")
end

local function exit()
    if not active then return end
    active = false

    mp.commandv("vf", "remove", "@lyra")

    mp.osd_message("Lyra Mode OFF")
    broadcast("no")
end

local function toggle()
    if active then
        exit()
    else
        enter()
    end
end

mp.register_script_message("lyra-toggle", toggle)

mp.register_script_message("lyra-state-query", function()
    broadcast(active and "yes" or "no")
end)

mp.register_event("end-file", function()
    if active then
        active = false
        broadcast("no")
    end
end)
