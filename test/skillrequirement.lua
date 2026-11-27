-- Logic test for the Skill Requirement (v1.6), run outside the game against the real mod files:
--   lua test/skillrequirement.lua        (from the repo root)
--
-- Stubs only the engine, vanilla and Shine globals the files touch. Proves who is held and why,
-- the tier formula, the country lookup, the messages, sud_allow / sud_disallow and the SUD Queue
-- refusals; it says nothing about a real server (the HTTP request, Shine's admin menu).

local kSharedFiles = { "source/lua/SSM/Messages.lua", "source/lua/SSM/Strings.lua", "source/lua/SSM/Commands.lua" }
local kJoinPoolFile = "source/lua/SSM/JoinPool/Server.lua"
local kServerFile = "source/lua/SSM/SkillRequirement/Server.lua"

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
kRookieLevel = 10

local Files, Now, Hooks, Notified, Printed, Joins, Requests = {}, 0, {}, {}, {}, {}, {}
local Players = {}
local Thunderdome, Password, Started = false, false, true
local ChatHook
Logged = {}

function LoadConfigFile(name) return Files[name] and deepcopy(Files[name]) or nil end
function SaveConfigFile(name, data) Files[name] = deepcopy(data) end

Shared = {
    GetTime = function() return Now end,
    GetSystemTime = function() return 1000000 + math.floor(Now) end,
    Message = function(t) Logged[#Logged + 1] = t if DEBUG then print(t) end end,
    GetThunderdomeEnabled = function() return Thunderdome end,
    SendHTTPRequest = function(url, method, params, callback)
        Requests[#Requests + 1] = { url = url, callback = callback }
    end
}
-- The response "body" is a key into Bodies, so tests hand back plain tables.
local Bodies = {}
json = { decode = function(data) return Bodies[data] end }
function IPAddressToString(address) return address end

local function OnTeam(team)
    local list = {}
    for _, p in ipairs(Players) do if p.team == team then list[#list + 1] = p end end
    return list
end

Server = {
    GetOwner = function(player) return player.client end,
    ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end,
    SendNetworkMessage = function() end,
    GetMaxPlayers = function() return 16 end,
    GetNumClientsTotal = function() return #Players end,
    GetNumSpectators = function() return #OnTeam(kSpectatorIndex) end,
    GetReservedSlotLimit = function() return 0 end,
    GetClientAddress = function(client) return client.ip end
}
function GetHasReservedSlotAccess() return false end
function ServerAdminPrint(client, text) Printed[#Printed + 1] = { client = client, text = text } end

Event = { Hook = function(name, fn)
    local previous = Hooks[name]
    Hooks[name] = previous and function(...) previous(...) return fn(...) end or fn
end }
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    _G[className][methodName] = method
    return original
end

-- The game's formula (NS2Utility.lua).
function GetPlayerSkillTier(skill, isRookie, adagradSum, isBot)
    if isBot then return -1 end
    if isRookie then return 0 end
    if not skill or skill == -1 then return -2 end
    if adagradSum then
        if adagradSum <= 0 then skill = 0 else skill = math.max(skill - 25 / math.sqrt(adagradSum), 0) end
    end
    if skill <= 300 then return 1 end
    if skill <= 750 then return 2 end
    if skill <= 1400 then return 3 end
    if skill <= 2100 then return 4 end
    if skill <= 2900 then return 5 end
    if skill <= 4100 then return 6 end
    return 7
end

local LockTeams = { Enabled = true, TeamLock = true }
local Access = {}   -- [client] = { permission = true }
Shine = {
    NotifyDualColour = function(_, client, _, _, _, prefix, _, _, _, text)
        Notified[#Notified + 1] = { client = client, text = text }
    end,
    Hook = { Add = function(name, id, fn) if name == "PlayerSay" then ChatHook = fn end end, Broadcast = function() end },
    HasAccess = function(_, client, access) return Access[client] ~= nil and Access[client][access] == true end,
    Plugins = {
        lockteamsv2 = LockTeams,
        afkkick = { Enabled = true, ResetAFKTime = function() end }
    },
    GameIDs = { Get = function(_, client) return client.gameId end }
}
local function IdOf(c)
    if type(c) == "number" then return c end
    if type(c) == "string" then return tonumber(c) end
    return c:GetUserId()
end
function Shine:GetUserData(c)
    local id = IdOf(c)
    if not id then return nil end
    return self.UserData.Users[tostring(id)], id
end
function Shine:GetGroupData(name) return self.UserData.Groups[name] end
function Shine:CreateGroup(name, immunity, blacklist)
    local group = { Immunity = immunity or 10, IsBlacklist = blacklist or false, Commands = {} }
    self.UserData.Groups[name] = group
    self.saves = self.saves + 1
    return group
end
function Shine:CreateUser(c, group)
    local user = { Group = group }
    self.UserData.Users[tostring(IdOf(c))] = user
    self.saves = self.saves + 1
    return user
end
function Shine:DeleteUser(c)
    local key = tostring(IdOf(c) or c)
    if not self.UserData.Users[key] then return false end
    self.UserData.Users[key] = nil
    self.saves = self.saves + 1
    return true
end
function Shine:SaveUsers() self.saves = self.saves + 1 end
function Shine.GetClientByID(id)
    for _, p in ipairs(Players) do if p.client.gameId == id then return p.client end end
end
function Shine:GetClient(text)
    local number = tonumber(text)
    for _, p in ipairs(Players) do
        if number and (p.client.steamId == number or p.client.gameId == number) then return p.client end
        if not number and p.name:lower():find(text:lower(), 1, true) then return p.client end
    end
end
function Shine.SteamIDToNS2(text)
    local x, y = text:match("^STEAM_%d:(%d):(%d+)$")
    return x and tonumber(y) * 2 + tonumber(x) or nil
end
function Shine.GetClientInfo(client) return "admin" end

local nextId = 0
local function NewPlayer(name, team, skill, options)
    options = options or {}
    nextId = nextId + 1
    local client = {
        id = nextId, steamId = 1000 + nextId, gameId = nextId, virtual = options.virtual == true,
        ip = options.ip or ("200.1.1." .. nextId),
        GetIsVirtual = function(self) return self.virtual end,
        GetUserId = function(self) return self.virtual and 0 or self.steamId end,
        GetId = function(self) return self.id end,
        GetIsSpectator = function(self) return self.player.team == kSpectatorIndex end,
        GetControllingPlayer = function(self) return self.player end
    }
    local player = {
        name = name, team = team, client = client, skill = skill, rookie = options.rookie == true,
        adagrad = options.adagrad,
        GetName = function(self) return self.name end,
        GetTeamNumber = function(self) return self.team end,
        GetPlayerSkill = function(self) return self.skill end,
        GetPlayerSkillOffset = function() return 0 end,
        GetIsRookie = function(self) return self.rookie end,
        GetAdagradSum = function(self) return self.adagrad end,
        isa = function() return false end,
        GetCommanderTeamSkill = function(self) return self.skill end
    }
    client.player = player
    Players[#Players + 1] = player
    if Hooks.ClientConnect then Hooks.ClientConnect(client) end
    return player
end

local Gamerules = {
    GetGameStarted = function() return Started end,
    GetTeam = function(_, number)
        return { ForEachPlayer = function(_, fn) for _, p in ipairs(OnTeam(number)) do fn(p) end end }
    end,
    JoinTeam = function(self, ...) return NS2Gamerules.JoinTeam(self, ...) end
}
local function BaseJoinTeam(self, player, team, force)
    Joins[#Joins + 1] = { name = player.name, team = team, force = force }
    player.team = team
    return true, player
end
function GetGamerules() return Gamerules end
NS2Gamerules = { ResetGame = function() end, JoinTeam = BaseJoinTeam }

local function Run(seconds)
    local stop = Now + seconds
    repeat
        Now = Now + 0.5
        Hooks.UpdateServer()
    until Now >= stop
end

local function Load()
    Hooks, ChatHook = {}, nil
    SSM = nil
    NS2Gamerules.JoinTeam = BaseJoinTeam
    for _, file in ipairs(kSharedFiles) do dofile(file) end
    SSM.HasPassword = function() return Password end
    dofile(kJoinPoolFile)
    dofile(kServerFile)
    Hooks.UpdateServer()   -- installs the chat hook
end

-- config: the SSM_SkillRequirement.json to start with (nil: none, the defaults are written).
local function Reset(config)
    Files, Now, Notified, Printed, Joins, Requests, Players, Access, Bodies = {}, 0, {}, {}, {}, {}, {}, {}, {}
    Files["SSM_JoinPool.json"] = { OfferDelaySeconds = 0 }
    if config then Files["SSM_SkillRequirement.json"] = config end
    nextId, Thunderdome, Password, Started = 0, false, false, true
    LockTeams.TeamLock = true
    Shine.UserData = { Users = {}, Groups = {} }
    Shine.saves = 0
    Load()
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
local function Count(player, pattern)
    local n = 0
    for _, text in ipairs(TextsTo(player)) do if text:find(pattern, 1, true) then n = n + 1 end end
    return n
end
local function Clear() Notified, Printed = {}, {} end

local function TryJoin(player, team)
    return Gamerules:JoinTeam(player, team, false)
end
local function Console(name, caller, ...)
    Hooks["Console_" .. name](caller and caller.client or nil, ...)
end
local function PrintedTo(player)
    local out = {}
    for _, p in ipairs(Printed) do if p.client == (player and player.client) then out[#out + 1] = p.text end end
    return table.concat(out, "\n")
end

local kOn = { Enabled = true }
local kSpanish = "¿Habla español?"
local kTierLine = "We ask for a tier 4 badge (Veteran, Hive skill above 1,400)"

-- ---------------------------------------------------------------------------------------------
-- Tests

-- Defaults: off, written to the config.
Reset()
local config = Files["SSM_SkillRequirement.json"]
check(config and config.Enabled == false and config.MinTier == 4, "config written: off, MinTier 4")
check(config and type(config.AllowedCountries) == "table" and #config.AllowedCountries == 0, "config: empty allowed list")
check(config and config.AllowGroup == "SudAllow", "config: AllowGroup SudAllow")
local low = NewPlayer("Low", kSpectatorIndex, 500)
check(TryJoin(low, kTeam1Index) == true and low.team == kTeam1Index, "off: low tier joins a team")

-- On, no allowed list: below tier 4 is held.
Reset(kOn)
low = NewPlayer("Low", kSpectatorIndex, 500)          -- T2
local vet = NewPlayer("Vet", kSpectatorIndex, 1500)   -- T4
check(SSM.SkillRequirement_StatusOf(low.client) == "restricted", "T2 restricted")
check(SSM.SkillRequirement_StatusOf(vet.client) == "free", "T4 free")
check(TryJoin(vet, kTeam1Index) == true, "T4 joins")
check(TryJoin(low, kTeam1Index) == false and low.team == kSpectatorIndex, "T2 refused a team")
check(Has(low, kSpanish), "first refusal: the Spanish line")
check(not Has(low, kTierLine), "first refusal: no tier line yet")
Clear()
check(TryJoin(low, kTeamReadyRoom) == false and low.team == kSpectatorIndex, "T2 refused the ready room")
check(#TextsTo(low) == 0, "a second try within a second says nothing more")
Now = Now + 1.5
TryJoin(low, kTeam2Index)
check(Has(low, kTierLine), "later refusal: the tier line")
check(Has(low, "guides to help you get there"), "tier line points to the guides")
check(not Has(low, kSpanish), "Spanish line only once")
check(TryJoin(low, kSpectatorIndex) == true, "moving to spectator is never refused")
check(Gamerules:JoinTeam(low, kTeam1Index, true) == true and low.team == kTeam1Index, "forced moves go through")

-- Welcome: once, 5 s after connect, three lines; admins told once.
Reset(kOn)
local admin = NewPlayer("Admin", kTeam1Index, 3000)
Shine.UserData.Users[tostring(admin.client.steamId)] = { Group = "SuperAdmin" }
local allowed = NewPlayer("Allowed", kTeam1Index, 3000)
Shine.UserData.Users[tostring(allowed.client.steamId)] = { Group = "SudAllow" }
low = NewPlayer("Pepe", kSpectatorIndex, 500)
Run(3)
check(not Has(low, "Welcome to NS2 SUD!"), "no welcome before 5 s")
Run(3)
check(Count(low, "Welcome to NS2 SUD!") == 1, "welcome once")
check(Has(low, "NA and EU 10v10 servers") and Has(low, "tutorials and game guides"), "welcome: NA/EU, then the guides")
check(Has(low, "welcome to stay and spectate"), "welcome: stay and spectate")
check(not Has(low, "region") and not Has(low, "country"), "welcome names no region")
check(Has(admin, "Pepe (#3, T2) is restricted. To let them play: sud_allow #3"), "admin told, with the #id and tier")
check(not Has(allowed, "is restricted"), "SudAllow members are not told (not admins)")
Run(20)
check(Count(low, "Welcome to NS2 SUD!") == 1, "welcome not repeated")
check(Count(admin, "is restricted") == 1, "admin told once")

-- Map change: welcome and Spanish line remembered.
TryJoin(low, kTeam1Index)
check(Has(low, kSpanish), "Spanish line before the map change")
local savedFiles = deepcopy(Files)
Notified, Players = {}, {}
nextId = 2   -- Pepe keeps the same Steam ID (1003)
Files = savedFiles
Load()
low = NewPlayer("Pepe", kSpectatorIndex, 500)
Run(10)
check(not Has(low, "Welcome to NS2 SUD!"), "welcome not repeated after a map change")
TryJoin(low, kTeam1Index)
check(Has(low, kTierLine) and not Has(low, kSpanish), "Spanish line not repeated after a map change")

-- Tier formula: rookie T0, adagrad cap.
Reset(kOn)
local rookie = NewPlayer("Rookie", kSpectatorIndex, 2500, { rookie = true })
local capped = NewPlayer("Capped", kSpectatorIndex, 1450, { adagrad = 0.25 })   -- 1450 - 50 = 1400: T3
local over = NewPlayer("Over", kSpectatorIndex, 1460, { adagrad = 0.25 })       -- 1410: T4
check(SSM.SkillRequirement_StatusOf(rookie.client) == "restricted", "rookie (T0) restricted")
check(SSM.SkillRequirement_StatusOf(capped.client) == "restricted", "adagrad cap: 1450 shows T3")
check(SSM.SkillRequirement_StatusOf(over.client) == "free", "adagrad cap: 1460 shows T4")
Files["SSM_SkillRequirement.json"].MinTier = 3
Load()
check(SSM.SkillRequirement_StatusOf(capped.client) == "free", "MinTier 3: T3 plays")
Clear()
TryJoin(rookie, kTeam1Index); Now = Now + 2; TryJoin(rookie, kTeam1Index)
check(Has(rookie, "tier 3 badge (Squad Leader, Hive skill above 750)"), "tier line follows MinTier")

-- Exemptions.
Reset(kOn)
local a = NewPlayer("SudAllowed", kSpectatorIndex, 100)
local b = NewPlayer("Super", kSpectatorIndex, 100)
local c = NewPlayer("Permitted", kSpectatorIndex, 100)
local bot = NewPlayer("Bot", kReadyRoom or kTeamReadyRoom, 0, { virtual = true })
Shine.UserData.Users[tostring(a.client.steamId)] = { Group = "SudAllow" }
Shine.UserData.Users[tostring(b.client.steamId)] = { Group = "SuperAdmin" }
Access[c.client] = { sud_allowed = true }
check(SSM.SkillRequirement_StatusOf(a.client) == "free", "SudAllow member plays")
check(SSM.SkillRequirement_StatusOf(b.client) == "free", "SuperAdmin plays")
check(SSM.SkillRequirement_StatusOf(c.client) == "free", "sud_allowed permission plays")
check(SSM.SkillRequirement_StatusOf(bot.client) == "free", "bots are left alone")

-- Password and Thunderdome.
Reset(kOn)
low = NewPlayer("Low", kSpectatorIndex, 500)
Password = true
check(SSM.SkillRequirement_StatusOf(low.client) == "free", "off while the server has a password")
check(TryJoin(low, kTeam1Index) == true, "passworded: low tier joins")
Password = false
low.team = kSpectatorIndex
Thunderdome = true
check(SSM.SkillRequirement_StatusOf(low.client) == "free", "off on Thunderdome")
Thunderdome = false
check(SSM.SkillRequirement_StatusOf(low.client) == "restricted", "back on without password")

-- Hive skill not loaded.
Reset(kOn)
local loading = NewPlayer("Loading", kSpectatorIndex, -1)
local inRR = NewPlayer("LoadingRR", kTeamReadyRoom, -1)
check(SSM.SkillRequirement_StatusOf(loading.client) == "loading", "-1: loading")
TryJoin(loading, kTeam1Index)
check(Has(loading, "your Hive skill hasn't loaded") and Has(loading, "Please wait a few seconds"), "loading line")
check(not Has(loading, kSpanish), "loading: no Spanish line")
Run(5)
check(inRR.team == kTeamReadyRoom, "loading players in the ready room are not moved")
check(not Has(loading, "Welcome to NS2 SUD!"), "loading: no welcome")
loading.skill = 1600
check(SSM.SkillRequirement_StatusOf(loading.client) == "free", "loaded at T4: free")
loading.skill = -1
Run(60)
check(SSM.SkillRequirement_StatusOf(loading.client) == "failed", "-1 after 60 s: failed")
check(inRR.team == kSpectatorIndex, "never loaded: moved from the ready room to spectator")
Clear()
TryJoin(loading, kTeam1Index)
check(Has(loading, "Your Hive skill didn't load. Reconnect"), "failed line says reconnect")
local exemptLoading = NewPlayer("AdminLoading", kSpectatorIndex, -1)
Shine.UserData.Users[tostring(exemptLoading.client.steamId)] = { Group = "SuperAdmin" }
check(SSM.SkillRequirement_StatusOf(exemptLoading.client) == "free", "exempt players are not held while loading")

-- Restricted players in the ready room go to spectator (map change, shuffles).
Reset(kOn)
local rr = NewPlayer("RR", kTeamReadyRoom, 500)
local rrVet = NewPlayer("RRVet", kTeamReadyRoom, 1500)
Run(2)
check(rr.team == kSpectatorIndex, "restricted player moved from the ready room to spectator")
check(Joins[#Joins].force == true, "that move is forced")
check(rrVet.team == kTeamReadyRoom, "T4 stays in the ready room")
local placed = NewPlayer("Placed", kTeam1Index, 500)
Run(2)
check(placed.team == kTeam1Index, "a restricted player an admin put on a team is left there")

-- Country list.
Reset({ Enabled = true, AllowedCountries = { "xa", "XB" } })
local br = NewPlayer("Inside", kSpectatorIndex, 500, { ip = "200.10.10.10" })
check(SSM.SkillRequirement_StatusOf(br.client) == "checking", "country unknown: checking")
check(#Requests == 1 and Requests[1].url == "http://ip-api.com/json/200.10.10.10?fields=status,countryCode", "one ip-api request, country code only")
SSM.SkillRequirement_StatusOf(br.client)
check(#Requests == 1, "no second request while the first is out")
TryJoin(br, kTeam1Index)
check(Has(br, "still checking your account") and not Has(br, "country"), "checking line names no country")
Bodies.inside = { status = "success", countryCode = "XA" }
Requests[1].callback("inside")
check(SSM.SkillRequirement_StatusOf(br.client) == "free", "allowed country (lower case in config): free")
Now = Now + 2
check(TryJoin(br, kTeam1Index) == true, "allowed country joins")

local us = NewPlayer("Away", kSpectatorIndex, 500, { ip = "8.8.4.4" })
local admin2 = NewPlayer("Admin2", kTeam1Index, 3000)
Shine.UserData.Users[tostring(admin2.client.steamId)] = { Group = "SuperAdmin" }
SSM.SkillRequirement_StatusOf(us.client)
Bodies.away = { status = "success", countryCode = "XC" }
Requests[#Requests].callback("away")
check(SSM.SkillRequirement_StatusOf(us.client) == "restricted", "other country: restricted")
Run(2)
check(Has(admin2, "Away (#2, XC, T2) is restricted"), "admin line names the country")
check(not Has(us, "XC"), "the player is never told the country")

local vetAway = NewPlayer("VetAway", kSpectatorIndex, 1600, { ip = "8.8.8.8" })
local before = #Requests
check(SSM.SkillRequirement_StatusOf(vetAway.client) == "free" and #Requests == before, "T4: no lookup at all")
local exemptAway = NewPlayer("ExemptAway", kSpectatorIndex, 500, { ip = "8.8.8.9" })
Shine.UserData.Users[tostring(exemptAway.client.steamId)] = { Group = "SudAllow" }
check(SSM.SkillRequirement_StatusOf(exemptAway.client) == "free" and #Requests == before, "exempt: no lookup")
local lan = NewPlayer("LAN", kSpectatorIndex, 500, { ip = "192.168.1.5" })
check(SSM.SkillRequirement_StatusOf(lan.client) == "free" and #Requests == before, "private address: free, no lookup")

-- Lookup fails: retried, then let through after 30 s.
local slow = NewPlayer("Slow", kSpectatorIndex, 500, { ip = "9.9.9.9" })
SSM.SkillRequirement_StatusOf(slow.client)
local first = #Requests
Requests[first].callback(nil)
SSM.SkillRequirement_StatusOf(slow.client)
check(#Requests == first, "no retry straight away")
Now = Now + 6
SSM.SkillRequirement_StatusOf(slow.client)
check(#Requests == first + 1, "retried after 5 s")
Requests[#Requests].callback("garbage")
Now = Now + 6
SSM.SkillRequirement_StatusOf(slow.client)
Requests[#Requests].callback(nil)
Now = Now + 6
SSM.SkillRequirement_StatusOf(slow.client)
check(#Requests == first + 2, "three tries at most")
check(SSM.SkillRequirement_StatusOf(slow.client) == "checking", "still held inside 30 s")
Now = Now + 15
check(SSM.SkillRequirement_StatusOf(slow.client) == "free", "unknown after 30 s: let through")

-- SSM.IsAdmin leaves out SudAllow.
Reset(kOn)
local super = NewPlayer("Super", kTeam1Index, 3000)
local member = NewPlayer("Member", kTeam1Index, 3000)
local trusted = NewPlayer("Trusted", kTeam1Index, 3000)
local nobody = NewPlayer("Nobody", kTeam1Index, 3000)
Shine.UserData.Users[tostring(super.client.steamId)] = { Group = "SuperAdmin" }
Shine.UserData.Users[tostring(member.client.steamId)] = { Group = "SudAllow" }
Shine.UserData.Users[tostring(trusted.client.steamId)] = { Group = "TrustedPlayer" }
check(SSM.IsAdmin(nil) == true, "server console is admin")
check(SSM.IsAdmin(super.client) == true, "SuperAdmin is admin")
check(SSM.IsAdmin(trusted.client) == true, "TrustedPlayer is admin (as before)")
check(SSM.IsAdmin(member.client) == false, "SudAllow member is not admin")
check(SSM.IsAdmin(nobody.client) == false, "nobody is not admin")
Hooks.Console_sud_joinpool(member.client, "off")
check(Has(member, "Only admins can switch the SUD Queue."), "SudAllow member cannot use sud_joinpool")

-- sud_allow / sud_disallow.
Reset(kOn)
super = NewPlayer("Super", kTeam1Index, 3000)
Shine.UserData.Users[tostring(super.client.steamId)] = { Group = "SuperAdmin" }
member = NewPlayer("Member", kTeam1Index, 3000)
Shine.UserData.Users[tostring(member.client.steamId)] = { Group = "SudAllow" }
low = NewPlayer("Pepe Low", kSpectatorIndex, 500)
Console("sud_allow", member, "#3")
check(Has(member, "Only admins can use sud_allow"), "SudAllow member refused")
check(Shine.UserData.Users[tostring(low.client.steamId)] == nil, "nothing added")
Console("sud_allow", super)
check(Has(super, "Usage: sud_allow"), "no target: usage")
Console("sud_allow", super, "#99")
check(Has(super, "No player found"), "unknown #id: not found")
Console("sud_allow", super, "#3")
local user = Shine.UserData.Users[tostring(low.client.steamId)]
check(user and user.Group == "SudAllow" and user.Note == "Pepe Low", "#id: added to SudAllow with the name as note")
local group = Shine.UserData.Groups.SudAllow
check(group and group.IsBlacklist == false and group.Immunity == 0, "group created: whitelist, immunity 0")
check(group and #group.Commands == 1 and group.Commands[1] == "sud_allowed", "group grants sud_allowed only")
check(Has(super, "Pepe Low can now play here (added to SudAllow)."), "admin told")
check(PrintedTo(super):find("can now play here", 1, true) ~= nil, "also printed in the admin's console")
check(Has(low, "An admin let you play on this server. Welcome!"), "player told")
check(SSM.SkillRequirement_StatusOf(low.client) == "free", "allowed player now free")
Console("sud_allow", super, "#3")
check(Has(super, "Pepe Low is already in SudAllow."), "already in")
Console("sud_allow", super, "Super")
check(Has(super, "Super is in the Shine group SuperAdmin, so they can already play. Nothing was changed."), "other group: left alone")
check(Shine.UserData.Users[tostring(super.client.steamId)].Group == "SuperAdmin", "SuperAdmin entry unchanged")
Console("sud_allow", super, "555666")
check(Shine.UserData.Users["555666"] and Shine.UserData.Users["555666"].Group == "SudAllow", "offline player by NS2 ID")
Console("sud_allow", super, "STEAM_0:1:100")
check(Shine.UserData.Users["201"] and Shine.UserData.Users["201"].Group == "SudAllow", "offline player by STEAM_0 ID")
Console("sud_allow", super, "pepe", "low")
check(Has(super, "Pepe Low is already in SudAllow."), "name with a space, split by the console")
Console("sud_allow", nil, "#3")
check(Logged[#Logged] == "Pepe Low is already in SudAllow.", "server console can use it (answer in the server log)")

Console("sud_disallow", member, "#3")
check(Has(member, "Only admins can use sud_allow and sud_disallow."), "disallow: member refused")
Console("sud_disallow", super, "#3")
check(Shine.UserData.Users[tostring(low.client.steamId)] == nil, "disallow: removed")
check(Has(super, "Pepe Low was removed from SudAllow."), "disallow: admin told")
check(SSM.SkillRequirement_StatusOf(low.client) == "restricted", "disallowed player held again")
Console("sud_disallow", super, "#3")
check(Has(super, "Pepe Low is not in SudAllow."), "disallow: not in")
Console("sud_disallow", super, "Super")
check(Has(super, "Super is in the Shine group SuperAdmin, not SudAllow. Nothing was changed."), "disallow: other group left alone")
Console("sud_disallow", super)
check(Has(super, "Usage: sud_disallow"), "disallow: usage")

-- Existing group keeps its other settings; the permission is added once.
Reset(kOn)
super = NewPlayer("Super", kTeam1Index, 3000)
Shine.UserData.Users[tostring(super.client.steamId)] = { Group = "SuperAdmin" }
Shine.UserData.Groups.SudAllow = { IsBlacklist = false, Commands = { "sud_allowed" }, Immunity = 0 }
Console("sud_allow", super, "777")
check(#Shine.UserData.Groups.SudAllow.Commands == 1, "existing group: permission not added twice")

-- Spanish players: the messages they pick with !lang.
Reset(kOn)
low = NewPlayer("Bajo", kSpectatorIndex, 500)
SSM.SetLanguage(low.client, "es")
Run(6)
check(Has(low, "Bienvenido a NS2 SUD!"), "welcome in Spanish")
TryJoin(low, kTeam1Index); Now = Now + 2; TryJoin(low, kTeam1Index)
check(Has(low, "Pedimos una insignia de nivel 4 (Veteran, habilidad Hive mayor a 1,400)"), "tier line in Spanish")

-- SUD Queue: held players cannot queue and get no reminder.
Reset({ Enabled = true })
for i = 1, 6 do NewPlayer("M" .. i, kTeam1Index, 1500) end
for i = 1, 6 do NewPlayer("A" .. i, kTeam2Index, 1500) end
low = NewPlayer("LowSpec", kSpectatorIndex, 500)
local okSpec = NewPlayer("VetSpec", kSpectatorIndex, 1600)
ChatHook(low.client, { message = "!joinq" })
check(Has(low, kSpanish), "!joinq: held player gets the Spanish line")
check(not Has(low, "SUD Queue"), "!joinq: not added")
ChatHook(okSpec.client, { message = "!joinq" })
check(Has(okSpec, "SUD Queue"), "!joinq: T4 spectator added as usual")
local spare = NewPlayer("Spare", kSpectatorIndex, 2000)
Clear()
Run(35)
check(Has(spare, "!joinq"), "reminder sent to a spectator who can play")
check(not Has(low, "!joinq"), "no reminder for a held player")

print(string.format("%d passed, %d failed", passes, failures))
if failures > 0 then os.exit(1) end
