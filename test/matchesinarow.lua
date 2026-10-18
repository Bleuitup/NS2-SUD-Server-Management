-- Logic test for Matches In A Row, run outside the game against the real mod files:
--   lua test/matchesinarow.lua        (from the repo root)
--
-- Stubs only the few engine and vanilla globals the files touch. Proves the counting rules and
-- the scoreboard tagging; it says nothing about how the scoreboard looks in game.

local kServerFile = "source/lua/SSM/MatchesInARow/Server.lua"
local kClientFile = "source/lua/SSM/MatchesInARow/Client.lua"
local kScoreboardFile = "source/lua/SSM/MatchesInARow/GUIScoreboard.lua"

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
-- Server stubs

local Files = {}
local Now, SystemStart = 0, 1000000
local Players = {}
local Sent = {}
local Hooks = {}
local Gamerules

kTeamReadyRoom, kTeam1Index, kTeam2Index, kSpectatorIndex = 0, 1, 2, 3

function LoadConfigFile(name, default)
    if Files[name] then return deepcopy(Files[name]) end
    if default then Files[name] = deepcopy(default) return deepcopy(default) end
    return {}
end
function SaveConfigFile(name, data) Files[name] = deepcopy(data) end

Shared = {
    GetTime = function() return Now end,
    GetSystemTime = function() return SystemStart + math.floor(Now) end
}

Server = {
    GetOwner = function(player) return player.client end,
    ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end,
    SendNetworkMessage = function(a, b, c)
        if type(a) == "string" then
            Sent[#Sent + 1] = { to = "all", name = a, msg = b }
        else
            Sent[#Sent + 1] = { to = a, name = b, msg = c }
        end
    end
}

Event = { Hook = function(name, fn) Hooks[name] = fn end }

NS2Gamerules = { EndGame = function() Gamerules.started = false end }
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    _G[className][methodName] = method
    return original
end

Gamerules = {
    started = false, startTime = 0,
    GetGameStarted = function(self) return self.started end,
    GetGameStartTime = function(self) return self.started and self.startTime or 0 end,
    EndGame = function(self) return NS2Gamerules.EndGame(self) end
}
function GetGamerules() return Gamerules end

local function AddPlayer(steamId, team)
    local player = { team = team }
    player.client = {
        GetIsVirtual = function() return steamId == 0 end,
        GetUserId = function() return steamId end
    }
    player.GetTeamNumber = function(self) return self.team end
    Players[#Players + 1] = player
    return player
end

local function Run(seconds)
    local stop = Now + seconds
    while Now < stop do
        Now = Now + 0.5
        Hooks.UpdateServer()
    end
end

local function StartGame()
    Gamerules.started = true
    Gamerules.startTime = Now
end

local function LoadServer()
    Hooks = {}
    NS2Gamerules = { EndGame = function() Gamerules.started = false end }
    dofile(kServerFile)
end

-- Count as the server last broadcast it: { [steamId] = "rounds/minutes" }.
local function Broadcast()
    local result, clearSeen = {}, false
    for _, entry in ipairs(Sent) do
        if entry.to == "all" then
            if entry.name == "SSM_MatchesInARowClear" then
                result, clearSeen = {}, true
            elseif entry.name == "SSM_MatchesInARow" then
                result[entry.msg.steamId] = entry.msg.rounds .. "/" .. entry.msg.minutes
            end
        end
    end
    return result, clearSeen
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- ---------------------------------------------------------------------------------------------
-- Server scenarios

LoadServer()
check(Files["SSM_MatchesInARow.json"].GracePeriodSeconds == 120, "default settings file written")

local A = AddPlayer(101, kTeam1Index)
local B = AddPlayer(102, kTeam2Index)
local C = AddPlayer(103, kSpectatorIndex)
local D = AddPlayer(104, kSpectatorIndex)
local Bot = AddPlayer(0, kTeam1Index)

-- Round 1: A and B from the start, C subs in at 5 minutes, D spectates. 10 minutes.
Run(5)
StartGame()
Run(300)
C.team = kTeam2Index
Run(300)
Gamerules:EndGame()
Run(5)

local counts = Broadcast()
check(counts[101] == "1/10", "round 1: A 1 round 10 min, got " .. tostring(counts[101]))
check(counts[102] == "1/10", "round 1: B 1 round 10 min, got " .. tostring(counts[102]))
check(counts[103] == nil, "round 1: sub C gets 0")
check(counts[104] == nil, "round 1: spectator D gets 0")
check(counts[0] == nil, "round 1: bots never counted")

-- Round 2: A from start but hops to spectator at 3 min and back at 6; B spectates; C from start.
-- 20 minutes.
B.team = kSpectatorIndex
Sent = {}
StartGame()
Run(180)
A.team = kSpectatorIndex
Run(180)
A.team = kTeam1Index
Run(840)
Gamerules:EndGame()

counts = Broadcast()
check(counts[101] == "2/27", "round 2: A keeps the round despite hopping, 2 rounds 27 min, got " .. tostring(counts[101]))
check(counts[102] == nil, "round 2: B sat out, back to 0")
check(counts[103] == "1/20", "round 2: C 1 round 20 min, got " .. tostring(counts[103]))

-- Round 3: ends after 2 minutes, void.
Sent = {}
StartGame()
Run(120)
Gamerules:EndGame()
check(#Sent == 0, "round 3: a 2-minute round sends nothing")

-- Round 4: reset mid-round (Started ends without EndGame), nothing counts.
StartGame()
Run(600)
Gamerules.started = false
Run(5)
check(#Sent == 0, "round 4: a reset round sends nothing")

-- A late connect gets the whole list, starting with a clear.
Sent = {}
local newClient = AddPlayer(105, kSpectatorIndex).client
Hooks.ClientConnect(newClient)
check(Sent[1] and Sent[1].to == newClient and Sent[1].name == "SSM_MatchesInARowClear", "connect: clear first")
check(#Sent == 3, "connect: clear + 2 counts, got " .. #Sent)

-- Map change: the server Lua restarts and reads the saved counts back.
local saved = Files["SSM_MatchesInARowData.json"]
check(saved and #saved.Players == 2, "counts saved")
Sent = {}
LoadServer()
Hooks.ClientConnect(newClient)
check(#Sent == 3, "after map change the counts are still there")

-- Round 5 on the new map: A continues, C sits out.
C.team = kSpectatorIndex
Sent = {}
StartGame()
Run(600)
Gamerules:EndGame()
counts = Broadcast()
check(counts[101] == "3/37", "round 5: A 3 rounds 37 min across a map change, got " .. tostring(counts[101]))
check(counts[103] == nil, "round 5: C sat out")

-- Server left alone for 2 hours on the same map: the next round starts from scratch.
Now = Now + 7200
Sent = {}
StartGame()
Run(1)
local _, cleared = Broadcast()
check(cleared, "after 2 idle hours the old counts are cleared when the next round starts")
Run(599)
Gamerules:EndGame()
counts = Broadcast()
check(counts[101] == "1/10", "after 2 idle hours A starts again at 1, got " .. tostring(counts[101]))

-- Saved counts older than an hour are dropped on load.
Now = Now + 3700
Sent = {}
LoadServer()
Hooks.ClientConnect(newClient)
check(#Sent == 1, "stale save is dropped on load (only the clear is sent)")

-- ---------------------------------------------------------------------------------------------
-- Client: tagging

local ClientHooks = {}
Client = { HookNetworkMessage = function(name, fn) ClientHooks[name] = fn end }
local LocalName = "Bleu"
function ScoreboardUI_IsPlayerLocal(name) return name == LocalName end
local SteamIds = { [1] = 101, [2] = 102, [3] = nil }
function GetSteamIdForClientIndex(index) return SteamIds[index] end

dofile(kClientFile)

ClientHooks.SSM_MatchesInARowClear()
ClientHooks.SSM_MatchesInARow({ steamId = 101, rounds = 3, minutes = 95 })

local records = {
    { ClientIndex = 1, Name = "Bleu", Score = 10 },
    { ClientIndex = 2, Name = "Other", Score = 5 },
    { ClientIndex = 3, Name = "Loading", Score = 0 }
}
local tagged = SSM_MatchesInARow.TagScores(records)
check(tagged[1].Name == "[3r, 95m] Bleu", "tag format, got " .. tostring(tagged[1].Name))
check(tagged[1].Score == 10, "tagged copy keeps the other fields")
check(records[1].Name == "Bleu", "original record untouched")
check(tagged[2] == records[2], "untagged record passed through")
check(tagged[3] == records[3], "player without a Steam ID yet passed through")
check(ScoreboardUI_IsPlayerLocal("[3r, 95m] Bleu"), "local highlight still finds the tagged row")
check(not ScoreboardUI_IsPlayerLocal("[3r, 95m] Other"), "local highlight not fooled")

ClientHooks.SSM_MatchesInARowClear()
check(SSM_MatchesInARow.TagScores(records) == records, "after clear nobody is tagged")

-- Client: scoreboard hook

GUIScoreboard = {}
function GUIScoreboard:Initialize()
    self.teams = { { GetScores = function() return records end, GUIs = {} } }
end
function GUIScoreboard:UpdateTeam(team) self.lastScores = team.GetScores() end

dofile(kScoreboardFile)

ClientHooks.SSM_MatchesInARow({ steamId = 102, rounds = 1, minutes = 12 })
local board = setmetatable({}, { __index = GUIScoreboard })
board:Initialize()
local commText = "[1r, 12m] Other"
local commItem = { GetText = function() return commText end, SetText = function(_, t) commText = t end }
board.teams[1].GUIs.TeamInfo = { teamComm = commItem }
SSM_MatchesInARow.TagScores(records) -- registers the tagged name, as a scoreboard pass would
board:UpdateTeam(board.teams[1])
check(board.lastScores[2].Name == "[1r, 12m] Other", "scoreboard rows read tagged names")
check(commText == "Other", "commander header shows the real name")

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
