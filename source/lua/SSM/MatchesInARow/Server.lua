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
--   * Rounds shorter than MinimumRoundSeconds are void: nobody's count changes.
--   * Minutes are the player's own time on a team, added up over the rounds in the count.
--
-- Counts only change when a round ends, because that is when the server decides who spectates.
--
-- The server's Lua restarts on every map change, so counts are saved to a config file and read
-- back on load. After ForgetAfterMinutes with nobody playing a round, counts are dropped, so each
-- day's play session starts from scratch. "Playing" is refreshed every kActiveSaveSeconds during a
-- round, so a server that restarts deep into a 70-minute round still keeps its counts.
--
-- The counts are only ever shown through two commands, which need Shine: sud_streaks
-- (console) and !streaks (chat, seen only by whoever typed it) list the 5 connected players
-- with the most rounds in a row and the 5 with the most minutes. Open to everyone, for
-- transparency. Without Shine the commands simply do not exist. Nothing is sent to clients and
-- the mod has no client files.

local kSettingsFile = "SSM_MatchesInARow.json"
local kDataFile = "SSM_MatchesInARowData.json"

local kDefaultSettings = {
    GracePeriodSeconds = 120,
    MinimumRoundSeconds = 180,
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

-- [steamId] = { rounds = number, minutes = number }. Only players with a count of 1 or more.
local Streaks = {}

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
        players[#players + 1] = { id = steamId, rounds = streak.rounds, minutes = streak.minutes }
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
        and type(entry.rounds) == "number" and type(entry.minutes) == "number" then
            Streaks[entry.id] = { rounds = entry.rounds, minutes = entry.minutes }
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
        return
    end

    -- Everyone not in fromStart (subs, spectators, absent players) simply has no entry any more,
    -- which is what a count of 0 is.
    local newStreaks = {}
    for steamId in pairs(round.fromStart) do
        local previous = Streaks[steamId]
        local minutes = math.floor((round.seconds[steamId] or 0) / 60 + 0.5)

        newStreaks[steamId] = {
            rounds = (previous and previous.rounds or 0) + 1,
            minutes = (previous and previous.minutes or 0) + minutes
        }
    end

    Streaks = newStreaks
    LastActiveAt = Shared.GetSystemTime()

    Save()
end

-- Streaks: top 5 of each list ------------------------------------------------------------------

local kTopCount = 5

-- Connected players with a count, as { name, rounds, minutes }.
local function GetConnectedStreaks()
    local list, seen = {}, {}

    Server.ForAllPlayers(function(player)
        local steamId = GetSteamId(player)
        local streak = steamId and Streaks[steamId]
        if streak and not seen[steamId] then
            seen[steamId] = true
            list[#list + 1] = { name = player:GetName(), rounds = streak.rounds, minutes = streak.minutes }
        end
    end)

    return list
end

-- "Bleu 4r, Pepe 4r, ..." ranked by `first`, ties broken by `second`, then by name.
local function FormatTop(list, first, second, suffix)
    table.sort(list, function(a, b)
        if a[first] ~= b[first] then
            return a[first] > b[first]
        end
        if a[second] ~= b[second] then
            return a[second] > b[second]
        end
        return a.name < b.name
    end)

    local parts = {}
    for i = 1, math.min(kTopCount, #list) do
        parts[i] = string.format("%s %d%s", list[i].name, list[i][first], suffix)
    end

    return table.concat(parts, ", ")
end

function SSM_MatchesInARow_GetStreaksLines()
    local list = GetConnectedStreaks()
    if #list == 0 then
        return { "Nobody has played a round in a row yet." }
    end

    return {
        "Most rounds in a row: " .. FormatTop(list, "rounds", "minutes", "r"),
        "Most minutes in a row: " .. FormatTop(list, "minutes", "rounds", "m")
    }
end

local function OnStreaks(client)
    local fromChat = Shine:IsCommandFromChat()

    for _, line in ipairs(SSM_MatchesInARow_GetStreaksLines()) do
        if not client then
            Shared.Message(line)
        elseif fromChat then
            -- Goes to this client only.
            Shine:NotifyDualColour(client, 180, 180, 180, "[Matches In A Row]", 255, 255, 255, line)
        else
            ServerAdminPrint(client, line)
        end
    end
end

-- Shine is another mod, and the order mods load in is not guaranteed, so this waits until the
-- server is running rather than looking for Shine when this file loads.
local commandsRegistered = false
local function RegisterCommands()
    commandsRegistered = true

    if not (Shine and Shine.RegisterCommand and Shine.Commands) then
        return
    end

    local command = Shine:RegisterCommand("sud_streaks", "streaks", OnStreaks, true)
    command:Help("Lists the 5 players with the most rounds in a row and the 5 with the most minutes.")
end

local function OnUpdateServer()
    if not commandsRegistered then
        RegisterCommands()
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

Load()
