-- Matches In A Row - server side.
--
-- Counts how many rounds in a row each player has played, and for how many minutes, so anyone
-- can check who has had their turn when a spectator is waiting for a slot.
--
-- Rules:
--   * A round counts for a player when they were on Marines or Aliens at any moment of its first
--     GracePeriodSeconds. Leaving and coming back later does not undo that, so hopping to the
--     spectators mid-round cannot wipe a count.
--   * Anyone who first joins a team after the grace period is a sub. For them the round counts as
--     a round sat out, so their count goes back to 0. That rewards subbing in.
--   * Sitting a round out (spectator, ready room or not connected) also puts the count back to 0.
--   * Rounds shorter than MinimumRoundSeconds do not count as a round: nobody's round count goes
--     up and nobody is reset. Their time still counts, though: anyone already on a run gets the
--     time they played added to their minutes.
--   * Minutes are the player's own time on a team, added up over the rounds in the count. Kept in
--     seconds and only rounded for display, so a short round adds its partial minute properly.
--
-- Counts only change when a round ends, because that is when the server decides who spectates.
--
-- The server's Lua restarts on every map change, so counts are saved to a config file and read
-- back on load. After ForgetAfterMinutes with nobody playing a round, counts are dropped, so each
-- day's play session starts from scratch. "Playing" is refreshed every kActiveSaveSeconds during a
-- round, so a server that restarts deep into a 70-minute round still keeps its counts.
--
-- The counts are only ever shown through commands, open to everyone for transparency:
-- sud_streaks (console) lists every connected player with a count, ranked by rounds and by
-- minutes; !streakr and !streakm (chat, seen only by whoever typed it) give the top 5 by rounds
-- and by minutes. The console command needs nothing else; the chat commands need Shine.
-- Nothing else is sent to clients and the mod has no client files.

local kSettingsFile = "SSM_MatchesInARow.json"
local kDataFile = "SSM_MatchesInARowData.json"

local kDefaultSettings = {
    GracePeriodSeconds = 120,
    MinimumRoundSeconds = 60,
    ForgetAfterMinutes = 60
}

local Settings = LoadConfigFile(kSettingsFile, kDefaultSettings)
if type(Settings) ~= "table" then
    Settings = {}
end

local settingsChanged = false
for key, value in pairs(kDefaultSettings) do
    if type(Settings[key]) ~= "number" then
        Settings[key] = value
        settingsChanged = true
    end
end
if settingsChanged then
    SaveConfigFile(kSettingsFile, Settings)
end

-- [steamId] = { rounds = number, seconds = number }. Only players with a count of 1 or more.
local Streaks = {}

local function Minutes(seconds)
    return math.floor(seconds / 60 + 0.5)
end

local kActiveSaveSeconds = 300

-- System time (seconds) someone was last playing a round, or nil if none is known.
local LastActiveAt
local lastActiveSaveTime = 0

-- The round being played, or nil outside one:
-- { startTime = Shared.GetTime() at round start, seconds = { [steamId] = seconds on a team },
--   fromStart = { [steamId] = true when on a team during the grace period } }
local Round
local lastSampleTime = 0

local function GetSteamId(player)
    local client = Server.GetOwner(player)
    if client and not client:GetIsVirtual() then
        local steamId = client:GetUserId()
        if steamId and steamId > 0 then
            return steamId
        end
    end
end

-- Saved as a list rather than a table keyed by Steam ID: JSON object keys always come back as
-- strings, and the counts are looked up by number.
local function Save()
    local players = {}
    for steamId, streak in pairs(Streaks) do
        players[#players + 1] = { id = steamId, rounds = streak.rounds, seconds = streak.seconds }
    end

    SaveConfigFile(kDataFile, { SavedAt = LastActiveAt, Players = players })
end

local function IsForgotten()
    return LastActiveAt ~= nil
        and Shared.GetSystemTime() - LastActiveAt > Settings.ForgetAfterMinutes * 60
end

local function Load()
    local data = LoadConfigFile(kDataFile)
    if type(data) ~= "table" or type(data.SavedAt) ~= "number" or type(data.Players) ~= "table" then
        return
    end

    LastActiveAt = data.SavedAt
    if IsForgotten() then
        return
    end

    for _, entry in ipairs(data.Players) do
        if type(entry) == "table" and type(entry.id) == "number"
        and type(entry.rounds) == "number" and type(entry.seconds) == "number" then
            Streaks[entry.id] = { rounds = entry.rounds, seconds = entry.seconds }
        end
    end
end

-- Adds the time since the last sample to everyone on a team.
local function Sample(now)
    local elapsed = now - lastSampleTime
    lastSampleTime = now

    local inGracePeriod = now - Round.startTime <= Settings.GracePeriodSeconds

    Server.ForAllPlayers(function(player)
        local teamNumber = player:GetTeamNumber()
        if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then
            return
        end

        local steamId = GetSteamId(player)
        if not steamId then
            return
        end

        Round.seconds[steamId] = (Round.seconds[steamId] or 0) + elapsed
        if inGracePeriod then
            Round.fromStart[steamId] = true
        end
    end)
end

-- Records that a round is being played right now, and saves it so a restart sees it too.
local function MarkActive(now)
    LastActiveAt = Shared.GetSystemTime()
    lastActiveSaveTime = now
    Save()
end

local function StartRound(startTime, now)
    Round = { startTime = startTime, seconds = {}, fromStart = {} }
    lastSampleTime = now

    -- The server can sit on one map for hours with nobody playing, so the age check on load is
    -- not enough on its own.
    if IsForgotten() then
        Streaks = {}
    end

    MarkActive(now)
    Sample(now)
end

local function EndRound()
    if not Round then
        return
    end

    local now = Shared.GetTime()
    Sample(now)

    local round = Round
    Round = nil

    if now - round.startTime < Settings.MinimumRoundSeconds then
        -- Too short to count as a round, so no round counts change and nobody is reset, but the
        -- time played still goes on the minutes of anyone already on a run.
        for steamId, streak in pairs(Streaks) do
            streak.seconds = streak.seconds + (round.seconds[steamId] or 0)
        end
    else
        -- Everyone not in fromStart (subs, spectators, absent players) simply has no entry any
        -- more, which is what a count of 0 is.
        local newStreaks = {}
        for steamId in pairs(round.fromStart) do
            local previous = Streaks[steamId]

            newStreaks[steamId] = {
                rounds = (previous and previous.rounds or 0) + 1,
                seconds = (previous and previous.seconds or 0) + (round.seconds[steamId] or 0)
            }
        end

        Streaks = newStreaks
    end

    LastActiveAt = Shared.GetSystemTime()

    Save()
end

-- Streaks: the two rankings ------------------------------------------------------------------

-- Chat has little room, so each chat command shows one ranking, top 5; the console gets
-- everyone, both ways.
local kChatCount = 5

-- The two rankings. Each shows only the value it is sorted by.
local kRankings = {
    rounds = { header = "Players sorted by rounds played", first = "rounds", second = "minutes", suffix = "r" },
    minutes = { header = "Players sorted by minutes played", first = "minutes", second = "rounds", suffix = "m" }
}

-- Chat commands and the ranking each one shows.
local kChatCommands = {
    ["!streakr"] = "rounds", ["/streakr"] = "rounds",
    ["!streakm"] = "minutes", ["/streakm"] = "minutes"
}

-- Connected players with a count, as { name, rounds, minutes }.
local function GetConnectedStreaks()
    local list, seen = {}, {}

    Server.ForAllPlayers(function(player)
        local steamId = GetSteamId(player)
        local streak = steamId and Streaks[steamId]
        if streak and not seen[steamId] then
            seen[steamId] = true
            list[#list + 1] = { name = player:GetName(), rounds = streak.rounds, minutes = Minutes(streak.seconds) }
        end
    end)

    return list
end

local kNobody = "No rounds have been counted yet this session."

-- Ranks by `first`, ties broken by `second`, then by name.
local function Rank(list, first, second)
    table.sort(list, function(a, b)
        if a[first] ~= b[first] then
            return a[first] > b[first]
        end
        if a[second] ~= b[second] then
            return a[second] > b[second]
        end
        return a.name < b.name
    end)
end

-- The named rankings as { text, isListRow } pairs, `count` players each (nil for everyone).
local function BuildRankings(kinds, count)
    local list = GetConnectedStreaks()
    if #list == 0 then
        return { { kNobody } }
    end

    local lines = {}
    for _, kind in ipairs(kinds) do
        local ranking = kRankings[kind]
        lines[#lines + 1] = { ranking.header }
        Rank(list, ranking.first, ranking.second)
        for i = 1, math.min(count or #list, #list) do
            local entry = list[i]
            lines[#lines + 1] = { string.format("%d. %s  %d%s", i, entry.name, entry[ranking.first], ranking.suffix), true }
        end
    end

    return lines
end

-- For chat, one ranking ("rounds" or "minutes"): the header carries the [NS2 SUD] tag, the
-- player rows continue under it.
function SSM_MatchesInARow_GetChatLines(kind)
    return BuildRankings({ kind }, kChatCount)
end

-- For the console: everyone, both rankings, indented under the headers, a blank line between.
function SSM_MatchesInARow_GetConsoleLines()
    local lines = {}
    for i, line in ipairs(BuildRankings({ "rounds", "minutes" }, nil)) do
        if not line[2] and i > 1 then
            lines[#lines + 1] = ""
        end
        lines[#lines + 1] = line[2] and ("  " .. line[1]) or line[1]
    end
    return lines
end

-- sud_streaks in the console. A plain game console command rather than a Shine one: Shine logs
-- every command it runs to the admins' consoles, and this needs no Shine at all.
local function OnConsoleStreaks(client)
    for _, line in ipairs(SSM_MatchesInARow_GetConsoleLines()) do
        SSM.Print(client, line)
    end
end

-- !streakr / !streakm (or with /) in chat, answered to that player only. Returning "" drops the
-- typed message, so nobody else sees the command either.
local function OnPlayerSay(client, message)
    local text = message and message.message
    if type(text) ~= "string" then
        return
    end

    local kind = kChatCommands[string.lower(text:match("^%s*(.-)%s*$"))]
    if not kind then
        return
    end

    for _, line in ipairs(SSM_MatchesInARow_GetChatLines(kind)) do
        SSM.Notify(client, line[1], line[2])
    end

    return ""
end

-- Chat commands are caught through Shine's PlayerSay hook (without becoming a Shine plugin).
-- Shine is another mod and the order mods load in is not guaranteed, so this waits until the
-- server is running rather than looking for Shine when this file loads.
local chatHooked = false
local function HookChat()
    chatHooked = true

    if Shine and Shine.Hook and Shine.Hook.Add then
        Shine.Hook.Add("PlayerSay", "SSM_MatchesInARow", OnPlayerSay)
    end
end

local function OnUpdateServer()
    if not chatHooked then
        HookChat()
    end

    local gamerules = GetGamerules()
    if not gamerules then
        return
    end

    local now = Shared.GetTime()

    if gamerules:GetGameStarted() then
        if not Round then
            StartRound(gamerules:GetGameStartTime(), now)
        elseif now - lastSampleTime >= 1 then
            Sample(now)

            if now - lastActiveSaveTime >= kActiveSaveSeconds then
                MarkActive(now)
            end
        end
    elseif Round then
        -- The round stopped without ending (a reset or a map change mid-round), so nothing counts.
        Round = nil
    end
end

local oldEndGame
oldEndGame = Class_ReplaceMethod("NS2Gamerules", "EndGame", function(self, ...)
    oldEndGame(self, ...)
    EndRound()
end)

Event.Hook("UpdateServer", OnUpdateServer)
Event.Hook("Console_sud_streaks", OnConsoleStreaks)

Load()
