-- custom_idle_logo.lua
-- Loads a custom logo.png from portable_config when the player is idle.

local mp = require 'mp'

local logo_path = mp.command_native({"expand-path", "~~/logo.png"})

local function file_exists(path)
    local f = io.open(path, "r")
    if f then f:close() return true else return false end
end

-- Listen for the player becoming idle
mp.observe_property("idle-active", "bool", function(name, idle)
    if idle and file_exists(logo_path) then
        mp.commandv("loadfile", logo_path)
    end
end)

-- Handle UI visibility when transitioning between logo and real videos
mp.register_event("file-loaded", function()
    local path = mp.get_property("path", "")
    
    if path == logo_path or path:match("logo%.png$") then
        -- We are playing the logo. Make it display infinitely and hide the UI.
        mp.set_property("image-display-duration", "inf")
        
        -- Force the image to 64x64, then pad it into a 1280x720 black canvas. 
        -- This forces the MPV window to open at a standard 720p default size!
        mp.commandv("vf", "add", "@idlelogo:lavfi=[scale=64:64:force_original_aspect_ratio=decrease,pad=1280:720:-1:-1:color=black]")
        
        mp.commandv("script-message", "osc-visibility", "never")
    else
        -- We are playing a real video. Restore normal behavior.
        
        -- Safely remove the logo scaling filter so real videos play normally
        mp.commandv("vf", "remove", "@idlelogo")
        
        mp.commandv("script-message", "osc-visibility", "auto")
    end
end)
