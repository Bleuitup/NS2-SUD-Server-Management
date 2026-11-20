-- Logic test for Saved Players, run outside the game against the real mod files:
--   lua test/savedplayers.lua        (from the repo root)
--
-- Stubs a tiny server: clients, players that a client controls, teams, a 4-player cap, even
-- teams, a Lockteams-style lock, placeholder (virtual) clients. Proves who is kept, taking a body
-- over by joining, the slot rule, reconnecting straight back in (and Spectator On Connect leaving
-- them alone), sud_swap's access and results, stats following the person, and the round reset.
-- It says nothing about the real engine hand-over, which only a server shows.

local kSharedFiles = { "source/lua/SSM/Messages.lua", "source/lua/SSM/Strings.lua", "source/lua/SSM/Commands.lua" }
local kFiles = { "source/lua/SSM/SpectatorOnConnect/Server.lua", "source/lua/SSM/SavedPlayers/Server.lua" }

local failures, passes = 0, 0
local function check(condition, label)
    if condition then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL: " .. label)
    end
end

local function deepcopy(value)
    if type(value) ~= "table" then return value end
    local out = {}
    for k, v in pairs(value) do out[k] = deepcopy(v) end
    return out
end

-- ---------------------------------------------------------------------------------------------
-- Stubs

local Files = {}
local Now, SystemStart = 0, 1000000
local Hooks = {}
local Sent = {}       -- chat: { client or nil, text }
local Printed = {}    -- console replies: { client, text }
local Players = {}    -- every player entity
local Admins = {}     -- [steamId] = true
local Locked = false  -- Lockteams: unforced joins to a playing team are refused
local MaxPlayers = 4
local nextClientId = 1

kTeamReadyRoom, kTeam1Index, kTeam2Index, kSpectatorIndex = 0, 1, 2, 3
kGameState = { NotStarted = 1, Started = 5 }
Skulk = { kMapName = "skulk" }
function Vector() return {} end

function LoadConfigFile(name, default)
    if Files[name] then return deepcopy(Files[name]) end
    return default and deepcopy(default) or nil
end
function SaveConfigFile(name, data) Files[name] = deepcopy(data) end
function ServerAdminPrint(client, text) Printed[#Printed + 1] = { client = client, text = text } end
function BuildJoinErrorMessage() return {} end
function HasMixin(entity, name) return name == "Scoring" and entity.isPlayer == true end

-- Stats that follow the person: the real mixin copies a long list of fields, this one three.
ScoringMixin = { CopyPlayerDataFrom = function(self, other)
    self.score = other.score
    self.kills = other.kills
    self.skill = other.skill
end }

Shared = {
    GetTime = function() return Now end,
    GetSystemTime = function() return SystemStart + math.floor(Now) end,
    Message = function(text)
        if text:find("error") then print("server: " .. text) end
        if not text:find("^%[NS2 SUD%]") then Printed[#Printed + 1] = { client = nil, text = text } end
    end
}
Event = { Hook = function(name, fn)
    local previous = Hooks[name]
    Hooks[name] = previous and function(...) previous(...) return fn(...) end or fn
end }
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    assert(original ~= nil, methodName)
    _G[className][methodName] = method
    return original
end
function SSMPause_ReplaceMethod(className, methodName, method)
    local container = _G[className]
    if container == nil or container[methodName] == nil then return nil end
    local original = container[methodName]
    container[methodName] = method
    return original
end
SSMPause_TriggerDisconnectPause = function() return false end

local Gamerules   -- the gamerules instance; the class tables are the globals Gamerules and NS2Gamerules

local function RemovePlayer(player)
    for i, p in ipairs(Players) do
        if p == player then table.remove(Players, i) return end
    end
end

local function NewEntity(team, className)
    local player = { team = team, className = className or "Marine", isPlayer = true, name = "",
                     score = 0, kills = 0, skill = 0, pres = 0 }
    player.GetTeamNumber = function(p) return p.team end
    player.GetName = function(p) return p.name end
    player.SetName = function(p, name) p.name = name end
    player.GetClassName = function(p) return p.className end
    player.isa = function(p, name) return name == "Commander" and p.commander == true end
    player.SetControllerClient = function(p, client) p.client = client; client.player = p end
    player.GetIsSpectator = function(p) return p.client ~= nil and p.client.spectator end
    player.RemoveSpectators = function() end
    player.GetPlayerInfo = function(p) p.playerInfo = p.playerInfo or { owner = p } return p.playerInfo end
    player.SetPlayerInfo = function(p, info) p.playerInfo = info end
    player.AddTimedCallback = function(p, fn) fn(p) end
    Players[#Players + 1] = player
    return player
end

function CreateEntity(mapName, origin, team) return NewEntity(team, "Skulk") end
function DestroyEntity(player) RemovePlayer(player) end

local function NewClient(steamId, virtual)
    local client = { id = nextClientId, steamId = steamId, virtual = virtual == true, spectator = false }
    nextClientId = nextClientId + 1
    client.GetUserId = function(c) return c.steamId end
    client.GetIsVirtual = function(c) return c.virtual end
    client.GetId = function(c) return c.id end
    client.GetControllingPlayer = function(c) return c.player end
    client.GetIsSpectator = function(c) return c.spectator end
    client.SetIsSpectator = function(c, value) c.spectator = value end
    client.SetSpectatingPlayer = function() end
    return client
end

local function TeamCount(team)
    local count = 0
    for _, p in ipairs(Players) do if p.team == team then count = count + 1 end end
    return count
end

local function LoadServer()
    Hooks = {}
    SSM = nil
    Shine = {
        NotifyDualColour = function(_, client, _, _, _, _, _, _, _, text)
            Sent[#Sent + 1] = { client = client, text = text }
        end,
        HasAccess = function(_, client, command) return command == "sud_swap" and Admins[client.steamId] == true end
    }

    Server = {
        GetOwner = function(player) return player.client end,
        ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end,
        GetMaxPlayers = function() return MaxPlayers end,
        SendNetworkMessage = function() end,
        AddVirtualClient = function()
            local client = NewClient(0, true)
            Gamerules:OnClientConnect(client)
            return client
        end,
        DisconnectClient = function(client)
            Gamerules:OnClientDisconnect(client)
        end
    }

    _G.Gamerules = {
        -- The engine counts every client that is not a spectator, placeholders included.
        GetCanJoinPlayingTeam = function(self, player)
            if player:GetIsSpectator() then
                local playing = 0
                for _, p in ipairs(Players) do
                    if p.client and not p.client.spectator then playing = playing + 1 end
                end
                if playing >= MaxPlayers then return false end
            end
            return true
        end
    }
    NS2Gamerules = setmetatable({
        GetGameState = function(self) return self.state end,
        GetGameStarted = function(self) return self.state == kGameState.Started end,
        OnClientConnect = function(self, client)
            local player = NewEntity(kTeamReadyRoom, "ReadyRoomPlayer")
            player:SetControllerClient(client)
            player.name = client.name or ("Player" .. client.steamId)
            return player
        end,
        OnClientDisconnect = function(self, client)
            if client.player then RemovePlayer(client.player) end
        end,
        GetCanJoinTeamNumber = function(self, player, team)
            if team == kTeam1Index and TeamCount(1) > TeamCount(2) then return false end
            if team == kTeam2Index and TeamCount(2) > TeamCount(1) then return false end
            return true
        end,
        JoinTeam = function(self, player, team, force)
            if Locked and not force and (team == 1 or team == 2) then return false end
            if team ~= kSpectatorIndex and not self:GetCanJoinPlayingTeam(player) then return false end
            if not force and not self:GetCanJoinTeamNumber(player, team) then return false end
            local client = player.client
            local newPlayer = NewEntity(team, team == 3 and "Spectator" or (team == 0 and "ReadyRoomPlayer" or "Marine"))
            newPlayer.name, newPlayer.score, newPlayer.kills, newPlayer.skill = player.name, player.score, player.kills, player.skill
            RemovePlayer(player)
            newPlayer:SetControllerClient(client)
            client.spectator = team == kSpectatorIndex
            return true, newPlayer
        end,
        ResetGame = function(self) end
    }, { __index = _G.Gamerules })
    local instance = setmetatable({ state = kGameState.NotStarted }, { __index = NS2Gamerules })
    GetGamerules = function() return instance end
    for _, file in ipairs(kSharedFiles) do dofile(file) end
    for _, file in ipairs(kFiles) do dofile(file) end
    Gamerules = instance
end

local function Run(seconds)
    local stop = Now + seconds
    while Now < stop do
        Now = Now + 0.5
        Hooks.UpdateServer(0.5)
    end
end

-- A human connects (landing as a spectator, Spectator On Connect) and joins a team.
local function Connect(steamId, name)
    local client = NewClient(steamId)
    client.name = name
    Gamerules:OnClientConnect(client)
    return client
end

local function Join(client, team)
    return Gamerules:JoinTeam(client.player, team, false)
end

local function Disconnect(client)
    Gamerules:OnClientDisconnect(client)
end

local function Swap(caller, a, b)
    Printed = {}
    Hooks.Console_sud_swap(caller, a, b)
    return Printed[#Printed] and Printed[#Printed].text
end

local function Body(name)
    for _, p in ipairs(Players) do if p.name == name then return p end end
end

local function SaidToAll(text)
    for _, line in ipairs(Sent) do
        if line.client == nil and line.text == text then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------------------------
-- Setup: 2v2, round not started

LoadServer()
Run(1)
local ana, bleu, juan, pepe = Connect(1, "Ana"), Connect(2, "Bleu"), Connect(3, "Juan"), Connect(4, "Pepe")
check(ana.spectator, "newcomers start as spectators (Spectator On Connect)")
Join(ana, 1) Join(juan, 2) Join(bleu, 1) Join(pepe, 2)
Run(6)
check(TeamCount(1) == 2 and TeamCount(2) == 2, "2v2")

Disconnect(pepe)
check(not SSM.SavedPlayers_IsHeld(4) and TeamCount(2) == 1, "nothing is kept before the round starts")
pepe = Connect(4, "Pepe")
Join(pepe, 2)

-- ---------------------------------------------------------------------------------------------
-- A disconnect mid-round on a pub

Gamerules.state = kGameState.Started
bleu.player.className = "JetpackMarine"
bleu.player.pres, bleu.player.score, bleu.player.kills, bleu.player.skill = 50, 10, 3, 2000
local bleuBody = bleu.player
Disconnect(bleu)
check(SSM.SavedPlayers_IsHeld(2), "a team player who disconnects mid-round is kept")
check(bleuBody.name == "[D/C] Bleu" and bleuBody.client.virtual and bleuBody.team == 1,
    "the body stays on its team as [D/C] Bleu, held by a placeholder")
check(SaidToAll("Bleu disconnected. Join the Marines to take their place."), "everyone is told where to join")
check(TeamCount(1) == 2, "the body still counts on its team")

-- The slot: the server is full (4 = 3 humans + the body), a spectator may only take the body.
local leo = Connect(5, "Leo")
check(leo.spectator, "Leo starts as a spectator")
check(Join(leo, 2) == false and leo.spectator, "the held slot cannot be used to join the other team")

-- Lockteams on: no takeover by joining.
Locked = true
check(Join(leo, 1) == false and bleuBody.client.virtual, "locked teams: joining is refused, body still held")
Locked = false

-- Taking over by joining (even teams would refuse 3v2, the body is not "one more").
Sent = {}
leo.player.score, leo.player.kills, leo.player.skill = 1, 0, 1500
local ok, now = Join(leo, 1)
check(ok and now == bleuBody and leo.player == bleuBody, "joining the Marines takes over the body")
check(bleuBody.className == "JetpackMarine" and bleuBody.pres == 50, "the gear and resources stay with the body")
check(bleuBody.name == "Leo" and bleuBody.score == 1 and bleuBody.skill == 1500, "the name and stats are Leo's")
check(not leo.spectator, "Leo no longer holds a spectator slot")
check(not SSM.SavedPlayers_IsHeld(2), "the body is no longer held")
check(TeamCount(1) == 2 and #Players == 4, "no extra player left behind")
check(SaidToAll("Leo took Bleu's place."), "takeover line")

-- Bleu comes back: spectator as usual, then an admin swaps him back in.
bleu = Connect(2, "Bleu")
check(bleu.spectator and bleu.player.team == kSpectatorIndex, "the original lands in spectator once the body was taken")

check(Swap(ana, "Bleu", "Leo") == "Only admins, and commanders for their own team, can use sud_swap.", "no access for players")

Admins[1] = true
Sent = {}
check(Swap(ana, "leo", "bleu") == "Done.", "an admin swaps Bleu back in")
check(bleu.player == bleuBody and bleuBody.name == "Bleu", "Bleu plays his body again")
check(bleuBody.score == 10 and bleuBody.kills == 3 and bleuBody.skill == 2000, "Bleu's own stats are back")
check(leo.player.team == kSpectatorIndex and leo.spectator and leo.player.score == 1 and leo.player.skill == 1500,
    "Leo is a spectator again with his own stats")
check(not bleu.spectator, "Bleu's spectator slot is released")
check(SaidToAll("Leo and Bleu swapped places."), "swap line")

-- ---------------------------------------------------------------------------------------------
-- Reconnecting while the body is still held

Sent = {}
local juanBody = juan.player
juanBody.className, juanBody.score = "Fade", 7
Disconnect(juan)
check(SSM.SavedPlayers_IsHeld(3), "Juan is kept")
juan = Connect(3, "Juan")
check(juan.player == juanBody and juanBody.name == "Juan" and juanBody.className == "Fade" and juanBody.score == 7,
    "reconnecting goes straight back into the body, with his own stats")
check(not juan.spectator, "Spectator On Connect leaves him alone")
check(not SSM.SavedPlayers_IsHeld(3) and #Players == 5, "no longer held, nothing left behind")
check(SaidToAll("Juan reconnected and is back in the game."), "reconnect line")
Run(6)
local toJuan = 0
for _, line in ipairs(Sent) do if line.client == juan then toJuan = toJuan + 1 end end
check(toJuan == 0, "no 'you start as a spectator' line for him")

-- ---------------------------------------------------------------------------------------------
-- Commanders, and sud_swap on a held body

Admins[1] = nil
local pepeBody = pepe.player
Disconnect(pepe)
check(SSM.SavedPlayers_IsHeld(4), "Pepe is kept")

ana.player.commander = true
check(Swap(ana, "Pepe", "Leo") == "Commanders can only swap a player on their team with a spectator or someone in the ready room.",
    "a Marine commander cannot fill an Alien body")
check(Swap(ana, "Bleu", "Juan") == "Commanders can only swap a player on their team with a spectator or someone in the ready room.",
    "nor swap with the other team")
check(Swap(ana, "Bleu", "Leo") == "Done." and leo.player == bleuBody and bleu.player.team == kSpectatorIndex,
    "a commander swaps a teammate with a spectator")
Swap(ana, "Leo", "Bleu")
ana.player.commander = nil

check(Swap(nil, "Leo", "nobody") == "No player matches \"nobody\".", "unknown name")
check(Swap(nil, "e", "Leo"):find("^\"e\" matches more than one player"), "ambiguous name")
check(Swap(nil, "Leo", "Leo") == "Those are the same player.", "same player")
check(Swap(nil, "Leo") == "Usage: sud_swap <player> <player> (a name, part of one, or a Steam ID)", "usage")

Sent = {}
check(Swap(nil, "Leo", "Pepe") == "Done." and leo.player == pepeBody and pepeBody.name == "Leo",
    "the server console puts a spectator into a held body")
check(not SSM.SavedPlayers_IsHeld(4) and SaidToAll("Leo took Pepe's place."), "and says so")

-- ---------------------------------------------------------------------------------------------
-- Round reset

local anaBody = ana.player
Disconnect(ana)
check(SSM.SavedPlayers_IsHeld(1), "Ana is kept")
Gamerules:ResetGame()
check(not SSM.SavedPlayers_IsHeld(1) and Body("[D/C] Ana") == nil, "a round reset removes held bodies")

-- Switched off.
Files["SSM_SavedPlayers.json"] = { Enabled = false }
LoadServer()
Gamerules.state = kGameState.Started
Players = {}
local x = Connect(9, "X")
Join(x, 1)
Disconnect(x)
check(not SSM.SavedPlayers_IsHeld(9), "Enabled false: nobody is kept")

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
