-- youtube-channel-next.lua
-- When you press > on a YouTube video, loads the next video from the SAME channel.
-- Channel video list is fetched in the background as soon as a video loads,
-- so pressing > is usually instant.
--
-- FIX: Added a 3-second startup delay before spawning any yt-dlp subprocess.
-- Previously, the channel_url resolution subprocess fired immediately on
-- file-loaded, racing with the demuxer buffer fill and compounding the initial
-- network load. The delay gives the demuxer time to fill its forward buffer
-- before any background process competes for CPU and bandwidth.
--
-- Place in: portable_config/scripts/youtube-channel-next.lua

local mp    = require 'mp'
local utils = require 'mp.utils'

-- ── Config ────────────────────────────────────────────────────────────────────
-- FIX: use bare "yt-dlp" so it resolves via PATH — no hardcoded absolute path.
-- yt-dlp must be accessible from PATH (or place yt-dlp.exe next to mpv.exe).
local YTDLP       = "yt-dlp"
local FETCH_COUNT = 30   -- how many channel videos to fetch ahead

-- Delay (seconds) after file-loaded before spawning any yt-dlp subprocess.
-- This gives the demuxer buffer time to fill before background processes
-- compete for CPU and network bandwidth. Adjust down if your connection is
-- fast and you want quicker > key response on first press.
local FETCH_DELAY = 3.0
-- ──────────────────────────────────────────────────────────────────────────────

-- Cache: channel_url -> { list = {url, ...}, index = N }
local channel_cache   = {}
local current_channel = nil   -- channel URL of currently playing video
local fetch_in_progress = {}  -- set of channel_urls currently being fetched

-- Track the pending delay timer so we can cancel it if the user loads a new
-- file before the delay fires (avoids a stale subprocess on rapid file switches).
local pending_fetch_timer = nil

local function is_youtube(url)
    return url and (
        url:match("youtube%.com/watch") or
        url:match("youtu%.be/") or
        url:match("youtube%.com/shorts/")
    )
end

-- ── Fetch channel video list asynchronously ───────────────────────────────────
local function fetch_channel_videos(channel_url, on_done)
    if fetch_in_progress[channel_url] then return end
    fetch_in_progress[channel_url] = true

    -- Append /videos to get the uploads tab
    local videos_url = channel_url:gsub("/?$", "") .. "/videos"

    mp.command_native_async({
        name           = "subprocess",
        capture_stdout = true,
        playback_only  = false,
        args = {
            YTDLP,
            "--no-warnings",
            "--flat-playlist",
            "--print", "url",
            "--playlist-end", tostring(FETCH_COUNT),
            videos_url
        }
    }, function(success, result)
        fetch_in_progress[channel_url] = nil
        if not success or result.status ~= 0 then
            if on_done then on_done(nil) end
            return
        end

        local urls = {}
        for line in result.stdout:gmatch("[^\r\n]+") do
            if line:match("^https://") then
                table.insert(urls, line)
            end
        end

        if #urls > 0 then
            channel_cache[channel_url] = { list = urls, index = 0 }
            mp.msg.info(("yt-channel: cached %d videos for %s"):format(#urls, channel_url))
        end

        if on_done then on_done(channel_cache[channel_url]) end
    end)
end

-- ── On file load: resolve channel URL and pre-fetch in background ─────────────
mp.register_event("file-loaded", function()
    local url = mp.get_property("path")

    -- Cancel any pending fetch timer from a previous load (rapid file switching)
    if pending_fetch_timer then
        pending_fetch_timer:kill()
        pending_fetch_timer = nil
    end

    if not is_youtube(url) then
        current_channel = nil
        return
    end

    -- FIX: Delay subprocess spawn by FETCH_DELAY seconds after file-loaded.
    -- Previously this fired immediately, racing with the demuxer buffer fill.
    -- A cold yt-dlp --no-download call takes 1.5–4s and consumes network +
    -- CPU during the exact window mpv needs to fill its forward buffer.
    pending_fetch_timer = mp.add_timeout(FETCH_DELAY, function()
        pending_fetch_timer = nil

        -- Resolve channel_url from the video (async, runs in background)
        mp.command_native_async({
            name           = "subprocess",
            capture_stdout = true,
            playback_only  = false,
            args = {
                YTDLP,
                "--no-warnings",
                "--print", "channel_url",
                "--no-download",
                url
            }
        }, function(success, result)
            if not success or result.status ~= 0 or not result.stdout then return end

            local chan = result.stdout:gsub("[%s\r\n]+$", "")
            if chan == "" then return end

            -- Verify the user is still on the same video — if they navigated
            -- away during the delay, don't pollute current_channel state.
            local current_url = mp.get_property("path")
            if current_url ~= url then
                mp.msg.info("yt-channel: URL changed during fetch delay, discarding channel resolve")
                return
            end

            current_channel = chan
            mp.msg.info("yt-channel: current channel → " .. chan)

            -- Pre-fetch channel videos if not already cached
            if not channel_cache[chan] then
                fetch_channel_videos(chan, nil)  -- fire and forget
            end
        end)
    end)
end)

-- ── Handle > key (registered via script-message from input.conf) ──────────────
local function go_next()
    local url = mp.get_property("path")

    -- Not YouTube → normal playlist-next
    if not is_youtube(url) or not current_channel then
        mp.command("playlist-next")
        return
    end

    local cached = channel_cache[current_channel]

    if not cached then
        -- Nothing fetched yet — fetch now and wait
        mp.osd_message("⏳ Fetching channel…", 3)
        fetch_channel_videos(current_channel, function(data)
            if not data or #data.list == 0 then
                mp.osd_message("❌ Could not fetch channel videos", 3)
                return
            end
            data.index = 1
            mp.commandv("loadfile", data.list[1])
            mp.osd_message(("▶ Channel  1 / %d"):format(#data.list), 2)
        end)
        return
    end

    -- Advance index, loop around at the end
    cached.index = cached.index + 1
    if cached.index > #cached.list then
        cached.index = 1
    end

    local next_url = cached.list[cached.index]
    mp.commandv("loadfile", next_url)
    mp.osd_message(("▶ Channel  %d / %d"):format(cached.index, #cached.list), 2)
end

mp.register_script_message("yt-channel-next", go_next)
