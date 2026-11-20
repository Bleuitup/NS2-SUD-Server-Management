-- B2TP saved player states, server part. Thunderdome only.
--
-- Ported from Dragon's NSL Mod (lua/NSL/statesave/server.lua, https://github.com/xToken/NSL).
-- When a player on a team disconnects during a round, their player is not removed: it is handed to
-- a placeholder connection that sends no input and renamed "[D/C] Name". It stays where it was, on
-- its team, and can be killed. When the same Steam account reconnects during that round, they are
-- put back into it with whatever they had: lifeform, upgrades, weapons, jetpack or Exo, health,
-- energy, position, the command chair. Commanders are saved too, as in NSL. Saved players left at
-- round reset are removed.
--
-- Left out of the port: NSL's referee commands (list saved players, put a substitute into a saved
-- player) and its bot-controller and virtual-move hooks, which build 345 no longer needs (a
-- placeholder has no bot attached, so vanilla gives it an empty move and never kicks it).
-- B2TP addition: the restored player takes over the reconnecting client's scoreboard entry.

if not B2TP_GetPauseInstalled or not B2TP_GetPauseInstalled() then
    return
end

if not B2TPTD_Setting("SavePlayerStates") then
    B2TPTD_Log("saved player states are switched off in B2TP_Thunderdome.json")
    return
end

local kDisconnectTag = "[D/C]"

local virtualClients = { }     -- Steam id -> placeholder client holding that player's saved player
local dontCreatePlayerOnConnect = false

local function Log(text)
    B2TPTD_Log("player states: " .. text)
end

local function StoreDisconnectedTeamPlayer(gamerules, client)

    local player = client:GetControllingPlayer()

    -- A player that was already saved (and restored less than 0.1 s ago) is not saved again.
    if not player or player.isCached or not gamerules:GetGameStarted() then
        return
    end

    local teamNumber = player:GetTeamNumber()
    if teamNumber ~= kTeam1Index and teamNumber ~= kTeam2Index then
        return
    end

    local id = client:GetUserId()
    local name = player:GetName()

    -- Stand-in for the disconnecting client, so the rest of the disconnect code removes this
    -- instead of the real player.
    local tempplayer = CreateEntity(Skulk.kMapName, Vector(0, 0, 0), teamNumber)

    dontCreatePlayerOnConnect = true
    local newclient = Server.AddVirtualClient()
    dontCreatePlayerOnConnect = false

    if not newclient then
        Log("could not create a placeholder for " .. name)
        if tempplayer then
            DestroyEntity(tempplayer)
        end
        return
    end

    player:RemoveSpectators(nil)
    player:SetControllerClient(newclient)
    tempplayer:SetControllerClient(client)

    -- Its scoreboard entry belongs to the disconnecting client and is destroyed with it.
    player.playerInfo = nil

    player.isCached = true
    player:SetName(kDisconnectTag .. name)
    virtualClients[id] = newclient

    Log(string.format("saved %s (%s, %s)", name, player:GetClassName(), teamNumber == kTeam1Index and "Marines" or "Aliens"))

    if B2TPTD_Setting("PauseOnDisconnect") and B2TPPause_TriggerDisconnectPause then
        B2TPPause_TriggerDisconnectPause(name, teamNumber)
    end

end

local function CleanupVirtualClient(client)
    for id, v in pairs(virtualClients) do
        if v == client then
            virtualClients[id] = nil
        end
    end
end

local oldOnClientDisconnect = NS2Gamerules.OnClientDisconnect
function NS2Gamerules:OnClientDisconnect(client)
    if client and not client:GetIsVirtual() then
        StoreDisconnectedTeamPlayer(self, client)
    elseif client and client:GetIsVirtual() then
        CleanupVirtualClient(client)
    end
    oldOnClientDisconnect(self, client)
end

local function RemoveCachedFlag(self)
    self.isCached = false
    return false
end

local function MoveClientToStoredPlayer(client, id)

    local player = client:GetControllingPlayer()
    local gamerules = GetGamerules()
    local virtualClient = virtualClients[id]
    local success = false

    if virtualClient and player and gamerules then

        local name = player:GetName()
        local oldplayer = virtualClient:GetControllingPlayer()

        if oldplayer then

            -- Join the team for real first, so the team and the client agree.
            success, player = gamerules:JoinTeam(player, oldplayer:GetTeamNumber(), true)

            if success and player then

                local playerInfo = player:GetPlayerInfo()
                player.playerInfo = nil

                oldplayer:SetControllerClient(client)
                player:SetControllerClient(virtualClient)
                player.isCached = true

                Server.DisconnectClient(virtualClient)

                oldplayer:SetPlayerInfo(playerInfo)
                oldplayer:SetName(name)
                oldplayer.sendTechTreeBase = true
                oldplayer:AddTimedCallback(RemoveCachedFlag, 0.1)

                B2TPTD_SayAll(string.format("%s reconnected and is back in the game.", name))
                Log(string.format("restored %s (%s)", name, oldplayer:GetClassName()))

            end

        end

    end

    virtualClients[id] = nil
    return success

end

-- Placeholders get no player of their own; a reconnecting player is put back into their saved one.
local oldOnClientConnect = NS2Gamerules.OnClientConnect
function NS2Gamerules:OnClientConnect(client)

    if client:GetIsVirtual() then
        if dontCreatePlayerOnConnect then
            return
        end
        for _, v in pairs(virtualClients) do
            if v == client then
                return
            end
        end
    end

    local player = oldOnClientConnect(self, client)

    if client and not client:GetIsVirtual() and virtualClients[client:GetUserId()] then
        MoveClientToStoredPlayer(client, client:GetUserId())
    end

    return player

end

-- Round reset: remove any saved players still waiting.
local oldResetGame = NS2Gamerules.ResetGame
function NS2Gamerules:ResetGame(...)

    local result = oldResetGame(self, ...)

    local toDisconnect = { }
    for _, v in pairs(virtualClients) do
        table.insert(toDisconnect, v)
    end
    virtualClients = { }
    for i = 1, #toDisconnect do
        Server.DisconnectClient(toDisconnect[i])
    end
    if #toDisconnect > 0 then
        Log(string.format("round reset, removed %d saved players", #toDisconnect))
    end

    return result

end

-- A saved player's body is not removed by its ragdoll or by the destruction checks.
local oldRagdollMixinOnTag = RagdollMixin.OnTag
if oldRagdollMixinOnTag then
    function RagdollMixin:OnTag(tagName)
        if not (self.isCached and tagName == "destroy") then
            oldRagdollMixinOnTag(self, tagName)
        end
    end
end

local oldGetDestructionAllowed
oldGetDestructionAllowed = B2TPPause_ReplaceMethod("Player", "GetDestructionAllowed",
    function(self, destructionAllowedTable)
        oldGetDestructionAllowed(self, destructionAllowedTable)
        destructionAllowedTable.allowed = destructionAllowedTable.allowed and not self.isCached
    end
)

Log("on")
