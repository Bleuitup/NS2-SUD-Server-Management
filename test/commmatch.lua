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
function LoadConfigFile() return nil end
function SaveConfigFile() end
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

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
