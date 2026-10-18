-- Matches In A Row - server side.
--
-- Counts how many rounds in a row each player has played, and for how many minutes, so everyone
-- can see who has had their turn when a spectator is waiting for a slot.
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
-- back on load. Counts older than ForgetAfterMinutes (time since the last counted round) are
-- dropped, so yesterday's games never show up today.

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

-- System time (seconds) of the last round that counted, or nil if none is known.
local LastCountedAt

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

local function SendStreak(client, steamId, streak)
    local message = {
        steamId = steamId,
        rounds = math.min(streak.rounds, 255),
        minutes = math.min(streak.minutes, 4095)
    }

    if client then
        Server.SendNetworkMessage(client, "SSM_MatchesInARow", message, true)
    else
        Server.SendNetworkMessage("SSM_MatchesInARow", message, true)
    end
end

-- Sends the whole list, to one client or (with nil) to everyone.
local function SendAll(client)
    if client then
        Server.SendNetworkMessage(client, "SSM_MatchesInARowClear", {}, true)
    else
        Server.SendNetworkMessage("SSM_MatchesInARowClear", {}, true)
    end

    for steamId, streak in pairs(Streaks) do
        SendStreak(client, steamId, streak)
    end
end

-- Saved as a list rather than a table keyed by Steam ID: JSON object keys always come back as
-- strings, and the counts are looked up by number.
local function Save()
    local players = {}
    for steamId, streak in pairs(Streaks) do
        players[#players + 1] = { id = steamId, rounds = streak.rounds, minutes = streak.minutes }
    end

    SaveConfigFile(kDataFile, { SavedAt = LastCountedAt, Players = players })
end

local function IsForgotten()
    return LastCountedAt ~= nil
        and Shared.GetSystemTime() - LastCountedAt > Settings.ForgetAfterMinutes * 60
end

local function Load()
    local data = LoadConfigFile(kDataFile)
    if type(data) ~= "table" or type(data.SavedAt) ~= "number" or type(data.Players) ~= "table" then
        return
    end

    LastCountedAt = data.SavedAt
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

local function StartRound(startTime, now)
    Round = { startTime = startTime, seconds = {}, fromStart = {} }
    lastSampleTime = now

    -- The server can sit on one map for hours with nobody playing, so the age check on load is
    -- not enough on its own.
    if IsForgotten() and next(Streaks) then
        Streaks = {}
        SendAll(nil)
    end

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
    LastCountedAt = Shared.GetSystemTime()

    Save()
    SendAll(nil)
end

local function OnUpdateServer()
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
        end
    elseif Round then
        -- The round stopped without ending (a reset or a map change mid-round), so nothing counts.
        Round = nil
    end
end

local function OnClientConnect(client)
    if client and not client:GetIsVirtual() then
        SendAll(client)
    end
end

local oldEndGame
oldEndGame = Class_ReplaceMethod("NS2Gamerules", "EndGame", function(self, ...)
    oldEndGame(self, ...)
    EndRound()
end)

Event.Hook("UpdateServer", OnUpdateServer)
Event.Hook("ClientConnect", OnClientConnect)

Load()
