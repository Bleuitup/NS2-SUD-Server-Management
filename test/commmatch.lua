-- Logic test for Commander Match, run outside the game against the real mod file:
--   lua test/commmatch.lua        (from the repo root)
--
-- Stubs only the few engine, vanilla and Shine globals the file touches. Proves who is listed,
-- the order, the gaps and when the message is sent; it says nothing about a real server.

-- The shared files every feature needs, in the order SSM/Server.lua loads them.
local kSharedFiles = { "source/lua/SSM/Messages.lua", "source/lua/SSM/Strings.lua", "source/lua/SSM/Commands.lua" }
local kServerFile = "source/lua/SSM/CommMatch/Server.lua"

local failures, passes = 0, 0
local function check(condition, label)
    if condition then
        passes = passes + 1
    else
        failures = failures + 1
        print("FAIL: " .. label)
    end
end

-- ---------------------------------------------------------------------------------------------
-- Stubs

local Now = 0
local Players = {}
local Sent = {}
kGameState = { NotStarted = 1, WarmUp = 2, PreGame = 3, Countdown = 4, Started = 5, Team1Won = 6, Team2Won = 7, Draw = 8 }
local State = kGameState.NotStarted

kTeamReadyRoom, kTeam1Index, kTeam2Index, kSpectatorIndex = 0, 1, 2, 3

Shared = { GetTime = function() return Now end, Message = function(text) print("server: " .. text) end }
Server = {
    GetOwner = function(player) return player.client end,
    ForAllPlayers = function(fn) for _, p in ipairs(Players) do fn(p) end end
}
function GetGamerules() return { GetGameState = function() return State end } end
local Files = {}
function LoadConfigFile(name, default)
    if Files[name] then return Files[name] end
    if default then Files[name] = default end
    return default
end
function SaveConfigFile(name, data) Files[name] = data end
Event = { Hook = function() end }

Shine = {
    NotifyDualColour = function(_, target, _, _, _, prefix, _, _, _, text)
        Sent[#Sent + 1] = { target = target, prefix = prefix, text = text }
    end
}

-- The chair: LoginPlayer turns the player into a commander and returns it, like the game.
CommandStructure = {
    LoginPlayer = function(_, player)
        player.commander = true
        return player
    end
}
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    _G[className][methodName] = method
    return original
end

local function AddPlayer(name, team, commSkill, offset, isBot)
    local player = { name = name, team = team, commSkill = commSkill, offset = offset or 0 }
    local steamId = #Players + 1000
    player.client = { GetIsVirtual = function() return isBot == true end, GetUserId = function() return steamId end }
    player.GetTeamNumber = function(self) return self.team end
    player.GetName = function(self) return self.name end
    player.isa = function(self, class) return class == "Commander" and self.commander == true end
    player.GetCommanderSkill = function(self) return self.commSkill end
    player.GetCommanderSkillOffset = function(self) return self.offset end
    player.client.GetControllingPlayer = function() return player end
    Players[#Players + 1] = player
    return player
end

local function Login(player, forced)
    return CommandStructure.LoginPlayer({}, player, forced)
end

local function Texts()
    local t = {}
    for i, m in ipairs(Sent) do t[i] = m.text end
    return t
end

for _, file in ipairs(kSharedFiles) do dofile(file) end
dofile(kServerFile)

-- ---------------------------------------------------------------------------------------------
-- Who is listed and how

-- Bleu: commander skill 2000, offset +100 -> marine 2100, alien 1900.
local Bleu = AddPlayer("Bleu", kTeam1Index, 2000, 100)
-- Alien commander skills (skill - offset):
AddPlayer("Pepe", kTeam2Index, 2150, 40)        -- 2110 -> +10
AddPlayer("LZZ", kTeam1Index, 2000, -65)        -- 2065 -> -35, same team as Bleu, still listed
AddPlayer("Ana", kSpectatorIndex, 2200, 120)    -- 2080 -> -20, spectators listed
AddPlayer("Juan", kTeamReadyRoom, 1700, -400)   -- 2100 -> 0
AddPlayer("Leo", kTeam2Index, 2500, 0)          -- 2500 -> +400
AddPlayer("Max", kTeam2Index, 1500, 0)          -- 1500 -> -600, 6th, left off
AddPlayer("Newbie", kTeam2Index, 0, 0)          -- never commanded, left out
AddPlayer("Bot", kTeam2Index, 2100, 0, true)    -- bot, left out

local returned = Login(Bleu)
check(returned == Bleu, "the login still returns the commander")

local t = Texts()
check(#t == 6, "header plus 5 rows (got " .. #t .. ")")
check(t[1] == "Bleu took Marine commander. Closest alien commanders:", "header: " .. tostring(t[1]))
check(t[2] == "1. Juan  +0", "closest first, zero gap: " .. tostring(t[2]))
check(t[3] == "2. Pepe  +10", "plus sign when above: " .. tostring(t[3]))
check(t[4] == "3. Ana  -20", "spectator listed, minus when below: " .. tostring(t[4]))
check(t[5] == "4. LZZ  -35", "same-team player listed: " .. tostring(t[5]))
check(t[6] == "5. Leo  +400", "fifth: " .. tostring(t[6]))
check(Sent[1].target == nil, "sent to everyone")
check(Sent[1].prefix == "[NS2 SUD]" and Sent[2].prefix == "", "tag on the header only")
for _, text in ipairs(t) do
    check(not text:find("Newbie") and not text:find("Bot") and not text:find("Max"), "left out: " .. text)
end

-- ---------------------------------------------------------------------------------------------
-- When it is sent

-- Cooldown, per player: Bleu hops out and back into the Marine chair 20 s later.
local LZZ = Players[3]
Bleu.commander = false
Sent = {}
Now = 20
Login(Bleu)
check(#Sent == 0, "same player, same side, within 30 seconds: nothing")

-- Another player taking the chair is not held back by Bleu's cooldown.
Bleu.commander = false
Now = 25
Login(LZZ)
check(#Sent == 6 and Sent[1].text:find("^LZZ took Marine") ~= nil, "another player gets the list right away")
LZZ.commander = false

-- Bleu switching side skips the cooldown, both ways.
Sent = {}
Now = 26
Bleu.team = kTeam2Index
Login(Bleu)
check(#Sent == 6 and Sent[1].text:find("^Bleu took Alien") ~= nil, "Marine to Alien: no cooldown")
Bleu.commander = false
Sent = {}
Now = 40
Bleu.team = kTeam1Index
Login(Bleu)
check(#Sent == 6 and Sent[1].text:find("^Bleu took Marine") ~= nil, "Alien back to Marine: no cooldown")

-- Same side again: held back until 30 s have passed since that player's last list.
Bleu.commander = false
Sent = {}
Now = 69
Login(Bleu)
check(#Sent == 0, "29 seconds later: nothing")
Bleu.commander = false
Now = 70
Login(Bleu)
check(#Sent == 6, "30 seconds later: again")

-- Other team already has a commander: the alien who logs in gets no message.
Sent = {}
Now = 200
local Pepe = Players[2]
Login(Pepe)
check(#Sent == 0, "nothing when the other chair is taken")

-- Alien side, once the marine chair is empty again: compares with marine commander skill.
Bleu.commander = false
Pepe.commander = false
Now = 300
Login(Pepe) -- Pepe alien 2110; Bleu marine 2100 -> -10
t = Texts()
check(t[1] == "Pepe took Alien commander. Closest marine commanders:", "alien header: " .. tostring(t[1]))
check(t[2] == "1. Bleu  -10", "uses others' marine skill: " .. tostring(t[2]))

-- Only in pregame: never during the countdown or once the round has started.
for _, state in ipairs({ "Countdown", "Started", "Team1Won", "Draw" }) do
    Pepe.commander = false
    Sent = {}
    Now = Now + 100
    State = kGameState[state]
    Login(Pepe)
    check(#Sent == 0, "nothing in state " .. state)
end

-- Round start: the game resets the map and logs the commanders back in, forced, while the
-- state is still PreGame and the other chair is briefly empty. That must not post (bug in 1.1).
for _, state in ipairs({ "PreGame", "WarmUp" }) do
    Pepe.commander = false
    Bleu.commander = false
    Sent = {}
    Now = Now + 100
    State = kGameState[state]
    Login(Pepe, true)
    check(#Sent == 0, "forced re-login posts nothing in " .. state)
end

-- An ordinary login in PreGame and WarmUp still posts.
for _, state in ipairs({ "PreGame", "WarmUp" }) do
    Pepe.commander = false
    Bleu.commander = false
    Sent = {}
    Now = Now + 100
    State = kGameState[state]
    Login(Pepe)
    check(#Sent == 6, "ordinary login posts in " .. state)
end
Pepe.commander = false
State = kGameState.NotStarted
Now = 400

-- A commander who has never commanded: nothing to compare.
local Newbie = Players[8]
Pepe.commander = false
Sent = {}
Now = 500
Login(Newbie)
check(#Sent == 0, "nothing for a commander at 0")
Newbie.commander = false

-- A bot commander: nothing.
local Bot = Players[9]
Sent = {}
Now = 600
Login(Bot)
check(#Sent == 0, "nothing for a bot commander")
Bot.commander = false

-- Without Shine nothing is sent and nothing breaks.
local savedShine = Shine
Shine = nil
Now = 700
check(Login(Bleu) == Bleu, "works without Shine")
Shine = savedShine
Bleu.commander = false

-- An error inside the feature never breaks the login.
local brokenGetName = Bleu.GetName
Bleu.GetName = function() error("boom") end
Now = 800
Sent = {}
check(Login(Bleu) == Bleu, "login survives an error in the feature")
Bleu.GetName = brokenGetName

-- ---------------------------------------------------------------------------------------------
-- Ignored players

check(type(Files["SSM_CommMatch.json"]) == "table" and #Files["SSM_CommMatch.json"].IgnoredPlayers == 0,
    "settings file written with an empty ignore list")

-- Ignore Juan (as a number) and Pepe (as text), then load the map again.
Files["SSM_CommMatch.json"] = { IgnoredPlayers = { 1004, "1001" } }
CommandStructure.LoginPlayer = function(_, player) player.commander = true return player end
dofile(kServerFile)
for _, p in ipairs(Players) do p.commander = false end
Bleu.team = kTeam1Index
State = kGameState.PreGame
Sent = {}
Now = 900
Login(Bleu)
t = Texts()
check(#t == 5 and t[2] == "1. Ana  -20" and t[3] == "2. LZZ  -35" and t[4] == "3. Leo  +400" and t[5] == "4. Max  -600",
    "ignored players are not listed, got:\n" .. table.concat(t, "\n"))
check(not table.concat(t, "\n"):find("Juan") and not table.concat(t, "\n"):find("Pepe"), "Juan and Pepe left out")

-- An ignored player taking a chair still gets a list, compared with everyone else.
Bleu.commander = false
Sent = {}
Now = 1000
Login(Pepe)
check(#Sent > 0 and Sent[1].text:find("^Pepe took Alien") ~= nil and not Texts()[2]:find("Pepe"), "an ignored commander still gets a list")

-- Thunderdome: off unless EnabledOnThunderdome is true.
check(Files["SSM_CommMatch.json"].EnabledOnThunderdome == nil or Files["SSM_CommMatch.json"].EnabledOnThunderdome == false,
    "EnabledOnThunderdome is off unless set")
Shared.GetThunderdomeEnabled = function() return true end
Files["SSM_CommMatch.json"] = { IgnoredPlayers = {} }
dofile(kServerFile)
check(Files["SSM_CommMatch.json"].EnabledOnThunderdome == false, "the setting is written, off")
for _, p in ipairs(Players) do p.commander = false end
Bleu.team = kTeam1Index
Sent = {}
Now = 2000
Login(Bleu)
check(#Sent == 0, "Thunderdome: no list")

Files["SSM_CommMatch.json"] = { IgnoredPlayers = {}, EnabledOnThunderdome = true }
dofile(kServerFile)
for _, p in ipairs(Players) do p.commander = false end
Sent = {}
Now = 3000
Login(Bleu)
check(#Sent > 0 and Sent[1].text:find("^Bleu took Marine") ~= nil, "Thunderdome with EnabledOnThunderdome: the list goes out")
Shared.GetThunderdomeEnabled = nil



-- ---------------------------------------------------------------------------------------------
-- !mycomm and !comm (v1.5)

-- Load the chat router again with hooks that can be called, then the feature on top of it.
local chatHooks, sayHook = {}, nil
Event.Hook = function(name, fn) chatHooks[name] = fn end
Shine.Hook = { Add = function(_, _, fn) sayHook = fn end }

-- A map load with these settings: the router, the feature, then the first server update.
local function LoadWith(settings)
    Files["SSM_CommMatch.json"] = settings
    dofile("source/lua/SSM/Commands.lua")
    dofile(kServerFile)
    chatHooks.UpdateServer()
end
LoadWith({ IgnoredPlayers = {}, EnabledOnThunderdome = false })
for _, p in ipairs(Players) do p.commander = false end
Bleu.team = kTeam1Index
local Ana, Juan = Players[4], Players[5]

local function Say(player, text)
    Sent = {}
    return sayHook(player.client, { message = text })
end

local function SentTo(player)
    for _, m in ipairs(Sent) do
        if m.target ~= player.client then return false end
    end
    return #Sent > 0
end

-- From spectator: both chairs. Ana: marine 2320, alien 2080.
check(Say(Ana, "!mycomm") == "", "the typed command is not shown in chat")
t = Texts()
check(#t == 12, "spectator: two headers and 5 rows each (got " .. #t .. ")")
check(t[1] == "If you command Marines, closest alien commanders:", "marine header: " .. tostring(t[1]))
check(t[2] == "1. Leo  +180" and t[3] == "2. Pepe  -210" and t[4] == "3. Juan  -220" and t[5] == "4. LZZ  -255"
    and t[6] == "5. Bleu  -420", "marine rows, got:\n" .. table.concat(t, "\n", 2, 6))
check(t[7] == "If you command Aliens, closest marine commanders:", "alien header: " .. tostring(t[7]))
check(t[8] == "1. Bleu  +20" and t[9] == "2. Pepe  +110" and t[10] == "3. LZZ  -145" and t[11] == "4. Leo  +420"
    and t[12] == "5. Max  -580", "alien rows, got:\n" .. table.concat(t, "\n", 8, 12))
check(SentTo(Ana), "only the caller sees it")
check(Sent[1].prefix == "[NS2 SUD]" and Sent[2].prefix == "" and Sent[7].prefix == "[NS2 SUD]", "tag on the headers only")

-- From the ready room: both chairs too. With / as well.
Say(Juan, "/mycomm")
check(#Sent == 12 and SentTo(Juan), "ready room with /: both chairs")

-- On a team: that team's chair only, the same rows the chair would post. Works mid-round.
State = kGameState.Started
Say(Bleu, "!MyComm")
t = Texts()
check(#t == 6 and t[1] == "If you command Marines, closest alien commanders:" and t[2] == "1. Juan  +0"
    and t[3] == "2. Pepe  +10" and t[6] == "5. Leo  +400", "marine player, mid-round:\n" .. table.concat(t, "\n"))
local Pepe2 = Players[2]
Say(Pepe2, "!mycomm")
check(#Sent == 6 and Sent[1].text == "If you command Aliens, closest marine commanders:", "alien player: alien chair only")

-- Never commanded.
local Newbie2 = Players[8]
Say(Newbie2, "!mycomm")
check(#Sent == 1 and Sent[1].text == "You have never commanded, so there is nothing to compare.", "never commanded: " .. tostring(Sent[1] and Sent[1].text))

-- Nobody else has commanded.
local everyone = Players
Players = { Bleu, Newbie2 }
Say(Bleu, "!mycomm")
check(#Sent == 1 and Sent[1].text == "Nobody else on the server has commanded yet.", "nobody to list: " .. tostring(Sent[1] and Sent[1].text))
Players = everyone

-- !comm: no chair taken.
Say(Ana, "!comm")
check(#Sent == 1 and Sent[1].text == "Nobody is in a command chair.", "no commander: " .. tostring(Sent[1] and Sent[1].text))

-- One chair taken: that commander's list, to the caller only. The caller can be on it.
Bleu.commander = true
Say(Ana, "!comm")
t = Texts()
check(#t == 6 and t[1] == "Bleu is Marine commander. Closest alien commanders:" and t[2] == "1. Juan  +0"
    and t[4] == "3. Ana  -20", "one commander:\n" .. table.concat(t, "\n"))
check(SentTo(Ana), "!comm: only the caller sees it")

-- The commander can ask too.
Say(Bleu, "!comm")
check(#Sent == 6 and Sent[1].text:find("^Bleu is Marine") ~= nil, "the commander asking for their own list")

-- Both chairs taken: no list.
Pepe2.commander = true
Say(Ana, "!comm")
check(#Sent == 1 and Sent[1].text == "Both command chairs are taken, so there is no list.", "both chairs: " .. tostring(Sent[1] and Sent[1].text))

-- Alien chair only.
Bleu.commander = false
Say(Ana, "!comm")
check(#Sent == 6 and Sent[1].text == "Pepe is Alien commander. Closest marine commanders:" and Sent[2].text == "1. Bleu  -10",
    "alien commander: " .. tostring(Sent[1] and Sent[1].text))
Pepe2.commander = false

-- A commander who never commanded, and a bot in the chair.
Newbie2.commander = true
Say(Ana, "!comm")
check(#Sent == 1 and Sent[1].text == "Newbie has never commanded, so there is nothing to compare.", "never-commanded commander: " .. tostring(Sent[1] and Sent[1].text))
Newbie2.commander = false
local Bot2 = Players[9]
Bot2.commander = true
Say(Ana, "!comm")
check(#Sent == 1 and Sent[1].text:find("^Bot has never commanded") ~= nil, "bot commander: no list")
Bot2.commander = false

-- In the caller's language.
SSM.SetLanguage(Ana.client, "es")
Say(Ana, "!mycomm")
check(Sent[1].text == "Si comanda Marines, los comandantes alien más cercanos:" and Sent[2].text == "1. Leo  +180", "Spanish: " .. tostring(Sent[1].text))
Say(Ana, "!comm")
check(Sent[1].text == "No hay nadie en una silla de comandante.", "Spanish !comm: " .. tostring(Sent[1].text))
SSM.SetLanguage(Ana.client, "en")

-- Ignored players still get their own list, and are left off everyone else's.
LoadWith({ IgnoredPlayers = { 1003 }, EnabledOnThunderdome = false })
Say(Ana, "!mycomm")
check(#Sent == 12, "an ignored player gets their own list")
Say(Bleu, "!mycomm")
check(not table.concat(Texts(), "\n"):find("Ana"), "an ignored player is not on anyone else's list")

-- Thunderdome: off unless EnabledOnThunderdome.
LoadWith({ IgnoredPlayers = {}, EnabledOnThunderdome = false })
Shared.GetThunderdomeEnabled = function() return true end
Say(Ana, "!mycomm")
check(#Sent == 1 and Sent[1].text == "Commander match is off on Thunderdome games.", "Thunderdome: !mycomm off")
Say(Ana, "!comm")
check(#Sent == 1 and Sent[1].text == "Commander match is off on Thunderdome games.", "Thunderdome: !comm off")
LoadWith({ IgnoredPlayers = {}, EnabledOnThunderdome = true })
Say(Ana, "!mycomm")
check(#Sent == 12, "Thunderdome with EnabledOnThunderdome: !mycomm works")
Shared.GetThunderdomeEnabled = nil
State = kGameState.NotStarted

-- Listed in !help.
local help = table.concat(SSM_GetCommandLines("en"), "\n")
check(help:find("!mycomm", 1, true) ~= nil and help:find("!comm ", 1, true) ~= nil, "!help lists both:\n" .. help)
print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
