-- NS2 SUD saved players, server part. On every server.
--
-- Ported from Dragon's NSL Mod (lua/NSL/statesave/server.lua, https://github.com/xToken/NSL), first
-- for Blast to the Past, then moved here (author, 2026-11-20).
--
-- When a player on a team disconnects during a round, their player is not removed: it is handed to
-- a placeholder connection that sends no input and renamed "[D/C] Name". It stays where it was, on
-- its team, with its lifeform, upgrades, weapons, jetpack or Exo, health, energy, personal
-- resources, and the command chair. It can be killed. Where the pause is allowed (Pause/Server.lua)
-- the game pauses too.
--
-- Rules (the author's picks, 2026-11-20):
--   * The original reconnecting while the body is still held goes straight back into it, and
--     Spectator On Connect leaves them alone.
--   * Anyone who joins a team that holds a body takes it over, on every server. The original then
--     starts as a spectator as usual when they come back.
--   * sud_swap <player> <player> (console) puts a player into a held body (NSL's
--     sv_nslreplaceplayer), or swaps two connected players' places. One of the two is always a
--     spectator or in the ready room (author, 2026-11-20): never two players on teams. Shine
--     admins with sud_swap access and the server console can use it on any team. Commanders only
--     for their own team: a player on it (or a held body on it) with a spectator or someone in
--     the ready room.
--   * The body, with its gear and resources, stays where it is; the person moves. Scoreboard
--     stats and Hive skill follow the person (ScoringMixin's data), so team skill, Commander Match
--     and the end-of-round Hive report stay right.
--   * A held body keeps its player slot: only a takeover of that body may use it, so the player
--     cap holds. Lockteams still blocks joins that are not forced; sud_swap forces.
--   * Saved players left at round reset are removed.
--
-- Left out of the port: NSL's referee list command and its bot-controller and virtual-move hooks,
-- which build 345 no longer needs (a placeholder has no bot attached, so vanilla gives it an empty
-- move and never kicks it). B2TP addition kept: the restored player takes over the reconnecting
-- client's scoreboard entry.

local kSettingsFile = "SSM_SavedPlayers.json"
local kDefaultSettings = { Enabled = true }   -- false: disconnecting players are not kept

local settings = LoadConfigFile(kSettingsFile, kDefaultSettings, true)
if type(settings) ~= "table" or type(settings.Enabled) ~= "boolean" then
    settings = { Enabled = true }
end

local unpack = table.unpack or unpack

local kDisconnectTag = "[D/C] "
local kTeamNames = { [kTeam1Index] = "Marines", [kTeam2Index] = "Aliens" }

-- [steamId of the disconnected player] = { client = placeholder, name = their name, team, at }
local Held = {}
-- [steamId] = that person's ScoringMixin data while someone else plays their body.
local Stash = {}

local dontCreatePlayerOnConnect = false
local internalMove = false       -- our own JoinTeam calls: no takeover, no slot checks
local joiningHeldTeam = nil      -- team number a player is joining to take over a body

local function Log(text)
    Shared.Message("[NS2 SUD] saved players: " .. text)
end

local function SayAll(text)
    SSM.NotifyAll(text, false, true)
end

local function Reply(client, key, ...)
    SSM.Print(client, SSM.Text(SSM.LanguageOf(client), key, ...))
end

function SSM.SavedPlayers_IsHeld(steamId)
    return steamId ~= nil and Held[steamId] ~= nil
end

local function HeldCount()
    local count = 0
    for _ in pairs(Held) do
        count = count + 1
    end
    return count
end

-- The body held longest on a team, as the steamId it is held under.
local function OldestHeldOnTeam(teamNumber)
    local found, foundAt
    for steamId, held in pairs(Held) do
        if held.team == teamNumber and (not foundAt or held.at < foundAt) then
            found, foundAt = steamId, held.at
        end
    end
    return found
end

local function GetHumanClient(player)
    local client = player and Server.GetOwner(player)
    if client and not client:GetIsVirtual() then
        return client
    end
end

-- The person's data (score, kills, Hive skill...): ScoringMixin's own copy function only assigns
-- fields, so it copies into and out of a plain table too, whatever this build's field list is.
local function Snapshot(entity)
    if not (entity and ScoringMixin and ScoringMixin.CopyPlayerDataFrom and HasMixin(entity, "Scoring")) then
        return nil
    end
    local data = {}
    ScoringMixin.CopyPlayerDataFrom(data, entity)
    return data
end

local function Apply(entity, data)
    if data and entity and HasMixin(entity, "Scoring") then
        ScoringMixin.CopyPlayerDataFrom(entity, data)
    end
end

-- A person's data: what is kept for them while someone else plays their body, else their player's.
local function PersonData(client, player)
    local steamId = client:GetUserId()
    local data = Stash[steamId]
    Stash[steamId] = nil
    return data or Snapshot(player)
end

local function RemoveCachedFlag(self)
    self.isCached = false
    return false
end

-- Disconnect: keep the body ---------------------------------------------------------------------

local function StoreDisconnectedTeamPlayer(gamerules, client)

    local player = client:GetControllingPlayer()

    -- A player that was already saved (and restored less than 0.1 s ago) is not saved again.
    if not settings.Enabled or not player or player.isCached or not gamerules:GetGameStarted() then
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

    -- The game logs the disconnecting client's round (Hive report) from the stand-in, so it gets
    -- their stats.
    Apply(tempplayer, Snapshot(player))

    player:RemoveSpectators(nil)
    player:SetControllerClient(newclient)
    tempplayer:SetControllerClient(client)

    -- Its scoreboard entry belongs to the disconnecting client and is destroyed with it.
    player.playerInfo = nil

    player.isCached = true
    player:SetName(kDisconnectTag .. name)
    Held[id] = { client = newclient, name = name, team = teamNumber, at = Shared.GetTime(true) }

    Log(string.format("kept %s (%s, %s)", name, player:GetClassName(), kTeamNames[teamNumber]))

    local paused = SSMPause_TriggerDisconnectPause and SSMPause_TriggerDisconnectPause(name, teamNumber)
    if not paused then
        SayAll(string.format("%s disconnected. Join the %s to take their place.", name, kTeamNames[teamNumber]))
    end

end

local function CleanupVirtualClient(client)
    for id, held in pairs(Held) do
        if held.client == client then
            Held[id] = nil
        end
    end
end

local oldOnClientDisconnect
oldOnClientDisconnect = Class_ReplaceMethod("NS2Gamerules", "OnClientDisconnect", function(self, client, ...)
    if client then
        local ok, err = pcall(function()
            if client:GetIsVirtual() then
                CleanupVirtualClient(client)
            else
                StoreDisconnectedTeamPlayer(self, client)
            end
        end)
        if not ok then
            Log("error at disconnect: " .. tostring(err))
        end
    end
    return oldOnClientDisconnect(self, client, ...)
end)

-- Into a held body -----------------------------------------------------------------------------

-- Puts a connected player into the body held under ownerId. joined: the player already joined
-- that team (a takeover on join); otherwise they are moved there first, forced, so the team and
-- the client agree. Returns true on success.
local function PutIntoBody(client, ownerId, joined)

    local held = Held[ownerId]
    local gamerules = GetGamerules()
    local body = held and held.client:GetControllingPlayer()
    local player = joined or client:GetControllingPlayer()
    if not (held and gamerules and body and player) then
        return false
    end

    local isOwner = client:GetUserId() == ownerId
    local name = player:GetName()

    if not joined then
        internalMove = true
        local ok, success, newPlayer = pcall(gamerules.JoinTeam, gamerules, player, body:GetTeamNumber(), true)
        internalMove = false
        if not ok then
            Log("error moving " .. name .. ": " .. tostring(success))
            return false
        end
        if not (success and newPlayer) then
            return false
        end
        player = newPlayer
    end

    -- The person's data before their throwaway player goes.
    local person = not isOwner and PersonData(client, player) or nil

    local playerInfo = player:GetPlayerInfo()
    player.playerInfo = nil

    body:SetControllerClient(client)
    player:SetControllerClient(held.client)
    player.isCached = true

    Held[ownerId] = nil
    Server.DisconnectClient(held.client)

    body:SetPlayerInfo(playerInfo)
    -- Set directly: Player:SetName makes names unique, and the throwaway player may still carry
    -- this name, which would turn it into "Name (2)" (GitHub issue #1). It is already a valid name.
    body.name = name
    body.sendTechTreeBase = true
    body:AddTimedCallback(RemoveCachedFlag, 0.1)

    if isOwner then
        Stash[ownerId] = nil
    else
        Stash[ownerId] = Snapshot(body)
        Apply(body, person)
    end

    Log(string.format("%s is now playing %s (%s)", name, isOwner and "their own body" or (held.name .. "'s body"), body:GetClassName()))
    return true

end

-- The original reconnecting: straight back in. Placeholders get no player of their own.
local oldOnClientConnect
oldOnClientConnect = Class_ReplaceMethod("NS2Gamerules", "OnClientConnect", function(self, client, ...)

    if client:GetIsVirtual() then
        if dontCreatePlayerOnConnect then
            return
        end
        for _, held in pairs(Held) do
            if held.client == client then
                return
            end
        end
    end

    local player = oldOnClientConnect(self, client, ...)

    if not client:GetIsVirtual() and Held[client:GetUserId()] then
        local ok, result = pcall(PutIntoBody, client, client:GetUserId())
        if ok and result then
            SayAll(string.format("%s reconnected and is back in the game.", player and player:GetName() or "A player"))
            return client:GetControllingPlayer()
        elseif not ok then
            Log("error restoring a player: " .. tostring(result))
        end
    end

    return player

end)

-- Joining a team that holds a body takes it over.
local oldJoinTeam
oldJoinTeam = Class_ReplaceMethod("NS2Gamerules", "JoinTeam", function(self, player, newTeamNumber, force, ...)

    local client = not internalMove and GetHumanClient(player)
    local ownerId = client and player:GetTeamNumber() ~= newTeamNumber and OldestHeldOnTeam(newTeamNumber)
    if not ownerId then
        return oldJoinTeam(self, player, newTeamNumber, force, ...)
    end

    joiningHeldTeam = newTeamNumber
    local results = { pcall(oldJoinTeam, self, player, newTeamNumber, force, ...) }
    joiningHeldTeam = nil
    if not results[1] then
        error(results[2], 0)
    end

    local success, newPlayer = results[2], results[3]
    if success and newPlayer and Held[ownerId] then
        local heldName = Held[ownerId].name
        local ok, moved = pcall(PutIntoBody, client, ownerId, newPlayer)
        if ok and moved then
            local now = client:GetControllingPlayer()
            SayAll(string.format("%s took %s's place.", now:GetName(), heldName))
            return success, now
        elseif not ok then
            Log("error in a takeover: " .. tostring(moved))
        end
    end

    return unpack(results, 2)

end)

-- Slots: a held body keeps its slot, and only a takeover of that body may use it.
local oldGetCanJoinPlayingTeam
oldGetCanJoinPlayingTeam = SSMPause_ReplaceMethod("Gamerules", "GetCanJoinPlayingTeam", function(self, player, ...)
    if internalMove or joiningHeldTeam then
        return true
    end

    local heldCount = HeldCount()
    if heldCount > 0 and player:GetIsSpectator() then
        local playing = heldCount
        Server.ForAllPlayers(function(other)
            local client = GetHumanClient(other)
            if client and not client:GetIsSpectator() then
                playing = playing + 1
            end
        end)
        if playing >= Server.GetMaxPlayers() then
            Server.SendNetworkMessage(player, "JoinError", BuildJoinErrorMessage(3), true)
            return false
        end
    end

    return oldGetCanJoinPlayingTeam(self, player, ...)
end)

-- Even teams: the held body already counts on its team, so taking it over is not "one more".
local oldGetCanJoinTeamNumber
oldGetCanJoinTeamNumber = SSMPause_ReplaceMethod("NS2Gamerules", "GetCanJoinTeamNumber", function(self, player, teamNumber, ...)
    if joiningHeldTeam and joiningHeldTeam == teamNumber then
        return true
    end
    return oldGetCanJoinTeamNumber(self, player, teamNumber, ...)
end)

-- Swapping two connected players ----------------------------------------------------------------

local function SwapPeople(client1, client2)
    local player1, player2 = client1:GetControllingPlayer(), client2:GetControllingPlayer()
    if not (player1 and player2) then
        return false
    end

    local data1, data2 = PersonData(client1, player1), PersonData(client2, player2)
    local name1, name2 = player1:GetName(), player2:GetName()

    client1:SetSpectatingPlayer(nil)
    client2:SetSpectatingPlayer(nil)

    player1:SetControllerClient(client2)
    player2:SetControllerClient(client1)

    client1:SetIsSpectator(player2:GetTeamNumber() == kSpectatorIndex)
    client2:SetIsSpectator(player1:GetTeamNumber() == kSpectatorIndex)

    -- The two names are only exchanged, so set them directly: Player:SetName makes names unique,
    -- and the first rename would clash with the other player still holding it (GitHub issue #1).
    player1.name, player2.name = name2, name1
    Apply(player2, data1)
    Apply(player1, data2)
    player1.sendTechTreeBase = true
    player2.sendTechTreeBase = true

    Log(string.format("%s and %s swapped places", name1, name2))
    return true
end

-- sud_swap --------------------------------------------------------------------------------------

-- A target: a held body (by its player's name or Steam ID) or a connected person.
local function FindTargets(text)
    local wanted = string.lower(text)
    local id = tonumber(text)
    local exact, partial = {}, {}

    local function Consider(target, name)
        local lower = string.lower(name)
        if lower == wanted or lower == string.lower(kDisconnectTag) .. wanted then
            exact[#exact + 1] = target
        elseif string.find(lower, wanted, 1, true) then
            partial[#partial + 1] = target
        end
    end

    for steamId, held in pairs(Held) do
        local target = { held = steamId, name = kDisconnectTag .. held.name, team = held.team }
        if id and id == steamId then
            return { target }
        end
        Consider(target, held.name)
    end

    local byId
    Server.ForAllPlayers(function(player)
        local client = GetHumanClient(player)
        if client then
            local target = { client = client, name = player:GetName(), team = player:GetTeamNumber() }
            if id and id == client:GetUserId() then
                byId = target
            end
            Consider(target, player:GetName())
        end
    end)

    if byId then
        return { byId }
    end
    return #exact > 0 and exact or partial
end

local function FindTarget(caller, text)
    local found = FindTargets(text)
    if #found == 1 then
        return found[1]
    end
    if #found == 0 then
        Reply(caller, "swap_not_found", text)
    else
        local names = {}
        for i, target in ipairs(found) do
            names[i] = target.name
        end
        Reply(caller, "swap_ambiguous", text, table.concat(names, ", "))
    end
end

local function IsBench(team)
    return team == kTeamReadyRoom or team == kSpectatorIndex
end

-- "admin" for the server console and Shine admins with sud_swap access, else the commander's team.
local function GetSwapAccess(caller)
    if not caller then
        return "admin"
    end
    if Shine and Shine.HasAccess and Shine:HasAccess(caller, "sud_swap") then
        return "admin"
    end
    local player = caller:GetControllingPlayer()
    if player and player:isa("Commander") then
        return "commander", player:GetTeamNumber()
    end
end

local function OnSwap(caller, first, second)

    if not first or not second then
        Reply(caller, "swap_usage")
        return
    end

    local access, commanderTeam = GetSwapAccess(caller)
    if not access then
        Reply(caller, "swap_no_access")
        return
    end

    local a = FindTarget(caller, first)
    local b = a and FindTarget(caller, second)
    if not (a and b) then
        return
    end

    if (a.held and a.held == b.held) or (a.client and a.client == b.client) then
        Reply(caller, "swap_same")
        return
    end
    -- For everyone (author, 2026-11-20): never two players who are both on a team; one of them is
    -- a spectator or in the ready room. Held bodies are always on a team, so two of them never pass.
    if not (IsBench(a.team) or IsBench(b.team)) then
        Reply(caller, "swap_needs_bench")
        return
    end

    if access == "commander" then
        local allowed = (a.team == commanderTeam and IsBench(b.team)) or (b.team == commanderTeam and IsBench(a.team))
        if not allowed then
            Reply(caller, "swap_commander_rule")
            return
        end
    end

    local ok, result
    if a.held or b.held then
        local body, person = a.held and a or b, a.held and b or a
        local heldName = Held[body.held].name
        ok, result = pcall(PutIntoBody, person.client, body.held)
        if ok and result then
            local name = person.client:GetControllingPlayer():GetName()
            if person.client:GetUserId() == body.held then
                SayAll(string.format("%s is back in the game.", name))
            else
                SayAll(string.format("%s took %s's place.", name, heldName))
            end
        end
    else
        ok, result = pcall(SwapPeople, a.client, b.client)
        if ok and result then
            SayAll(string.format("%s and %s swapped places.", a.name, b.name))
        end
    end

    if not ok then
        Log("sud_swap error: " .. tostring(result))
    end
    Reply(caller, ok and result and "swap_done" or "swap_failed")

end

Event.Hook("Console_sud_swap", OnSwap)
SSM.ListCommand("sud_swap", "cmd_sud_swap", true)

-- Round reset: remove any saved players still waiting ---------------------------------------------

local oldResetGame
oldResetGame = Class_ReplaceMethod("NS2Gamerules", "ResetGame", function(self, ...)

    local result = { oldResetGame(self, ...) }

    local toDisconnect = {}
    for _, held in pairs(Held) do
        toDisconnect[#toDisconnect + 1] = held.client
    end
    Held = {}
    Stash = {}
    for i = 1, #toDisconnect do
        Server.DisconnectClient(toDisconnect[i])
    end
    if #toDisconnect > 0 then
        Log(string.format("round reset, removed %d saved players", #toDisconnect))
    end

    return unpack(result)

end)

-- A saved player's body is not removed by its ragdoll or by the destruction checks.
local oldRagdollMixinOnTag = RagdollMixin and RagdollMixin.OnTag
if oldRagdollMixinOnTag then
    function RagdollMixin:OnTag(tagName)
        if not (self.isCached and tagName == "destroy") then
            oldRagdollMixinOnTag(self, tagName)
        end
    end
end

local oldGetDestructionAllowed
oldGetDestructionAllowed = SSMPause_ReplaceMethod("Player", "GetDestructionAllowed",
    function(self, destructionAllowedTable)
        oldGetDestructionAllowed(self, destructionAllowedTable)
        destructionAllowedTable.allowed = destructionAllowedTable.allowed and not self.isCached
    end
)

Log(settings.Enabled and "on" or ("disconnecting players are not kept (" .. kSettingsFile .. ")"))
