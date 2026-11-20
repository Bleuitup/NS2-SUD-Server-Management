-- Logic test for the pause's server part, run outside the game against the real mod files:
--   lua test/pause.lua        (from the repo root)
--
-- Stubs only the few engine, vanilla and Shine globals the files touch. Proves when pausing is
-- allowed (Thunderdome, password, the map-change memory), the round-start line, the pause and
-- resume flow with its chat lines, the per-team limit, and the chat fallback without Shine. It
-- says nothing about the frozen world itself (Pause/Shared.lua and the entity blocks), which only
-- a real server shows.

local kSharedFiles = { "source/lua/SSM/Messages.lua", "source/lua/SSM/Strings.lua", "source/lua/SSM/Commands.lua" }
local kServerFile = "source/lua/SSM/Pause/Server.lua"
local kStateFile = "SSM_PauseState.json"
local kSettingsFile = "SSM_Pause.json"

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
local Sent = {}          -- { client = client or nil (everyone), text }
local Plain = {}         -- game chat without Shine: { target, text }
local Thunderdome = false
local EnginePassword = ""

kTeamReadyRoom, kTeam1Index, kTeam2Index, kSpectatorIndex = 0, 1, 2, 3
kNeutralTeamType = 0
kGameState = { NotStarted = 1, WarmUp = 2, PreGame = 3, Countdown = 4, Started = 5, Team1Won = 6, Team2Won = 7, Draw = 8 }

function LoadConfigFile(name, default)
    if Files[name] then return deepcopy(Files[name]) end
    return default and deepcopy(default) or nil
end
function SaveConfigFile(name, data) Files[name] = deepcopy(data) end
function StringTrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function ientitylist(list) return ipairs(list) end
function ServerAdminPrint(client, text) end

Shared = {
    GetTime = function() return Now end,
    GetSystemTime = function() return SystemStart + math.floor(Now) end,
    GetThunderdomeEnabled = function() return Thunderdome end,
    GetEntitiesWithClassname = function() return {} end,
    Message = function(text) end
}
Event = { Hook = function(name, fn)
    local previous = Hooks[name]
    Hooks[name] = previous and function(...) previous(...) return fn(...) end or fn
end }
function Class_ReplaceMethod(className, methodName, method)
    local original = _G[className][methodName]
    assert(original ~= nil)
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

local ShineStub = {
    NotifyDualColour = function(_, client, _, _, _, prefix, _, _, _, text)
        Sent[#Sent + 1] = { client = client, prefix = prefix, text = text }
    end
}

local function NewPlayer(steamId, name, team)
    local client = { steamId = steamId }
    local player = { client = client, name = name, team = team }
    client.GetUserId = function() return steamId end
    client.GetIsVirtual = function() return false end
    client.GetControllingPlayer = function() return player end
    player.GetName = function() return name end
    player.GetTeamNumber = function(p) return p.team end
    return player
end

local Gamerules

local function LoadServer()
    Hooks = {}
    SSM = nil
    Shine = ShineStub
    Server = {
        SetPassword = function(password) EnginePassword = password end,
        GetOwner = function(player) return player.client end,
        ForAllPlayers = function() end
    }
    NS2Gamerules = {
        GetGameState = function(self) return self.state end,
        SetGameState = function(self, state) self.state = state end,
        ResetGame = function(self) self.resets = (self.resets or 0) + 1 end,
        GetGameStarted = function(self) return self.state == kGameState.Started end
    }
    Gamerules = setmetatable({ state = kGameState.NotStarted }, { __index = NS2Gamerules })
    GetGamerules = function() return Gamerules end
    ProcessSayCommand = function() end
    for _, file in ipairs(kSharedFiles) do dofile(file) end
    dofile(kServerFile)
end

local function Run(seconds)
    local stop = Now + seconds
    while Now < stop do
        Now = Now + 0.25
        Hooks.UpdateServer(0.25)
    end
end

local function Say(player, text)
    ProcessSayCommand(player, text)
end

local function Texts(client)
    local out = {}
    for _, line in ipairs(Sent) do
        if line.client == client then out[#out + 1] = line.text end
    end
    return out
end

local function Has(list, text)
    for _, line in ipairs(list) do
        if line == text then return true end
    end
    return false
end

local function StartRound()
    Gamerules:SetGameState(kGameState.Started)
end

-- ---------------------------------------------------------------------------------------------
-- A pub: no Thunderdome, no password

LoadServer()
Run(1)
local ana = NewPlayer(101, "Ana", kTeam1Index)
local leo = NewPlayer(102, "Leo", kTeam2Index)

check(SSMPause_GetAllowedReason() == nil, "a pub without a password does not allow pausing")
StartRound()
check(#Sent == 0, "no round-start line on a pub")
Say(ana, "pause")
Run(6)
check(#Sent == 0 and not SSMPause_GetIsGamePaused(), "plain 'pause' on a pub does nothing, says nothing")
Say(ana, "!pause")
check(#Sent == 1 and Sent[1].client == ana.client
    and Sent[1].text == "Pausing is only available on Thunderdome and passworded games.",
    "!pause on a pub answers privately")
check(SSMPause_TriggerDisconnectPause("Ana", kTeam1Index) == false, "no pause on disconnect on a pub")

-- ---------------------------------------------------------------------------------------------
-- A password set during the map

Sent = {}
Gamerules:ResetGame()
Gamerules.state = kGameState.PreGame
Server.SetPassword("scrim")
check(EnginePassword == "scrim", "the password still reaches the engine")
check(SSMPause_GetAllowedReason() == "password", "a password allows pausing")
check(Files[kStateFile] and Files[kStateFile].HasPassword == true, "the password state is saved")
StartRound()
check(#Sent == 1 and Sent[1].client == nil and Sent[1].text == "PASSWORDED GAME DETECTED: PAUSE ENABLED",
    "round start tells everyone the pause is on")

-- The pause itself.
Sent = {}
Say(ana, "pause")
check(Has(Texts(nil), "Ana has paused the game."), "pause in chat starts the countdown")
check(not SSMPause_GetIsGamePaused() and SSMPause_GetIsGamePausing(), "counting down, not paused yet")
Run(5.5)
check(SSMPause_GetIsGamePaused(), "paused after the countdown")
check(Has(Texts(nil), "Game will pause in 4 seconds.") and Has(Texts(nil), "Game will pause in 1 second.")
    and Has(Texts(nil), "Game paused."), "countdown and paused lines")

Sent = {}
Say(ana, "unpause")
check(Has(Texts(nil), "Ana readied for the Marines, waiting for the Aliens."), "one team ready")
Say(leo, "!resume")
check(Has(Texts(nil), "Leo readied for the Aliens, resuming game."), "both teams ready")
Run(6)
check(not SSMPause_GetIsGamePaused(), "resumed after the resume countdown")
check(Has(Texts(nil), "Game resumed. Marines have 3 pauses remaining."), "resume line with pauses left")

-- 4 pauses per team per round.
for _ = 1, 3 do
    Hooks.Console_gpause(ana.client)
    Run(5.5)
    Hooks.Console_unpause(ana.client)
    Hooks.Console_unpause(leo.client)
    Run(6)
end
Sent = {}
Hooks.Console_gpause(ana.client)
check(not SSMPause_GetIsGamePausing() and Texts(ana.client)[1] == "Your team is out of pauses.",
    "a fifth pause is refused, privately")
Gamerules:ResetGame()
StartRound()
Hooks.Console_gpause(ana.client)
check(SSMPause_GetIsGamePausing(), "counts are full again after a round reset")
Run(5.5)
Gamerules:ResetGame()
check(not SSMPause_GetIsGamePaused(), "a round reset clears a running pause")

-- Pause on disconnect.
StartRound()
Sent = {}
check(SSMPause_TriggerDisconnectPause("Ana", kTeam1Index) == true, "a disconnect pauses where allowed")
check(Has(Texts(nil), "Ana disconnected, pausing the game."), "disconnect pause line")
Run(1.5)
check(SSMPause_GetIsGamePaused(), "paused one second after the disconnect")
Gamerules:ResetGame()

-- ---------------------------------------------------------------------------------------------
-- Map change and restart

Now = Now + 20
LoadServer()
check(SSMPause_GetAllowedReason() == "password", "the password is remembered across a map change")

Now = Now + 600
LoadServer()
check(SSMPause_GetAllowedReason() == nil, "an old save is not trusted (server restarted)")

Server.SetPassword("again")
Server.SetPassword("")
check(SSMPause_GetAllowedReason() == nil, "removing the password stops pausing")

-- ---------------------------------------------------------------------------------------------
-- Thunderdome, the off switch, and no Shine

Thunderdome = true
check(SSMPause_GetAllowedReason() == "thunderdome", "Thunderdome allows pausing")
Sent = {}
Gamerules.state = kGameState.PreGame
StartRound()
check(Sent[1] and Sent[1].text == "THUNDERDOME DETECTED: PAUSE ENABLED", "Thunderdome round-start line")

-- Without Shine the lines still go out, as game chat.
Gamerules:ResetGame()
Shine = nil
Server.SendNetworkMessage = function(a, b, c)
    if type(a) == "string" then
        Plain[#Plain + 1] = { target = nil, message = b }
    else
        Plain[#Plain + 1] = { target = a, message = c }
    end
end
BuildChatMessage = function(teamOnly, name, location, team, teamType, text) return { name = name, text = text } end
Gamerules.state = kGameState.PreGame
StartRound()
check(Plain[1] and Plain[1].target == nil and Plain[1].message.name == "[NS2 SUD]"
    and Plain[1].message.text == "THUNDERDOME DETECTED: PAUSE ENABLED", "without Shine: game chat to everyone")
Thunderdome = false
Say(ana, "!pause")
check(Plain[2] and Plain[2].target == ana and Plain[2].message.text:find("^Pausing is only available"),
    "without Shine: game chat to one player")
Server.SendNetworkMessage, BuildChatMessage = nil, nil

Thunderdome = true
Files[kSettingsFile] = { PauseEnabled = false }
LoadServer()
check(SSMPause_GetAllowedReason() == nil, "PauseEnabled false turns it off, Thunderdome too")
Thunderdome = false

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
