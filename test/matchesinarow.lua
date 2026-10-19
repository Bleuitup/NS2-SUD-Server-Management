-- Logic test for Matches In A Row, run outside the game against the real mod file:
--   lua test/matchesinarow.lua        (from the repo root)
--
-- Stubs only the few engine, vanilla and Shine globals the file touches. Proves the counting
-- rules and the commands; it says nothing about how they behave on a real server.

local kMessagesFile = "source/lua/SSM/Messages.lua"
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
    dofile(kMessagesFile)
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

-- What sud_streaks prints in the console.
local Lines = function() return SSM_MatchesInARow_GetConsoleLines() end
local kNobody = "No rounds have been counted yet this session."

-- ---------------------------------------------------------------------------------------------
-- Counting

LoadServer()
check(Files["SSM_MatchesInARow.json"].GracePeriodSeconds == 120, "default settings file written")
check(#Lines() == 1 and Lines()[1] == kNobody, "before any round: one line saying so")

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
check(Lines()[2] == "  1. P101  2r" and Lines()[3] == "  2. P103  1r", "after map change the counts are still there, got " .. tostring(Lines()[2]))

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
check(Lines()[2] == "  1. P101  3r" and #Lines() == 5, "restart 65 minutes into a round keeps the counts, got " .. tostring(Lines()[2]))

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
check(Lines()[1] == kNobody, "stale save is dropped on load")

-- ---------------------------------------------------------------------------------------------
-- Commands

A.team, B.team, C.team, D.team = kTeam1Index, kTeam2Index, kTeam1Index, kTeam2Index
StartGame() Run(600) Gamerules:EndGame()
D.team = kSpectatorIndex
StartGame() Run(900) Gamerules:EndGame()
-- B steps out 1 minute into round 3: still counts, fewer minutes. Ties on rounds go to minutes,
-- then to the name.
StartGame() Run(60) B.team = kSpectatorIndex Run(240) Gamerules:EndGame()

-- Chat: one ranking per command, each row showing only the value it is sorted by.
local function ChatText(lines)
    local out = {}
    for i, line in ipairs(lines) do out[i] = (line[2] and "> " or "") .. line[1] end
    return table.concat(out, "\n")
end
local chat = SSM_MatchesInARow_GetChatLines("rounds")
check(ChatText(chat) == table.concat({
    "Players sorted by rounds played", "> 1. P101  3r", "> 2. P103  3r", "> 3. P102  3r" }, "\n"),
    "chat rounds ranking, got:\n" .. ChatText(chat))
chat = SSM_MatchesInARow_GetChatLines("minutes")
check(ChatText(chat) == table.concat({
    "Players sorted by minutes played", "> 1. P101  30m", "> 2. P103  30m", "> 3. P102  26m" }, "\n"),
    "chat minutes ranking, got:\n" .. ChatText(chat))

-- Only the top 5 in chat, and only connected players anywhere.
for id = 201, 207 do AddPlayer(id, kTeam1Index) end
StartGame() Run(600) Gamerules:EndGame()
table.remove(Players) -- 207 disconnects
chat = SSM_MatchesInARow_GetChatLines("rounds")
check(ChatText(chat) == table.concat({
    "Players sorted by rounds played", "> 1. P101  4r", "> 2. P103  4r",
    "> 3. P201  1r", "> 4. P202  1r", "> 5. P203  1r" }, "\n"),
    "chat: header + top 5 by rounds, got:\n" .. ChatText(chat))
chat = SSM_MatchesInARow_GetChatLines("minutes")
check(#chat == 6 and chat[2][1] == "1. P101  40m" and chat[6][1] == "5. P203  10m", "chat: header + top 5 by minutes")
check(not ChatText(chat):find("P207"), "disconnected players are not listed")

-- The console gets everyone with a count: A and C (4 rounds, 30 + 10 min) and 201-206 (1 round,
-- 10 min). B and D sat the last round out; 207 is gone.
local full = Lines()
check(#full == 19, "console list: 2 headers, a blank line, 8 players twice, got " .. #full)
check(full[1] == "Players sorted by rounds played" and full[10] == "" and full[11] == "Players sorted by minutes played", "console list headers")
check(full[2] == "  1. P101  4r" and full[3] == "  2. P103  4r" and full[4] == "  3. P201  1r",
    "console rounds ranking, got " .. tostring(full[2]) .. " | " .. tostring(full[3]) .. " | " .. tostring(full[4]))
check(full[12] == "  1. P101  40m" and full[19] == "  8. P206  10m", "console minutes ranking, got " .. tostring(full[12]) .. " | " .. tostring(full[19]))
local fullText = table.concat(full, "\n")
check(not fullText:find("P207") and not fullText:find("P102") and not fullText:find("P104"), "console list skips the disconnected and players at 0")

-- The commands themselves.
local sayHooks, notified, printed = {}, {}, {}
Shine = {
    Hook = { Add = function(event, name, fn) sayHooks[event .. ":" .. name] = fn end },
    NotifyDualColour = function(self, client, pr, pg, pb, prefix, r, g, b, text)
        notified[#notified + 1] = { client = client, prefix = prefix, color = pr .. "," .. pg .. "," .. pb, text = text }
    end
}
function ServerAdminPrint(client, text) printed[#printed + 1] = { client = client, text = text } end

local caller = Players[1].client
LoadServer() -- the chat hook goes in on the first server update, once Shine is there
check(Hooks["Console_sud_streaks"] ~= nil, "sud_streaks is a plain console command")
Hooks.UpdateServer()
local onSay = sayHooks["PlayerSay:SSM_MatchesInARow"]
check(onSay ~= nil, "chat hooked through Shine's PlayerSay")

Hooks["Console_sud_streaks"](caller)
check(#printed == 19 and printed[1].client == caller and printed[2].client == caller, "console: the full list to the caller only, got " .. #printed)

check(onSay(caller, { message = "hello" }) == nil and #notified == 0, "ordinary chat is left alone")
check(onSay(caller, { message = "!streaks" }) == nil and #notified == 0, "!streaks is no longer a command")
check(onSay(caller, { message = "  !StreakR " }) == "", "!streakr is answered and hidden from chat")
check(#notified == 6, "!streakr: 6 lines, got " .. #notified)
check(notified[1].text == "Players sorted by rounds played", "!streakr shows the rounds ranking")
check(notified[1].client == caller and notified[6].client == caller, "chat goes to the caller only")
check(notified[1].prefix == "[NS2 SUD]" and notified[1].color == "255,0,255", "the header carries the magenta [NS2 SUD] tag")
check(notified[2].prefix == "" and notified[2].text == "1. P101  4r", "rows continue under the header, got " .. tostring(notified[2].text))
notified = {}
check(onSay(caller, { message = "/streakm" }) == "", "/streakm works too")
check(#notified == 6 and notified[1].text == "Players sorted by minutes played" and notified[2].text == "1. P101  40m",
    "!streakm shows the minutes ranking, got " .. tostring(notified[2] and notified[2].text))

-- Before any round: one line, to the caller only, in both places.
Now = Now + 7200
LoadServer()
notified, printed = {}, {}
Hooks["Console_sud_streaks"](caller)
check(#printed == 1 and printed[1].text == kNobody, "console before any round: one line")
Hooks.UpdateServer()
sayHooks["PlayerSay:SSM_MatchesInARow"](caller, { message = "!streakm" })
check(#notified == 1 and notified[1].text == kNobody and notified[1].prefix == "[NS2 SUD]", "chat before any round: one tagged line")
Shine = nil

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
