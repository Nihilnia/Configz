local mp = require "mp"

local ytdlp = "yt-dlp.exe"

-- Final completed downloads
local download_dir = "D:\\mpvDownloads"

-- Temporary/incomplete files
local temp_dir = "D:\\mpvDownloads\\_incomplete"

local running = false

local function strip_ytdl_prefix(url)
    if not url then return "" end
    return url:gsub("^ytdl://", "")
end

local function is_network_url(url)
    return url and url:match("^https?://") ~= nil
end

local function start_ytdlp_download()
    if running then
        mp.osd_message("yt-dlp: already running", 3)
        return
    end

    local url = strip_ytdl_prefix(mp.get_property("path", ""))

    if not is_network_url(url) then
        mp.osd_message("yt-dlp: not a network URL", 3)
        return
    end

    running = true

    local args = {
        ytdlp,

        -- Use your normal yt-dlp.conf.
        -- Do NOT use --ignore-config.

        -- Override only the output folders.
        "-P", "home:" .. download_dir,
        "-P", "temp:" .. temp_dir,

        -- Prevent playlist accidents.
        "--no-playlist",

        "--newline",

        url
    }

    mp.command_native_async({
        name = "subprocess",
        playback_only = false,
        capture_stdout = false,
        capture_stderr = false,
        args = args,
    }, function(success, result, error)
        running = false

        if result and result.killed_by_us then
            mp.osd_message("yt-dlp stopped with playback; resume later", 4)
        elseif result and result.status == 0 then
            mp.osd_message("yt-dlp finished", 3)
        else
            mp.osd_message("yt-dlp stopped/failed", 3)
        end
    end)

    mp.osd_message("yt-dlp started → D:\\mpvDownloads", 4)
end

mp.add_key_binding(nil, "download_current", start_ytdlp_download)