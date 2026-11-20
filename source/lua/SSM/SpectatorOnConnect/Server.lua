-- Spectator On Connect - server side.
--
-- Everyone who connects starts as a spectator instead of in the ready room. The server caps
-- people who are not spectators (16 on NS2 SUD) and people in total (21), not spectators as such,
-- and someone idling in the ready room uses up one of the 16. Starting everyone as a spectator
-- keeps a freed player slot free: when a player drops mid-round, a newcomer cannot take their slot
-- by sitting in the ready room. Joining a team from spectator is only let through while a player
-- slot is free (vanilla Gamerules:GetCanJoinPlayingTeam), the same as for any spectator today.
--
-- Rules (the author's picks, 2026-11-16):
--   * Always, pregame included.
--   * Not on map changes: every client reconnects then, and the players who were already on the
--     server land in the ready room as usual. Who was connected is saved every few seconds and
--     read back after the map loads, the same way the round counter survives map changes.
--   * Bots are left alone, and so is anyone the game already put in a spectator slot.
--   * The player moved gets one private line saying so, in their language (!lang).

local kStateFile = "SSM_SpectatorOnConnectState.json"
local kSnapshotSeconds = 5
-- A save older than this when the map loads is not a map change (the server was down or empty).
local kMapChangeMaxSeconds = 120
-- How long after the map loads players from the previous map still count as reconnecting.
local kReconnectWindowSeconds = 300
-- Delay before the chat line, so it arrives once the player is in the game.
local kNoticeDelaySeconds = 5

local function SteamIdOf(client)
    if client and not client:GetIsVirtual() then
        local steamId = client:GetUserId()
        if steamId and steamId > 0 then
            return steamId
        end
    end
end

-- [steamId] = true for players connected when the previous map ended, until they reconnect or
-- the window closes.
local Reconnecting = {}
local reconnectUntil = 0

do
    local state = LoadConfigFile(kStateFile)
    if type(state) == "table" and type(state.SavedAt) == "number" and type(state.Players) == "table"
    and Shared.GetSystemTime() - state.SavedAt <= kMapChangeMaxSeconds then
        for _, steamId in ipairs(state.Players) do
            if type(steamId) == "number" then
                Reconnecting[steamId] = true
            end
        end
        reconnectUntil = Shared.GetTime() + kReconnectWindowSeconds
    end
end

-- The snapshot keeps anyone seen in the last kSeenSeconds, not just who is connected right now:
-- if clients are already dropped in the last frames of a map, an empty snapshot then would lose
-- everyone.
local kSeenSeconds = 30
local LastSeen = {}   -- [steamId] = system time last seen connected
local lastSnapshotTime = -math.huge

local function SaveSnapshot(now)
    lastSnapshotTime = now
    local systemTime = Shared.GetSystemTime()

    Server.ForAllPlayers(function(player)
        local steamId = SteamIdOf(Server.GetOwner(player))
        if steamId then
            LastSeen[steamId] = systemTime
        end
    end)

    local players = {}
    for steamId, seenAt in pairs(LastSeen) do
        if systemTime - seenAt <= kSeenSeconds then
            players[#players + 1] = steamId
        else
            LastSeen[steamId] = nil
        end
    end

    SaveConfigFile(kStateFile, { SavedAt = systemTime, Players = players })
end

-- { steamId, at } waiting for their chat line.
local Notices = {}

local function SendNotices(now)
    for i = #Notices, 1, -1 do
        local notice = Notices[i]
        if now >= notice.at then
            table.remove(Notices, i)
            Server.ForAllPlayers(function(player)
                local client = Server.GetOwner(player)
                if SteamIdOf(client) == notice.steamId then
                    SSM.Notify(client, SSM.Text(SSM.LanguageOf(client), "spectator_joined"))
                end
            end)
        end
    end
end

-- Whether a newly connected client should be moved to the spectators.
local function ShouldMove(client, player)
    local steamId = SteamIdOf(client)
    if not steamId or client:GetIsSpectator() then
        return false
    end
    if not player or player:GetTeamNumber() ~= kTeamReadyRoom then
        return false
    end

    -- A player whose disconnected body is still held goes straight back into it (Saved Players).
    if SSM.SavedPlayers_IsHeld and SSM.SavedPlayers_IsHeld(steamId) then
        return false
    end

    if Reconnecting[steamId] then
        Reconnecting[steamId] = nil
        if Shared.GetTime() <= reconnectUntil then
            return false
        end
    end

    return true
end

local oldOnClientConnect
oldOnClientConnect = Class_ReplaceMethod("NS2Gamerules", "OnClientConnect", function(self, client, ...)
    local player = oldOnClientConnect(self, client, ...)

    local ok, err = pcall(function()
        if ShouldMove(client, player) then
            local joined, newPlayer = self:JoinTeam(player, kSpectatorIndex, true)
            if joined and newPlayer then
                player = newPlayer
            end
            Notices[#Notices + 1] = { steamId = SteamIdOf(client), at = Shared.GetTime() + kNoticeDelaySeconds }
        end
    end)
    if not ok then
        Shared.Message("[NS2 SUD] Spectator On Connect error: " .. tostring(err))
    end

    return player
end)

Event.Hook("UpdateServer", function()
    local now = Shared.GetTime()

    if now - lastSnapshotTime >= kSnapshotSeconds then
        SaveSnapshot(now)
    end

    if #Notices > 0 then
        SendNotices(now)
    end

    if reconnectUntil > 0 and now > reconnectUntil then
        Reconnecting = {}
        reconnectUntil = 0
    end
end)
