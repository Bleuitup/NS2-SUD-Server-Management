-- Logic test for Spectator On Connect, run outside the game against the real mod files:
--   lua test/spectatoronconnect.lua        (from the repo root)
--
-- Stubs only the few engine, vanilla and Shine globals the files touch. Proves who is moved,
-- the map-change exemption and the private line; it says nothing about a real server.

local kSharedFiles = { "source/lua/SSM/Messages.lua", "source/lua/SSM/Strings.lua", "source/lua/SSM/Commands.lua" }
local kServerFile = "source/lua/SSM/SpectatorOnConnect/Server.lua"
local kStateFile = "SSM_SpectatorOnConnectState.json"

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
local Players = {}
local Hooks = {}
local Notified = {}
local Joins = {}

kTeamReadyRoom, kTeam1Index, kTeam2Index, kSpectatorIndex = 0, 1, 2, 3

function LoadConfigFile(name, default)
    if Files[name] then return deepcopy(Files[name]) end
    return default and deepcopy(default) or nil
end
function SaveConfigFile(name, data) Files[name] = deepcopy(data) end

Shared = {
    GetTime = function() return Now end,
    GetSystemTime = function() return SystemStart + math.floor(Now) end,
    Message = function(text) print("server: " .. text) end
}
Server = {
    GetOwner = function(player) return player.client end,
    ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end
}
Event = { Hook = function(name, fn)
    local previous = Hooks[name]
    Hooks[name] = previous and function(...) previous(...) return fn(...) end or fn
end }
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    _G[className][methodName] = method
    return original
end
Shine = {
    NotifyDualColour = function(_, client, _, _, _, prefix, _, _, _, text)
        Notified[#Notified + 1] = { client = client, prefix = prefix, text = text }
    end
}

local function NewClient(steamId, options)
    options = options or {}
    return {
        steamId = steamId,
        spectator = options.spectator == true,
        GetIsVirtual = function() return options.bot == true end,
        GetUserId = function(self) return self.steamId end,
        GetIsSpectator = function(self) return self.spectator end
    }
end

local Gamerules = {}

local function LoadServer()
    Hooks = {}
    SSM = nil
    -- The game: a connecting client gets a player in the ready room, or in the spectators when
    -- the game gave them a spectator slot. JoinTeam replaces the player, like the real one.
    NS2Gamerules = {
        OnClientConnect = function(self, client)
            local player = { client = client, team = client.spectator and kSpectatorIndex or kTeamReadyRoom }
            player.GetTeamNumber = function(p) return p.team end
            Players[#Players + 1] = player
            return player
        end
    }
    Gamerules.JoinTeam = function(self, player, team, force)
        Joins[#Joins + 1] = { steamId = player.client.steamId, team = team, force = force }
        if Gamerules.failJoin then error("join failed") end
        local newPlayer = { client = player.client, team = team, GetTeamNumber = player.GetTeamNumber }
        for i, p in ipairs(Players) do if p == player then Players[i] = newPlayer end end
        player.client.spectator = team == kSpectatorIndex
        return true, newPlayer
    end
    for _, file in ipairs(kSharedFiles) do dofile(file) end
    dofile(kServerFile)
end

local function Connect(client)
    return NS2Gamerules.OnClientConnect(Gamerules, client)
end

local function Disconnect(steamId)
    for i, p in ipairs(Players) do
        if p.client.steamId == steamId then table.remove(Players, i) return end
    end
end

local function Run(seconds)
    local stop = Now + seconds
    while Now < stop do
        Now = Now + 0.5
        Hooks.UpdateServer()
    end
end

local function TeamOf(steamId)
    for _, p in ipairs(Players) do if p.client.steamId == steamId then return p.team end end
end

-- ---------------------------------------------------------------------------------------------
-- A fresh server

LoadServer()
Run(1)

local a = NewClient(101)
local returned = Connect(a)
check(returned.team == kSpectatorIndex, "a newcomer is moved to the spectators")
check(Joins[1].team == kSpectatorIndex and Joins[1].force == true, "through JoinTeam, forced")
check(a.spectator == true, "the client now holds a spectator slot")
check(#Notified == 0, "no line straight away")
Run(6)
check(#Notified == 1 and Notified[1].client == a and Notified[1].prefix == "[NS2 SUD]"
    and Notified[1].text == "You start as a spectator. Join a team when a player slot is free.",
    "one private line a few seconds later")
Run(10)
check(#Notified == 1, "the line is sent once")

Joins = {}
Connect(NewClient(0, { bot = true }))
check(#Joins == 0, "bots are left alone")
Connect(NewClient(102, { spectator = true }))
check(#Joins == 0, "clients already in a spectator slot are left alone")

-- In their language.
SSM.SetLanguage(NewClient(103), "es")
Notified = {}
local c = NewClient(103)
Connect(c)
Run(6)
check(Notified[1] and Notified[1].text:find("^Ingresaste como espectador") ~= nil, "the line is in the player's language")

-- Someone who leaves before the line goes out: nothing, no error.
Notified = {}
Connect(NewClient(104))
Disconnect(104)
Run(6)
check(#Notified == 0, "no line for someone who already left")

-- An error never breaks the connect.
Gamerules.failJoin = true
local e = NewClient(105)
local result = Connect(e)
check(result ~= nil and result.client == e, "connect survives an error in the feature")
Gamerules.failJoin = false
Disconnect(105)

-- ---------------------------------------------------------------------------------------------
-- Map change

-- The players join teams, then the map changes.
for _, p in ipairs(Players) do if p.client.steamId == 101 then p.team = kTeam1Index; p.client.spectator = false end end
Run(10)
local saved = {}
for _, id in ipairs(Files[kStateFile].Players) do saved[id] = true end
check(saved[101] and saved[102] and saved[103] and not saved[0], "who is connected is saved, bots not")

-- Clients drop in the last frames of the map; the snapshot still has them.
Players = {}
Run(6)
saved = {}
for _, id in ipairs(Files[kStateFile].Players) do saved[id] = true end
check(saved[101] and saved[103], "a snapshot right after everyone dropped still has them")

-- New map: the server Lua starts over and everyone reconnects.
Players = {}
Now = Now + 20
LoadServer()
Joins, Notified = {}, {}
local a2 = NewClient(101)
check(Connect(a2).team == kTeamReadyRoom, "a player from the last map lands in the ready room")
local n = NewClient(201)
check(Connect(n).team == kSpectatorIndex, "a newcomer during the map change is still moved")
Run(6)
check(#Notified == 1 and Notified[1].client == n, "only the newcomer gets the line")

-- The exemption is used once: the same player crashing and coming back later is moved.
Disconnect(101)
Joins = {}
Connect(NewClient(101))
check(#Joins == 1 and TeamOf(101) == kSpectatorIndex, "the exemption is used up by the first reconnect")

-- A player from the last map who only comes back after the window is moved too.
Run(300)
Connect(NewClient(103))
check(TeamOf(103) == kSpectatorIndex, "after the reconnect window everyone is moved")

-- A save from long ago is not a map change (server was down or empty).
Players = {}
Now = Now + 600
LoadServer()
Connect(NewClient(101))
check(TeamOf(101) == kSpectatorIndex, "an old save does not exempt anyone")

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
