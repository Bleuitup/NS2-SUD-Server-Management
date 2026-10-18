-- Logic test for Matches In A Row, run outside the game against the real mod file:
--   lua test/matchesinarow.lua        (from the repo root)
--
-- Stubs only the few engine, vanilla and Shine globals the file touches. Proves the counting
-- rules and the commands; it says nothing about how they behave on a real server.

local kServerFile = "source/lua/SSM/MatchesInARow/Server.lua"
local kDataFile = "SSM_MatchesInARowData.json"

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
    GetSystemTime = function() return SystemStart + math.floor(Now) end,
    Message = function() end
}

Server = {
    GetOwner = function(player) return player.client end,
    ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end
}

Event = { Hook = function(name, fn) Hooks[name] = fn end }

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
    player.GetName = function() return "P" .. steamId end
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

-- A fresh server Lua, as after a map change or restart.
local function LoadServer()
    Hooks = {}
    NS2Gamerules = { EndGame = function() Gamerules.started = false end }
    dofile(kServerFile)
end

-- Counts as last saved: { [steamId] = "rounds/minutes" }.
local function Saved()
    local result = {}
    local data = Files[kDataFile]
    for _, entry in ipairs(data and data.Players or {}) do
        result[entry.id] = entry.rounds .. "/" .. math.floor(entry.seconds / 60 + 0.5)
    end
    return result
end

local function Count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

local Lines = function() return SSM_MatchesInARow_GetStreaksLines() end

-- ---------------------------------------------------------------------------------------------
-- Counting

LoadServer()
check(Files["SSM_MatchesInARow.json"].GracePeriodSeconds == 120, "default settings file written")
check(Lines()[1] == "Nobody has played a round in a row yet.", "empty list message")

local A = AddPlayer(101, kTeam1Index)
local B = AddPlayer(102, kTeam2Index)
local C = AddPlayer(103, kSpectatorIndex)
local D = AddPlayer(104, kSpectatorIndex)
AddPlayer(0, kTeam1Index) -- a bot

-- Round 1: A and B from the start, C subs in at 5 minutes, D spectates. 10 minutes.
Run(5)
StartGame()
Run(300)
C.team = kTeam2Index
Run(300)
Gamerules:EndGame()
Run(5)

local counts = Saved()
check(counts[101] == "1/10", "round 1: A 1 round 10 min, got " .. tostring(counts[101]))
check(counts[102] == "1/10", "round 1: B 1 round 10 min, got " .. tostring(counts[102]))
check(counts[103] == nil, "round 1: sub C gets 0")
check(counts[104] == nil, "round 1: spectator D gets 0")
check(counts[0] == nil, "round 1: bots never counted")

-- Round 2: A from start but hops to spectator at 3 min and back at 6; B spectates; C from start.
-- 20 minutes.
B.team = kSpectatorIndex
StartGame()
Run(180)
A.team = kSpectatorIndex
Run(180)
A.team = kTeam1Index
Run(840)
Gamerules:EndGame()

counts = Saved()
check(counts[101] == "2/27", "round 2: A keeps the round despite hopping, 2 rounds 27 min, got " .. tostring(counts[101]))
check(counts[102] == nil, "round 2: B sat out, back to 0")
check(counts[103] == "1/20", "round 2: C 1 round 20 min, got " .. tostring(counts[103]))

-- Round 3: ends after 50 seconds. No round counts change and nobody is reset, but A's 50 seconds
-- go on A's minutes (1619 s + 49.5 s = 27.8 min, shown as 28). C sits it out and keeps 1 round;
-- D plays it with no run and gets no entry.
C.team, D.team = kSpectatorIndex, kTeam1Index
StartGame()
Run(50)
Gamerules:EndGame()
counts = Saved()
check(counts[101] == "2/28", "round 3: short round adds A's time but not a round, got " .. tostring(counts[101]))
check(counts[103] == "1/20", "round 3: sitting out a short round does not reset C, got " .. tostring(counts[103]))
check(counts[104] == nil and Count(counts) == 2, "round 3: a short round starts no new run")
D.team = kSpectatorIndex

-- Round 4: reset mid-round (Started ends without EndGame), nothing counts.
StartGame()
Run(600)
Gamerules.started = false
Run(5)
counts = Saved()
check(counts[101] == "2/28" and counts[103] == "1/20" and Count(counts) == 2, "round 4: a reset round changes nothing")

-- Map change: the server Lua restarts and reads the saved counts back.
LoadServer()
check(Lines()[1] == "Most rounds in a row: P101 2r, P103 1r", "after map change the counts are still there, got " .. Lines()[1])

-- Round 5 on the new map: A continues, C sits out.
C.team = kSpectatorIndex
StartGame()
Run(600)
Gamerules:EndGame()
counts = Saved()
check(counts[101] == "3/38", "round 5: A 3 rounds 38 min across a map change, got " .. tostring(counts[101]))
check(counts[103] == nil, "round 5: C sat out")

-- A 70-minute round with a restart 65 minutes in: that round is lost, the counts are kept.
StartGame()
Run(65 * 60)
check(Files[kDataFile].SavedAt >= SystemStart + math.floor(Now) - 300, "activity was saved during the long round")
LoadServer()
check(Lines()[1] == "Most rounds in a row: P101 3r", "restart 65 minutes into a round keeps the counts, got " .. Lines()[1])

-- Server left alone for 2 hours on the same map: the next round starts from scratch.
Now = Now + 7200
StartGame()
Run(1)
check(Count(Saved()) == 0, "after 2 idle hours the old counts are cleared when the next round starts")
Run(599)
Gamerules:EndGame()
counts = Saved()
check(counts[101] == "1/10", "after 2 idle hours A starts again at 1, got " .. tostring(counts[101]))

-- Saved counts older than an hour are dropped on load.
Now = Now + 3700
LoadServer()
check(Lines()[1] == "Nobody has played a round in a row yet.", "stale save is dropped on load")

-- ---------------------------------------------------------------------------------------------
-- Commands

A.team, B.team, C.team, D.team = kTeam1Index, kTeam2Index, kTeam1Index, kTeam2Index
StartGame() Run(600) Gamerules:EndGame()
D.team = kSpectatorIndex
StartGame() Run(900) Gamerules:EndGame()
-- B steps out 1 minute into round 3: still counts, fewer minutes. Ties on rounds go to minutes,
-- then to the name.
StartGame() Run(60) B.team = kSpectatorIndex Run(240) Gamerules:EndGame()

local lines = Lines()
check(lines[1] == "Most rounds in a row: P101 3r, P103 3r, P102 3r", "rounds list, got " .. tostring(lines[1]))
check(lines[2] == "Most minutes in a row: P101 30m, P103 30m, P102 26m", "minutes list, got " .. tostring(lines[2]))

-- Only the top 5, and only connected players.
for id = 201, 207 do AddPlayer(id, kTeam1Index) end
StartGame() Run(600) Gamerules:EndGame()
table.remove(Players) -- 207 disconnects
lines = Lines()
local listed = select(2, lines[1]:gsub(",", "")) + 1
check(listed == 5, "rounds list has 5 names, got " .. listed)
check(not lines[1]:find("P207") and not lines[2]:find("P207"), "disconnected players are not listed")

-- The console gets everyone with a count: A and C (4 rounds, 30 + 10 min) and 201-206 (1 round,
-- 10 min). B and D sat the last round out; 207 is gone.
local full = SSM_MatchesInARow_GetFullStreaksLines()
check(#full == 18, "console list: 2 headers + 8 players twice, got " .. #full)
check(full[1] == "Rounds in a row:" and full[10] == "Minutes in a row:", "console list headers")
check(full[2] == "  1. P101  4r  40m" and full[3] == "  2. P103  4r  40m" and full[4] == "  3. P201  1r  10m",
    "console rounds ranking, got " .. tostring(full[2]) .. " | " .. tostring(full[3]) .. " | " .. tostring(full[4]))
check(full[11] == "  1. P101  40m  4r" and full[18] == "  8. P206  10m  1r", "console minutes ranking, got " .. tostring(full[11]) .. " | " .. tostring(full[18]))
local fullText = table.concat(full, "\n")
check(not fullText:find("P207") and not fullText:find("P102") and not fullText:find("P104"), "console list skips the disconnected and players at 0")

local registered, notified, printed = nil, {}, {}
Shine = {
    Commands = {},
    fromChat = false,
    RegisterCommand = function(self, con, chat, fn, noPerm)
        registered = { con = con, chat = chat, fn = fn, noPerm = noPerm }
        return { Help = function() end }
    end,
    IsCommandFromChat = function(self) return self.fromChat end,
    NotifyDualColour = function(self, client, _, _, _, prefix, _, _, _, text)
        notified[#notified + 1] = { client = client, text = prefix .. " " .. text }
    end
}
function ServerAdminPrint(client, text) printed[#printed + 1] = { client = client, text = text } end

local caller = Players[1].client
LoadServer() -- commands register on the first server update once Shine is there
Hooks.UpdateServer()
check(registered and registered.con == "sud_streaks" and registered.chat == "streaks", "commands registered")
check(registered and registered.noPerm == true, "open to everyone")
registered.fn(caller)
check(#printed == 18 and printed[1].client == caller, "console: the full list to the caller, got " .. #printed)
Shine.fromChat = true
registered.fn(caller)
check(#notified == 2 and notified[1].client == caller, "chat: 2 lines to the caller only")
check(notified[1].text:find("^%[Matches In A Row%] Most rounds") ~= nil, "chat line has the prefix")
Shine = nil

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
