local mp = require "mp"
local utils = require "mp.utils"

local config_dir = mp.command_native({"expand-path", "~~/"})
local package_dir = mp.command_native({"expand-path", "~~/../"})
local ytdlp_path = package_dir .. "/yt-dlp.exe"
local deno_path = package_dir .. "/deno.exe"
local download_dir = config_dir .. "/downloads"
local temp_dir = download_dir .. "/_incomplete"
local running = false

local function exists(path)
    return path and utils.file_info(path) ~= nil
end

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

    local ytdlp = exists(ytdlp_path) and ytdlp_path or "yt-dlp.exe"
    local args = {
        ytdlp,
        "-P", "home:" .. download_dir,
        "-P", "temp:" .. temp_dir,
        "--no-playlist",
        "--newline",
    }

    if exists(deno_path) then
        table.insert(args, "--js-runtimes")
        table.insert(args, "deno:" .. deno_path:gsub("\\\\", "/"))
    end
    table.insert(args, url)

    running = true
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
            mp.osd_message("yt-dlp stopped/failed", 4)
        end
    end)

    mp.osd_message("yt-dlp started → " .. download_dir, 4)
end

mp.add_key_binding(nil, "download_current", start_ytdlp_download)
