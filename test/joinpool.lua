-- Logic test for Join Pool, run outside the game against the real mod files:
--   lua test/joinpool.lua        (from the repo root)
--
-- Stubs only the engine, vanilla and Shine globals the files touch. Proves who gets offered, the
-- gap maths, !readyq, the Lockteams lift, expiry and the commands; it says nothing about a real
-- server (spawning, the scoreboard, the taskbar flash).

local kSharedFiles = { "source/lua/SSM/Messages.lua", "source/lua/SSM/Strings.lua", "source/lua/SSM/Commands.lua" }
local kServerFile = "source/lua/SSM/JoinPool/Server.lua"

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

kTeamReadyRoom, kTeam1Index, kTeam2Index, kSpectatorIndex = 0, 1, 2, 3

local Files, Now, Hooks, Notified, Net, Joins = {}, 0, {}, {}, {}, {}
local Players = {}
local MaxPlayers, Reserved = 16, 0
local Started = true
local ChatHook
local LockDuringJoin = {}

function LoadConfigFile(name) return Files[name] and deepcopy(Files[name]) or nil end
function SaveConfigFile(name, data) Files[name] = deepcopy(data) end

Shared = {
    GetTime = function() return Now end,
    GetSystemTime = function() return 1000000 + math.floor(Now) end,
    Message = function(t) if DEBUG then print(t) end end
}

local function OnTeam(team)
    local list = {}
    for _, p in ipairs(Players) do if p.team == team then list[#list + 1] = p end end
    return list
end

Server = {
    GetOwner = function(player) return player.client end,
    ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end,
    SendNetworkMessage = function(a, b, c)
        if type(a) == "string" then Net[#Net + 1] = { name = a, data = b } else Net[#Net + 1] = { client = a, name = b, data = c } end
    end,
    GetMaxPlayers = function() return MaxPlayers end,
    GetNumClientsTotal = function() return #Players end,
    GetNumSpectators = function() return #OnTeam(kSpectatorIndex) end,
    GetReservedSlotLimit = function() return Reserved end
}
function GetHasReservedSlotAccess() return false end
function ServerAdminPrint() end

Event = { Hook = function(name, fn)
    local previous = Hooks[name]
    Hooks[name] = previous and function(...) previous(...) return fn(...) end or fn
end }
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    _G[className][methodName] = method
    return original
end

local LockTeams = { Enabled = true, TeamLock = true }
local AFKResets = {}
local Admins = {}
ShineUsers = {}
Shine = {
    NotifyDualColour = function(_, client, _, _, _, prefix, _, _, _, text)
        Notified[#Notified + 1] = { client = client, text = text }
    end,
    Hook = { Add = function(name, id, fn) if name == "PlayerSay" then ChatHook = fn end end },
    HasAccess = function(_, client, access) return Admins[client] and access == "sud_joinpool" end,
    GetUserData = function(_, client) return ShineUsers[client] end,
    Plugins = {
        lockteamsv2 = LockTeams,
        afkkick = { Enabled = true, ResetAFKTime = function(_, client) AFKResets[client] = (AFKResets[client] or 0) + 1 end }
    }
}

local nextId = 0
local function NewPlayer(name, team, skill, offset, options)
    options = options or {}
    nextId = nextId + 1
    local client = {
        id = nextId, steamId = 1000 + nextId, virtual = options.virtual == true,
        GetIsVirtual = function(self) return self.virtual end,
        GetUserId = function(self) return self.steamId end,
        GetId = function(self) return self.id end,
        GetIsSpectator = function(self) return self.player.team == kSpectatorIndex end,
        GetControllingPlayer = function(self) return self.player end
    }
    local player = {
        name = name, team = team, client = client, skill = skill, offset = offset or 0,
        commander = options.commander == true, commSkill = options.commSkill or 0, commOffset = options.commOffset or 0,
        GetName = function(self) return self.name end,
        GetTeamNumber = function(self) return self.team end,
        GetPlayerSkill = function(self) return self.skill end,
        GetPlayerSkillOffset = function(self) return self.offset end,
        isa = function(self, class) return class == "Commander" and self.commander end,
        GetCommanderTeamSkill = function(self)
            local s = self.commSkill > 0 and self.commSkill or self.skill
            return self.team == kTeam1Index and s + self.commOffset or s - self.commOffset
        end
    }
    client.player = player
    Players[#Players + 1] = player
    return player
end

local Gamerules = {
    GetGameStarted = function() return Started end,
    GetTeam = function(_, number)
        return { ForEachPlayer = function(_, fn) for _, p in ipairs(OnTeam(number)) do fn(p) end end }
    end,
    -- Through NS2Gamerules, so the mod's JoinTeam wrap (F4) sees every move, as in the game.
    JoinTeam = function(self, ...) return NS2Gamerules.JoinTeam(self, ...) end
}
local function BaseJoinTeam(self, player, team, force)
    Joins[#Joins + 1] = { name = player.name, team = team, force = force }
    LockDuringJoin[#LockDuringJoin + 1] = LockTeams.TeamLock
    if self.failJoinTeam == team then return false end
    player.team = team
    return true, player
end
function GetGamerules() return Gamerules end
NS2Gamerules = { ResetGame = function() end, JoinTeam = BaseJoinTeam }

local function Say(player, text)
    return ChatHook(player.client, { message = text })
end

local function Run(seconds)
    local stop = Now + seconds
    repeat
        Now = Now + 0.5
        Hooks.UpdateServer()
    until Now >= stop
end

-- Most tests switch the round-start wait off (OfferDelaySeconds 0) so pairs are offered at once;
-- Reset(true) keeps the defaults, wait included.
local function Reset(defaults)
    Files, Now, Hooks, Notified, Net, Joins, Players, LockDuringJoin, AFKResets, Admins = {}, 0, {}, {}, {}, {}, {}, {}, {}, {}
    if not defaults then
        Files["SSM_JoinPool.json"] = { OfferDelaySeconds = 0 }
    end
    nextId, MaxPlayers, Reserved, Started = 0, 16, 0, true
    LockTeams.TeamLock = true
    Gamerules.failJoinTeam = nil
    SSM = nil
    NS2Gamerules.JoinTeam = BaseJoinTeam
    for _, file in ipairs(kSharedFiles) do dofile(file) end
    dofile(kServerFile)
    Hooks.UpdateServer()   -- installs the chat hook
end

local function TextsTo(player)
    local out = {}
    for _, n in ipairs(Notified) do if n.client == player.client then out[#out + 1] = n.text end end
    return out
end
local function Has(player, pattern)
    for _, text in ipairs(TextsTo(player)) do if text:find(pattern, 1, true) then return true end end
    return false
end

-- 6v6, every fielder 1000 (no offset). marinesBonus moves the marine average.
local function Teams(size, marineSkill, alienSkill)
    local m, a = {}, {}
    for i = 1, size do m[i] = NewPlayer("M" .. i, kTeam1Index, marineSkill or 1000) end
    for i = 1, size do a[i] = NewPlayer("A" .. i, kTeam2Index, alienSkill or 1000) end
    return m, a
end

-- ---------------------------------------------------------------------------------------------
-- Tests

-- Config file written with the defaults.
Reset()
check(Files["SSM_JoinPool.json"] and Files["SSM_JoinPool.json"].MaxDifference == 75, "config written with MaxDifference 75")
check(Files["SSM_JoinPool.json"].ReadySeconds == 30, "config ReadySeconds 30")

-- Not live: refused.
Reset(); Started = false
local m, a = Teams(6)
local s1 = NewPlayer("Spec1", kSpectatorIndex, 1000)
check(Say(s1, "!joinq") == "", "command swallowed")
check(Has(s1, "live round"), "not live: told so")
check(#SSM.JoinPool_GetPool() == 0, "not live: not added")

-- On a team: refused.
Reset(); m, a = Teams(6)
Say(m[1], "!joinq")
check(Has(m[1], "already on a team"), "team player refused")

-- A basic pair at 6v6, even teams.
Reset(); m, a = Teams(6)
local p1 = NewPlayer("Pepito", kSpectatorIndex, 1100)
local p2 = NewPlayer("Juancito", kTeamReadyRoom, 1100)
local other = NewPlayer("Watcher", kSpectatorIndex, 5000)
Say(p1, "!joinq")
check(Has(p1, "join pool (1 waiting)"), "joinq reply with count")
Run(1.5)
check(SSM.JoinPool_GetProposal() == nil, "one player: no offer")
Say(p2, "!joinq")
Run(1.5)
local prop = SSM.JoinPool_GetProposal()
check(prop ~= nil, "two players at 6v6: offered")
check(Has(other, "are the best suitable joiners"), "public line to others")
check(not Has(p1, "best suitable joiners") and not Has(p2, "best suitable joiners"), "public line not to the pair")
check(Has(p1, "Type !readyq within 30 seconds") and Has(p2, "Type !readyq within 30 seconds"), "private line to both")
local flashes = 0
for _, n in ipairs(Net) do if n.name == "SSM_JoinPoolAttention" then flashes = flashes + 1 end end
check(flashes == 2, "taskbar flash sent to both")
local queueMsg
for _, n in ipairs(Net) do if n.name == "SSM_JoinPoolQueue" then queueMsg = n.data.clients end end
check(queueMsg and queueMsg:find("," .. p1.client.id .. ",", 1, true) and queueMsg:find("," .. p2.client.id .. ",", 1, true), "scoreboard list has both")

Say(p1, "!readyq")
check(Has(p1, "Waiting for"), "first ready waits")
check(#Joins == 0, "nobody moved after one ready")
Say(p2, "!readyq")
check(#Joins == 2, "both moved after both ready")
check(Joins[1].name == "Juancito", "ready-room player placed before the spectator")
check(Joins[1].force == nil and Joins[2].force == nil, "joins are not forced (normal respawn)")
check(LockDuringJoin[1] == false and LockDuringJoin[2] == false, "lockteams lifted during the joins")
check(LockTeams.TeamLock == true, "lockteams lock restored")
check(#OnTeam(kTeam1Index) == 7 and #OnTeam(kTeam2Index) == 7, "now 7v7")
check(#SSM.JoinPool_GetPool() == 0, "pool empty after placing")
check(Has(other, "joined Marines and"), "done line to everyone")

-- Lockteams required: not loaded, or teams not locked, and !joinq is refused.
Reset(); m, a = Teams(6)
Shine.Plugins.lockteamsv2 = nil
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Say(p1, "!joinq")
check(Has(p1, "needs Lockteams") and #SSM.JoinPool_GetPool() == 0, "no Lockteams: refused")
Shine.Plugins.lockteamsv2 = LockTeams
LockTeams.Enabled = false
Say(p1, "!joinq")
check(#SSM.JoinPool_GetPool() == 0, "Lockteams disabled: refused")
LockTeams.Enabled = true
LockTeams.TeamLock = false
Say(p1, "!joinq")
check(Has(p1, "teams are not locked") and #SSM.JoinPool_GetPool() == 0, "teams open: refused")

-- Unlocked mid-round: pool kept and paused, pending pair cancelled, told once; locked again: runs.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
check(SSM.JoinPool_GetProposal() ~= nil, "locked: offered")
LockTeams.TeamLock = false
Run(1.5)
check(SSM.JoinPool_GetProposal() == nil, "unlocked: pending pair cancelled")
check(#SSM.JoinPool_GetPool() == 2, "unlocked: pool kept")
check(Has(p1, "join pool is paused") and Has(p2, "join pool is paused"), "unlocked: members told")
Run(5)
local pausedLines = 0
for _, text in ipairs(TextsTo(p1)) do if text:find("paused", 1, true) then pausedLines = pausedLines + 1 end end
check(pausedLines == 1 and SSM.JoinPool_GetProposal() == nil, "unlocked: told once, nobody offered")
Say(p1, "!readyq")
check(#Joins == 0, "unlocked: !readyq does nothing")
LockTeams.TeamLock = true
Run(1.5)
check(Has(p1, "locked again") and SSM.JoinPool_GetProposal() ~= nil, "locked again: running and offered")

-- Orientation and gap maths: marines average 1050, aliens 1000 (gap +50). Joiners 1400 and 600.
-- Strong one to aliens: (6*1050+600)/7 - (6*1000+1400)/7 = 6900/7 - 7400/7 = -71.4 (allowed).
-- Other way: (6*1050+1400)/7 - (6*1000+600)/7 = 7700/7 - 6600/7 = +157 (not).
Reset(); m, a = Teams(6, 1050, 1000)
p1 = NewPlayer("Strong", kSpectatorIndex, 1400); p2 = NewPlayer("Weak", kSpectatorIndex, 600)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
prop = SSM.JoinPool_GetProposal()
check(prop and prop.alienName == "Strong" and prop.marineName == "Weak", "picks the orientation with the smaller gap")
check(prop and math.abs(prop.after - (-500 / 7)) < 1e-6, "gap after computed from team sums")
check(prop and math.abs(prop.before - 50) < 1e-6, "gap before")
check(Has(m[1], "+50 Marines") and Has(m[1], "+71 Aliens"), "gap shown as +N Team")

-- Side skills: offsets used per team. Joiner X: skill 1000, offset +200 (marine 1200, alien 800).
Reset(); m, a = Teams(6)
local x = NewPlayer("X", kSpectatorIndex, 1000, 200); local y = NewPlayer("Y", kSpectatorIndex, 1000, 0)
Say(x, "!joinq"); Say(y, "!joinq"); Run(1.5)
prop = SSM.JoinPool_GetProposal()
-- X marine + Y alien: (6000+1200)/7 - (6000+1000)/7 = +28.6; Y marine + X alien: (7000)/7 - (6800)/7 = +28.6.
check(prop and math.abs(math.abs(prop.after) - 200 / 7) < 1e-6, "side offsets applied")

-- Over the limit: not offered.
Reset(); m, a = Teams(6)
p1 = NewPlayer("Huge", kSpectatorIndex, 2000); p2 = NewPlayer("Tiny", kSpectatorIndex, 0)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
-- Best: (6000+0)/7 - (6000+2000)/7 = -285: over 75.
check(SSM.JoinPool_GetProposal() == nil, "pair over the limit not offered")

-- Already over the limit: a pair that brings it closer is allowed.
Reset(); m, a = Teams(6, 1200, 1000)   -- gap +200
p1 = NewPlayer("A", kSpectatorIndex, 2000); p2 = NewPlayer("B", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
-- B marine, A alien: (7200+1000)/7 - (6000+2000)/7 = 8200/7 - 8000/7 = +28.6
prop = SSM.JoinPool_GetProposal()
check(prop and math.abs(prop.after - 200 / 7) < 1e-6, "far-apart game: closing pair offered")
Reset(); m, a = Teams(6, 1300, 1000)   -- gap +300
p1 = NewPlayer("A", kSpectatorIndex, 1000); p2 = NewPlayer("B", kSpectatorIndex, 1500)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
-- Best: A marine, B alien: (7800+1000)/7 - (6000+1500)/7 = 8800/7 - 7500/7 = 185.7 < 300 -> allowed.
prop = SSM.JoinPool_GetProposal()
check(prop and math.abs(prop.after - 1300 / 7) < 1e-6, "far-apart game: any improvement allowed even if still over 75")

-- Best pair out of three.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1500); p2 = NewPlayer("P2", kSpectatorIndex, 1010); local p3 = NewPlayer("P3", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Say(p3, "!joinq"); Run(1.5)
prop = SSM.JoinPool_GetProposal()
check(prop and ((prop.marineName == "P2" and prop.alienName == "P3") or (prop.marineName == "P3" and prop.alienName == "P2")), "picks the pair with the smallest gap")

-- Commanders count at commander skill.
Reset(); m, a = Teams(6)
m[1].commander = true; m[1].commSkill = 400   -- marines: (5*1000 + 400)/6 = 900, gap -100
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
prop = SSM.JoinPool_GetProposal()
check(prop and math.abs(prop.before - (-100)) < 1e-6, "commander counted at commander skill")

-- Team sizes: 7v7 runs, 8v8 and 5v5 do not, uneven does not.
for _, case in ipairs({ { 7, 7, true }, { 8, 8, false }, { 5, 5, false } }) do
    Reset(); Teams(case[1])
    p1 = NewPlayer("P1", kTeamReadyRoom, 1000); p2 = NewPlayer("P2", kTeamReadyRoom, 1000)
    Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
    check((SSM.JoinPool_GetProposal() ~= nil) == case[3], case[1] .. "v" .. case[2] .. (case[3] and " offered" or " not offered"))
end
Reset(); m, a = Teams(6); m[1].team = kSpectatorIndex
p1 = NewPlayer("P1", kTeamReadyRoom, 1000); p2 = NewPlayer("P2", kTeamReadyRoom, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
check(SSM.JoinPool_GetProposal() == nil, "uneven teams not offered")

-- A held body (virtual client) on a team pauses it.
Reset(); m, a = Teams(6); m[1].client.virtual = true
p1 = NewPlayer("P1", kTeamReadyRoom, 1000); p2 = NewPlayer("P2", kTeamReadyRoom, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
check(SSM.JoinPool_GetProposal() == nil, "held body on a team: not offered")

-- Slots: two spectators need two free player slots.
Reset(); m, a = Teams(6)
NewPlayer("RR1", kTeamReadyRoom, 1000); NewPlayer("RR2", kTeamReadyRoom, 1000); NewPlayer("RR3", kTeamReadyRoom, 1000)
MaxPlayers = 16   -- 12 on teams + 3 in the ready room = 15: one slot free
p1 = NewPlayer("S1", kSpectatorIndex, 1000); p2 = NewPlayer("S2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
check(SSM.JoinPool_GetProposal() == nil, "two spectators, one free slot: not offered")

-- Expiry: one ready, the other not.
Reset(); m, a = Teams(6)
p1 = NewPlayer("Fast", kSpectatorIndex, 1000); p2 = NewPlayer("Slow", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
Say(p1, "!readyq")
Run(31)
local pool = SSM.JoinPool_GetPool()
check(#pool == 1 and pool[1].steamId == p1.client.steamId, "expired: the ready player stays, the other leaves")
check(Has(p2, "did not type !readyq in time"), "expired: told the slow one")
check(Has(p1, "Slow did not type !readyq"), "expired: told the ready one")
check(Has(m[1], "Not ready in time: Slow"), "expired: public line")
check(#Joins == 0, "expired: nobody moved")

-- Teams change before both are ready: cancelled, both stay.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
a[1].skill = 0; a[2].skill = 0   -- aliens drop to 833: gap +167, pair cannot fix it below
Say(p1, "!readyq"); Say(p2, "!readyq")
check(#Joins == 2, "still placed when it improves an already-wide gap")
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
NewPlayer("M7", kTeam1Index, 1000)   -- now 7v6
Say(p1, "!readyq"); Say(p2, "!readyq")
check(#Joins == 0, "teams no longer even: cancelled")
check(Has(p1, "The teams changed") and #SSM.JoinPool_GetPool() == 2, "cancelled: both told and kept")

-- A join failing half way is undone.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
Gamerules.failJoinTeam = SSM.JoinPool_GetProposal().alien == p1.client.steamId and kTeam2Index or kTeam2Index
Say(p1, "!readyq"); Say(p2, "!readyq")
check(#OnTeam(kTeam1Index) == 6 and #OnTeam(kTeam2Index) == 6, "half-done join undone")
check(LockTeams.TeamLock == true, "lock restored after a failure")

-- !exitq, !listq, !readyq with nothing pending.
Reset(); m, a = Teams(6)
p1 = NewPlayer("Ana", kSpectatorIndex, 1000)
Say(p1, "!listq"); check(Has(p1, "Nobody is in the join pool"), "listq empty")
Say(p1, "!joinq"); Say(p1, "!listq"); check(Has(p1, "Join pool (1): Ana"), "listq names")
Say(p1, "!joinq"); check(Has(p1, "already in the join pool"), "joinq twice")
check(Say(p1, "!readyq") == "" and Has(p1, "Nobody has asked you to type !readyq"), "readyq with nothing pending: private reply")
Say(p1, "!exitq"); check(Has(p1, "You left the join pool") and #SSM.JoinPool_GetPool() == 0, "exitq")
Say(p1, "!exitq"); check(Has(p1, "not in the join pool"), "exitq when not in")

-- Leaving during a proposal: the partner is told and stays.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
Say(p1, "!exitq")
check(SSM.JoinPool_GetProposal() == nil and Has(p2, "other player left"), "exit during proposal: partner told")

-- Joining a team by hand removes you from the pool.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Say(p1, "!joinq"); p1.team = kTeam1Index; Run(1.5)
check(#SSM.JoinPool_GetPool() == 0, "joined by hand: left the pool")

-- Round over clears the pool and says so.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Started = false; Run(1)
check(#SSM.JoinPool_GetPool() == 0 and Has(p1, "round is over"), "round over clears the pool")

-- AFK shield.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Say(p1, "!joinq"); Run(11)
check((AFKResets[p1.client] or 0) >= 1, "queued player shielded from AFK kick")

-- Admin switch.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); local admin = NewPlayer("Admin", kSpectatorIndex, 1000)
Say(p1, "!joinq")
Hooks.Console_sud_joinpool(p1.client, "off")
check(Has(p1, "Only admins"), "non-admin refused")
Admins[admin.client] = true
Hooks.Console_sud_joinpool(admin.client, "off")
check(#SSM.JoinPool_GetPool() == 0 and Has(p1, "switched off for this round"), "admin off clears the pool")
Say(p1, "!joinq"); check(Has(p1, "switched off"), "joinq while off")
Hooks.Console_sud_joinpool(nil, "on")
Say(p1, "!joinq"); check(#SSM.JoinPool_GetPool() == 1, "server console switches it back on")
Hooks.Console_sud_joinpool(admin.client, "off")
NS2Gamerules.ResetGame(Gamerules)
Say(p1, "!joinq"); check(#SSM.JoinPool_GetPool() == 1, "new round: on again")

-- Any Shine admin (in a Shine user group) can use it without being given sud_joinpool.
Reset(); m, a = Teams(6)
local trusted = NewPlayer("Trusted", kSpectatorIndex, 1000)
ShineUsers = { [trusted.client] = { Group = "TrustedPlayer" } }
Hooks.Console_sud_joinpool(trusted.client, "off")
check(Has(trusted, "switched the join pool off"), "Shine admin without explicit access switches it")
ShineUsers = {}

-- Round-start wait (default 30 s): !joinq works at once, no pair before 30 s, then the best pair.
Reset(true)
check(Files["SSM_JoinPool.json"].OfferDelaySeconds == 30, "config OfferDelaySeconds 30")
m, a = Teams(6)
p1 = NewPlayer("Early1", kSpectatorIndex, 1500); p2 = NewPlayer("Early2", kSpectatorIndex, 1060)
Say(p1, "!joinq"); Say(p2, "!joinq")
check(#SSM.JoinPool_GetPool() == 2, "round start: !joinq accepted")
check(Has(p1, "Pairs are picked from 30 seconds") and Has(p1, "(30 s left)"), "round start: told about the wait")
Run(10)
check(SSM.JoinPool_GetProposal() == nil, "round start: no pair at 10 s")
p3 = NewPlayer("Later", kSpectatorIndex, 1000)
Say(p3, "!joinq")
check(Has(p3, "(20 s left)"), "wait line counts down")
Run(19)
check(SSM.JoinPool_GetProposal() == nil, "round start: no pair at 29 s")
Run(2)
prop = SSM.JoinPool_GetProposal()
check(prop and ((prop.marineName == "Early2" and prop.alienName == "Later") or (prop.marineName == "Later" and prop.alienName == "Early2")), "after 30 s: best pair of everyone, not the first two")
local p4 = NewPlayer("AfterWait", kSpectatorIndex, 1000)
Say(p4, "!joinq")
check(not Has(p4, "Pairs are picked from"), "after the wait: no wait line")
-- A new round starts the wait again.
Started = false; Run(1); Started = true
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(5)
check(SSM.JoinPool_GetProposal() == nil and Has(p1, "Pairs are picked from"), "new round: wait again")

-- Spanish texts.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Say(p1, "!lang es"); Say(p1, "!joinq")
check(Has(p1, "Está en la cola para entrar"), "Spanish reply")

-- Plain !ready is not the join pool's (Shine's tournament mode uses it): left alone, even from a
-- player with a pair waiting.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
local before = #TextsTo(p1)
check(Say(p1, "!ready") == nil and #TextsTo(p1) == before, "!ready: not swallowed, no reply")
check(Say(m[1], "!ready") == nil, "a commander's !ready passes through")

-- Thunderdome: off by default, on with EnabledOnThunderdome or an admin's sud_joinpool on.
Reset(); m, a = Teams(6)
Shared.GetThunderdomeEnabled = function() return true end
check(Files["SSM_JoinPool.json"].EnabledOnThunderdome == false, "config written with EnabledOnThunderdome false")
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Say(p1, "!joinq")
check(Has(p1, "off on Thunderdome games") and #SSM.JoinPool_GetPool() == 0, "Thunderdome: !joinq refused")
local tdAdmin = NewPlayer("TDAdmin", kSpectatorIndex, 1000)
Admins[tdAdmin.client] = true
Hooks.Console_sud_joinpool(tdAdmin.client, "on")
Say(p1, "!joinq"); Say(p2, "!joinq"); Run(1.5)
check(#SSM.JoinPool_GetPool() == 2 and SSM.JoinPool_GetProposal() ~= nil, "Thunderdome: an admin's on works for the round")
-- The setting: reload the server file with it on.
Reset(); m, a = Teams(6)
Files["SSM_JoinPool.json"] = { OfferDelaySeconds = 0, EnabledOnThunderdome = true }
SSM = nil
for _, file in ipairs(kSharedFiles) do dofile(file) end
dofile(kServerFile)
Hooks.UpdateServer()
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Say(p1, "!joinq")
check(#SSM.JoinPool_GetPool() == 1, "Thunderdome: EnabledOnThunderdome true turns it on")
Shared.GetThunderdomeEnabled = nil

-- ---------------------------------------------------------------------------------------------
-- F4 (v1.5)

-- The game's private "rr" handler: anyone not in the ready room goes there, unforced.
local function GameReadyRoom(player)
    if player.team ~= kTeamReadyRoom then
        return Gamerules:JoinTeam(player, kTeamReadyRoom)
    end
end
-- F4, with the engine calling this mod's hook before or after the game's handler.
local function PressF4(player, gameFirst)
    if gameFirst then
        GameReadyRoom(player)
        Hooks.Console_rr(player.client)
    else
        Hooks.Console_rr(player.client)
        GameReadyRoom(player)
    end
end
local function InPool(player)
    for _, entry in ipairs(SSM.JoinPool_GetPool()) do
        if entry.steamId == player.client.steamId then return true end
    end
    return false
end

Reset(); m, a = Teams(6)
check(Files["SSM_JoinPool.json"].F4JoinsQueue == true, "config written with F4JoinsQueue true")
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
PressF4(p1, false)
check(InPool(p1) and p1.team == kSpectatorIndex, "F4, mod's hook first: in the pool, still a spectator")
check(Has(p1, "You are in the join pool"), "F4 gives the !joinq line")
check(#Joins == 0, "the game's move to the ready room was refused")

p2 = NewPlayer("P2", kSpectatorIndex, 1000)
PressF4(p2, true)
check(InPool(p2) and p2.team == kSpectatorIndex, "F4, game's handler first: moved back, in the pool")
check(Joins[#Joins].team == kSpectatorIndex and Joins[#Joins].force == true, "moved back with a forced join")

Notified = {}
PressF4(p1, false)
check(Has(p1, "Type !exitq to leave it") and #SSM.JoinPool_GetPool() == 2 and p1.team == kSpectatorIndex,
    "F4 when already in: told how to leave, nothing changes")
Notified = {}
PressF4(p2, true)
check(Has(p2, "Type !exitq to leave it") and p2.team == kSpectatorIndex, "same with the game's handler first")

-- The pool does not take players: F4 works as usual, both orders.
local function UsualF4(label, setup, teardown)
    for _, gameFirst in ipairs({ false, true }) do
        Reset(); m, a = Teams(6)
        setup()
        local p = NewPlayer("P", kSpectatorIndex, 1000)
        PressF4(p, gameFirst)
        check(p.team == kTeamReadyRoom and not InPool(p), label .. (gameFirst and " (game first)" or " (mod first)"))
        if teardown then teardown() end
    end
end
UsualF4("teams unlocked: F4 goes to the ready room", function() LockTeams.TeamLock = false end)
UsualF4("round not live: F4 goes to the ready room", function() Started = false end)
UsualF4("pool off this round: F4 goes to the ready room", function()
    local admin = NewPlayer("Admin", kSpectatorIndex, 1000)
    Admins[admin.client] = true
    Hooks.Console_sud_joinpool(admin.client, "off")
end)
UsualF4("Lockteams missing: F4 goes to the ready room",
    function() LockTeams.Enabled = false end, function() LockTeams.Enabled = true end)
UsualF4("F4JoinsQueue false: F4 goes to the ready room", function()
    Files["SSM_JoinPool.json"] = { OfferDelaySeconds = 0, F4JoinsQueue = false }
    SSM = nil
    NS2Gamerules.JoinTeam = BaseJoinTeam
    for _, file in ipairs(kSharedFiles) do dofile(file) end
    dofile(kServerFile)
    Hooks.UpdateServer()
end)

-- Moves to the ready room that are not the player's own F4 are left alone.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000)
Gamerules:JoinTeam(p1, kTeamReadyRoom)
check(p1.team == kTeamReadyRoom, "another mod's unforced move to the ready room goes through")
Now = Now + 1
Hooks.Console_rr(p1.client)
check(p1.team == kTeamReadyRoom and not InPool(p1), "a later F4 in the ready room does not undo it")

-- A mark the game's handler never used (it refused, as on Thunderdome) does not block later moves.
p2 = NewPlayer("P2", kSpectatorIndex, 1000)
Hooks.Console_rr(p2.client)
check(InPool(p2) and p2.team == kSpectatorIndex, "mod's hook alone: queued")
Now = Now + 1
Gamerules:JoinTeam(p2, kTeamReadyRoom)
check(p2.team == kTeamReadyRoom, "a stale mark does not block a later move")

-- Ready room players: F4 does nothing there (the game leaves them), and they are not queued.
p3 = NewPlayer("P3", kTeamReadyRoom, 1000)
PressF4(p3, false); PressF4(p3, true)
check(p3.team == kTeamReadyRoom and not InPool(p3), "F4 in the ready room: nothing")

-- Players on a team: F4 takes them to the ready room as usual.
PressF4(m[1], false)
check(m[1].team == kTeamReadyRoom and not InPool(m[1]), "F4 on a team: to the ready room, not queued")

-- F4 joiners are paired like anyone else.
Reset(); m, a = Teams(6)
p1 = NewPlayer("P1", kSpectatorIndex, 1000); p2 = NewPlayer("P2", kSpectatorIndex, 1000)
PressF4(p1, false); PressF4(p2, true)
Run(1.5)
check(SSM.JoinPool_GetProposal() ~= nil, "two F4 joiners are offered as a pair")

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then os.exit(1) end
