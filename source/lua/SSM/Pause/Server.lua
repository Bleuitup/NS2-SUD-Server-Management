-- NS2 SUD pause, server part.
--
-- Ported from Dragon's NSL Mod (lua/NSL/pause/server.lua, https://github.com/xToken/NSL), first
-- for Blast to the Past, then moved here (author, 2026-11-20). What is SSM's own: when pausing is
-- allowed, the settings file, the [NS2 SUD] chat voice instead of NSL's message system, chat and
-- console commands without NSL's command registry, pause counts that reset every round, and a
-- server log line for every pause and resume. NSL's referee commands are left out.
--
-- When (author, 2026-11-20): only on Thunderdome, or when the server has a password. A password
-- is seen when it is set with sv_password, Shine's sh_password or !password, which all go through
-- Server.SetPassword; the mod remembers it across map changes. A password from the server's launch
-- settings cannot be seen from Lua. At round start everyone gets one line saying the pause is on.
-- The pause machinery (Pause/Shared.lua and the blocks below) is installed on every server and
-- does nothing unless the game is paused.
--
-- Players: type pause (or !pause) in chat, or gpause in the console, during a round. After a
-- countdown the game freezes. To resume, someone on EACH team types unpause (or !unpause, resume,
-- !resume); typing it again un-readies your team. The game resumes on its own after AutoResumeAfter
-- seconds. Each team has PausesPerTeam pauses per round. Pause on disconnect is triggered from
-- SavedPlayers/Server.lua.
--
-- Chat goes out with `always`, so it reaches players without Shine too (Thunderdome servers).
-- Messages to everyone are in English; private ones in the player's language.

-- Settings ------------------------------------------------------------------------------------

local kSettingsFile = "SSM_Pause.json"
local kDefaultSettings =
{
    PauseEnabled = true,         -- false turns the pause off everywhere (and pause on disconnect)
    PausesPerTeam = 4,           -- per team, per round
    PauseCountdown = 5,          -- seconds between pause and the game freezing
    ResumeCountdown = 5,         -- seconds between both teams being ready and the game resuming
    AutoResumeAfter = 300,       -- seconds paused before the game resumes on its own; 0 = never
    ReadyReminderInterval = 30,  -- seconds between reminders of who still has to ready up
    PauseOnDisconnect = true,    -- pause when a team player disconnects (uses one of their team's pauses)
}

local settings = LoadConfigFile(kSettingsFile, kDefaultSettings, true)
if type(settings) ~= "table" then
    settings = {}
end

local function Setting(name)
    local value = settings[name]
    if type(value) ~= type(kDefaultSettings[name]) then
        return kDefaultSettings[name]
    end
    return value
end

-- A countdown of 0 would mean "no countdown running", so never go below 1 second.
local function Countdown(name)
    return math.max(1, math.floor(Setting(name)))
end

local function Log(text)
    Shared.Message("[NS2 SUD] pause: " .. text)
end

local function SayAll(text)
    SSM.NotifyAll(text, false, true)
end

local function SayTo(client, key, ...)
    SSM.Notify(client, SSM.Text(SSM.LanguageOf(client), key, ...), false, true)
end

-- When pausing is allowed -------------------------------------------------------------------

-- The password state, kept across map changes: the server Lua starts over on every map, the
-- engine keeps the password. A save older than kPasswordStateMaxAge is not trusted (the server was
-- restarted, which drops a password set with sv_password).
local kPasswordStateFile = "SSM_PauseState.json"
local kPasswordStateMaxAge = 120
local kPasswordStateSaveSeconds = 5

local hasPassword = false
do
    local state = LoadConfigFile(kPasswordStateFile)
    if type(state) == "table" and type(state.SavedAt) == "number"
    and Shared.GetSystemTime() - state.SavedAt <= kPasswordStateMaxAge then
        hasPassword = state.HasPassword == true
    end
end

local lastPasswordSave = -math.huge
local function SavePasswordState()
    lastPasswordSave = Shared.GetTime(true)
    SaveConfigFile(kPasswordStateFile, { SavedAt = Shared.GetSystemTime(), HasPassword = hasPassword })
end

local oldSetPassword = Server.SetPassword
if oldSetPassword then
    function Server.SetPassword(password, ...)
        oldSetPassword(password, ...)
        local now = type(password) == "string" and password ~= ""
        if now ~= hasPassword then
            hasPassword = now
            Log(now and "server password set" or "server password removed")
        end
        SavePasswordState()
    end
end

local function GetIsThunderdome()
    return Shared.GetThunderdomeEnabled ~= nil and Shared.GetThunderdomeEnabled() == true
end

-- "thunderdome", "password", or nil when pausing is not allowed right now.
function SSMPause_GetAllowedReason()
    if not Setting("PauseEnabled") then
        return nil
    end
    if GetIsThunderdome() then
        return "thunderdome"
    end
    if hasPassword then
        return "password"
    end
    return nil
end

local kAnnouncements =
{
    thunderdome = "THUNDERDOME DETECTED: PAUSE ENABLED",
    password = "PASSWORDED GAME DETECTED: PAUSE ENABLED"
}

-- Pause state -------------------------------------------------------------------------------

local gamestate =
{
    serverpauseloopenabled = false,
    serverprepauseloopenabled = false,
    gamepaused = false,
    gamepausedtime = 0,
    gamepausedcountdown = 0,
    gamepausedmessagetime = 0,
    gamepausingteam = 0,
    teampauses = { },
    team1resume = false,
    team1lastresume = 0,
    team2resume = false,
    team2lastresume = 0,
    gamepauseddelta = 0,
    gameprepausedelta = 0
}

gSharedGetTimeAdjustments = gSharedGetTimeAdjustments or 0

function SSMPause_GetIsGamePaused()
    return gamestate.gamepaused
end

function SSMPause_GetIsGamePausing()
    return gamestate.gamepausedcountdown ~= 0
end

function SSMPause_GetPausedTime()
    return gamestate.gamepausedtime
end

local kTeamNames = { [1] = "Marines", [2] = "Aliens" }

local function TeamName(teamNumber)
    return kTeamNames[teamNumber] or ("Team " .. tostring(teamNumber))
end

local function ValidateTeamNumber(teamnum)
    return teamnum == 1 or teamnum == 2
end

-- Freezing the world (NSL) -------------------------------------------------------------------

-- Classes whose entities keep updating normally; everything else stops updating while paused.
local UpdatingClasses =
{
    "ScriptActor", "Clog", "DeathTrigger", "Gamerules", "ObjectiveInfo", "ParticleEffect", "Pheromone",
    "PredictedProjectile", "Ragdoll", "SoundEffect", "SpawnBlocker", "SporeCloud", "TeamInfo", "TeamJoin",
    "TimedEmitter", "Tunnel", "TunnelProp", "ViewModel", "Web"
}

local AllowedCallbackClassNames = { "PlayerInfoEntity" }

-- Mixins whose OnProcessMove stops while paused. Names that do not exist in this build (or have no
-- OnProcessMove) are skipped by SSMPause_ReplaceMethod.
local kProcessMoveBlocked =
{
    "CatalystMixin", "CloakableMixin", "ClogFallMixin", "CombatMixin", "ConstructMixin", "CorrodeMixin",
    "EffectsMixin", "EnergizeMixin", "EnergyMixin", "FireMixin", "FlinchMixin", "GhostStructureMixin",
    "IdleMixin", "LOSMixin", "MaturityMixin", "NanoShieldMixin", "OrdersMixin", "ParasiteMixin",
    "PredictedProjectileShooterMixin", "RagdollMixin", "RecycleMixin", "ResearchMixin", "StompMixin",
    "StormCloudMixin", "StunMixin", "TargettingMixin", "TechMixin", "TeleportMixin", "TunnelUserMixin",
    "UmbraMixin", "VortexAbleMixin"
}

for _, name in ipairs(kProcessMoveBlocked) do
    local original
    original = SSMPause_ReplaceMethod(name, "OnProcessMove",
        function(self, input)
            if SSMPause_GetIsGamePaused() then
                return
            end
            return original(self, input)
        end
    )
end

-- Commanders cannot build or research while paused.
for _, name in ipairs({ "Commander", "AlienCommander", "MarineCommander" }) do
    local original
    original = SSMPause_ReplaceMethod(name, "ProcessTechTreeAction",
        function(...)
            if SSMPause_GetIsGamePaused() then
                return false
            end
            return original(...)
        end
    )
end

local originalAddTimedCallback
originalAddTimedCallback = SSMPause_ReplaceMethod("Entity", "AddTimedCallback",
    function(self, func, interval, early)
        local function BlockCallsIfPaused(self, deltaTime)
            if SSMPause_GetIsGamePaused() and not table.contains(AllowedCallbackClassNames, self:GetClassName()) then
                return true
            end
            return func(self, deltaTime)
        end
        return originalAddTimedCallback(self, BlockCallsIfPaused, interval, early)
    end
)

local originalMoveToTarget
originalMoveToTarget = SSMPause_ReplaceMethod("PathingMixin", "MoveToTarget",
    function(...)
        if SSMPause_GetIsGamePaused() then
            return false
        end
        return originalMoveToTarget(...)
    end
)

local originalWhipOnTag
originalWhipOnTag = SSMPause_ReplaceMethod("Whip", "OnTag",
    function(self, tagName)
        if SSMPause_GetIsGamePaused() then
            return
        end
        originalWhipOnTag(self, tagName)
    end
)

local originalWhipUpdateOrders
originalWhipUpdateOrders = SSMPause_ReplaceMethod("Whip", "UpdateOrders",
    function(self, deltaTime)
        if SSMPause_GetIsGamePaused() then
            return
        end
        originalWhipUpdateOrders(self, deltaTime)
    end
)

-- No getting into or out of the command chair while paused or about to pause.
local originalCommandStructureOnUse
originalCommandStructureOnUse = SSMPause_ReplaceMethod("CommandStructure", "OnUse",
    function(self, player, elapsedTime, useSuccessTable)
        if SSMPause_GetIsGamePaused() or SSMPause_GetIsGamePausing() then
            useSuccessTable.useSuccess = false
        else
            originalCommandStructureOnUse(self, player, elapsedTime, useSuccessTable)
        end
    end
)

local oldGetCommanderLogoutAllowed = GetCommanderLogoutAllowed
if oldGetCommanderLogoutAllowed then
    function GetCommanderLogoutAllowed(...)
        if SSMPause_GetIsGamePaused() then
            return false
        end
        return oldGetCommanderLogoutAllowed(...)
    end
end

local function SetPlayerPauseFields(player)
    player.gamepaused = SSMPause_GetIsGamePaused()
    player.timepaused = SSMPause_GetPausedTime()
    player.timeadjustment = gSharedGetTimeAdjustments
end

local originalCopyPlayerDataFrom
originalCopyPlayerDataFrom = SSMPause_ReplaceMethod("Player", "CopyPlayerDataFrom",
    function(self, player)
        originalCopyPlayerDataFrom(self, player)
        SetPlayerPauseFields(self)
    end
)

local originalPlayerOnCreate
originalPlayerOnCreate = SSMPause_ReplaceMethod("Player", "OnCreate",
    function(self, ...)
        originalPlayerOnCreate(self, ...)
        SetPlayerPauseFields(self)
    end
)

local lastTimeAdjustmentUpdate = 0
local kTimeAdjustmentUpdateRate = 1

-- Every tick while paused: keep the players' time fields current and keep scoreboard pings,
-- health and tech points updating.
local function UpdateEntStates(deltatime)

    local updateTime = false
    lastTimeAdjustmentUpdate = lastTimeAdjustmentUpdate + deltatime
    if lastTimeAdjustmentUpdate > (1 / kTimeAdjustmentUpdateRate) then
        lastTimeAdjustmentUpdate = lastTimeAdjustmentUpdate - (1 / kTimeAdjustmentUpdateRate)
        updateTime = true
    end

    for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
        if updateTime then
            player.timeadjustment = gSharedGetTimeAdjustments
        end
        player.gamepaused = gamestate.gamepaused
        player.timepaused = gamestate.gamepausedtime
    end

    local gamerules = GetGamerules()
    if gamerules and gamerules.timeToSendAllPings then
        gamerules.timeToSendAllPings = gamerules.timeToSendAllPings - deltatime
        gamerules.timeToSendIndividualPings = gamerules.timeToSendIndividualPings - deltatime
        gamerules.timeToSendHealth = gamerules.timeToSendHealth - deltatime
        gamerules.timeToSendTechPoints = gamerules.timeToSendTechPoints - deltatime
        gamerules:UpdatePings()
        gamerules:UpdateHealth()
        gamerules:UpdateTechPoints()
    end

end

-- On resume: restore what SaveEntStates switched off.
local function ResumeEntStates()

    for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
        player.gamepaused = gamestate.gamepaused
        player.timeadjustment = gSharedGetTimeAdjustments
        player.timepaused = gamestate.gamepausedtime
    end

    -- Resume the beacon sound.
    for _, ob in ientitylist(Shared.GetEntitiesWithClassname("Observatory")) do
        if ob.distressBeaconTime ~= nil and ob.distressBeaconSound ~= nil then
            ob.distressBeaconSound:Start()
            ob.distressBeaconSound:SetOrigin(ob:GetDistressOrigin())
        end
    end

    for _, ent in ientitylist(Shared.GetEntitiesWithClassname("Entity")) do
        for i = 1, #UpdatingClasses do
            if ent:isa(UpdatingClasses[i]) then
                ent:SetUpdates(true)
                break
            end
        end
        if ent.WakeUp then
            ent:WakeUp()
        end
    end

end

-- When the pause starts: save or cancel what cannot be paused through the clock alone.
local function SaveEntStates()

    for _, sentry in ientitylist(Shared.GetEntitiesWithClassname("Sentry")) do
        sentry.attacking = false
    end

    for _, ob in ientitylist(Shared.GetEntitiesWithClassname("Observatory")) do
        if ob.distressBeaconTime ~= nil and ob.distressBeaconSound ~= nil then
            ob.distressBeaconSound:Stop()
        end
    end

    for _, whip in ientitylist(Shared.GetEntitiesWithClassname("Whip")) do
        whip.attacking = false
        whip.slapping = false
        whip.bombarding = false
        whip.attackStartTime = nil
        whip.targetId = Entity.invalidId
        whip.waitingForEndAttack = false
    end

    for _, player in ientitylist(Shared.GetEntitiesWithClassname("Player")) do
        if ValidateTeamNumber(player:GetTeamNumber()) then
            player:PrimaryAttackEnd()
            local weapon = player:GetActiveWeapon()
            if weapon ~= nil then
                weapon.reloading = false
            end
            player:SetCameraShake(0)
            if player.secondaryAttackLastFrame then
                player:SecondaryAttackEnd()
            end
        end
        player.gamepaused = true
        player.timepaused = Shared.GetTime()
    end

    for _, ent in ientitylist(Shared.GetEntitiesWithClassname("Entity")) do
        if not ent:isa("PlayerInfoEntity") then
            ent:SetUpdates(false)
        end
    end

end

local function ClearResumeVotes()
    gamestate.team1resume = false
    gamestate.team2resume = false
    gamestate.team1lastresume = 0
    gamestate.team2lastresume = 0
end

local function PausesLeft(teamNumber)
    return math.max(0, Setting("PausesPerTeam") - (gamestate.teampauses[teamNumber] or 0))
end

local function UpdatePause(deltatime)

    if gamestate.serverpauseloopenabled then

        gamestate.gamepauseddelta = gamestate.gamepauseddelta + deltatime

        if SSMPause_GetIsGamePaused() then

            gSharedGetTimeAdjustments = gSharedGetTimeAdjustments + deltatime
            gamestate.gamepausedmessagetime = gamestate.gamepausedmessagetime + deltatime

            if gamestate.gamepausedmessagetime > Setting("ReadyReminderInterval") and gamestate.gamepausedcountdown == 0 then
                if gamestate.team2resume and not gamestate.team1resume then
                    SayAll(string.format("%s are ready, waiting for the %s.", TeamName(2), TeamName(1)))
                elseif gamestate.team1resume and not gamestate.team2resume then
                    SayAll(string.format("%s are ready, waiting for the %s.", TeamName(1), TeamName(2)))
                elseif not gamestate.team1resume and not gamestate.team2resume then
                    SayAll("No team is ready to resume. Type unpause in chat to ready your team.")
                end
                if Setting("AutoResumeAfter") > 0 then
                    SayAll(string.format("Game will automatically resume in %d seconds.", math.max(0, math.floor(Setting("AutoResumeAfter") - gamestate.gamepauseddelta))))
                end
                gamestate.gamepausedmessagetime = 0
            end

            UpdateEntStates(deltatime)

            if Setting("AutoResumeAfter") > 0 and gamestate.gamepauseddelta >= Setting("AutoResumeAfter") and gamestate.gamepausedcountdown == 0 then
                Log("auto-resume after " .. math.floor(gamestate.gamepauseddelta) .. " s")
                gamestate.serverprepauseloopenabled = true
                gamestate.gamepausedcountdown = Countdown("ResumeCountdown")
            end

        else

            ResumeEntStates()
            gamestate.serverpauseloopenabled = false
            if gamestate.gamepausingteam ~= 0 then
                SayAll(string.format("Game resumed. %s have %d pauses remaining.", TeamName(gamestate.gamepausingteam), PausesLeft(gamestate.gamepausingteam)))
            end
            Log(string.format("game resumed after %d s paused", math.floor(gamestate.gamepauseddelta)))
            gamestate.gamepausedtime = 0
            gamestate.gamepausingteam = 0
            gamestate.gamepauseddelta = 0

        end

    end

    if gamestate.serverprepauseloopenabled then

        gamestate.gameprepausedelta = gamestate.gameprepausedelta + deltatime

        if gamestate.gameprepausedelta >= 1 then

            gamestate.gamepausedcountdown = gamestate.gamepausedcountdown - 1

            if gamestate.gamepausedcountdown > 0 then
                SayAll(string.format("Game will %s in %d %s.", SSMPause_GetIsGamePaused() and "resume" or "pause",
                    gamestate.gamepausedcountdown, gamestate.gamepausedcountdown == 1 and "second" or "seconds"))
            else
                if not SSMPause_GetIsGamePaused() then
                    SaveEntStates()
                    gamestate.serverpauseloopenabled = true
                    SayAll("Game paused.")
                    Log("game paused")
                    gamestate.gamepausedtime = Shared.GetTime()
                end
                -- When resuming, the paused loop above runs the resume on the next frame.
                gamestate.serverprepauseloopenabled = false
                gamestate.gamepaused = not SSMPause_GetIsGamePaused()
                gamestate.gamepausedcountdown = 0
            end

            gamestate.gameprepausedelta = gamestate.gameprepausedelta - 1

        end

    end

    if Shared.GetTime(true) - lastPasswordSave >= kPasswordStateSaveSeconds then
        SavePasswordState()
    end

end

Event.Hook("UpdateServer", UpdatePause)

-- Commands ----------------------------------------------------------------------------------

-- explicit: the player typed !pause or gpause, so a "not on this server" answer is worth sending
-- (plain "pause" in chat may just be talk).
local function OnCommandPause(client, explicit)

    local gamerules = GetGamerules()
    if client == nil or not gamerules then
        return
    end

    if not SSMPause_GetAllowedReason() then
        if explicit then
            SayTo(client, "pause_unavailable")
        end
        return
    end

    if not gamerules:GetGameStarted() then
        return
    end

    local player = client:GetControllingPlayer()
    if player == nil or SSMPause_GetIsGamePaused() or gamestate.gamepausedcountdown ~= 0 then
        return
    end

    local teamNumber = player:GetTeamNumber()
    if not ValidateTeamNumber(teamNumber) then
        return
    end

    if PausesLeft(teamNumber) <= 0 then
        SayTo(client, "pause_none_left")
        return
    end

    gamestate.teampauses[teamNumber] = (gamestate.teampauses[teamNumber] or 0) + 1
    ClearResumeVotes()
    gamestate.gamepausedcountdown = Countdown("PauseCountdown")
    gamestate.gamepausingteam = teamNumber
    gamestate.serverprepauseloopenabled = true

    SayAll(string.format("%s has paused the game.", player:GetName()))
    Log(string.format("%s (%s) paused the game; %s have %d pauses left", player:GetName(), TeamName(teamNumber), TeamName(teamNumber), PausesLeft(teamNumber)))

end

local function OnCommandUnPause(client)

    if client == nil then
        return
    end

    local player = client:GetControllingPlayer()
    if player == nil or not SSMPause_GetIsGamePaused() then
        return
    end

    local teamNumber = player:GetTeamNumber()
    local lastResume = teamNumber == 1 and gamestate.team1lastresume or gamestate.team2lastresume
    if not ValidateTeamNumber(teamNumber) or lastResume + 2 >= Shared.GetTime(true) then
        return
    end

    if teamNumber == 1 then
        gamestate.team1resume = not gamestate.team1resume
        gamestate.team1lastresume = Shared.GetTime(true)
    else
        gamestate.team2resume = not gamestate.team2resume
        gamestate.team2lastresume = Shared.GetTime(true)
    end

    if gamestate.team2resume and not gamestate.team1resume then
        SayAll(string.format("%s readied for the %s, waiting for the %s.", player:GetName(), TeamName(2), TeamName(1)))
    elseif gamestate.team1resume and not gamestate.team2resume then
        SayAll(string.format("%s readied for the %s, waiting for the %s.", player:GetName(), TeamName(1), TeamName(2)))
    elseif not gamestate.team1resume and not gamestate.team2resume then
        SayAll("No team is ready to resume. Type unpause in chat to ready your team.")
    elseif gamestate.gamepausedcountdown == 0 then
        SayAll(string.format("%s readied for the %s, resuming game.", player:GetName(), TeamName(teamNumber)))
        gamestate.serverprepauseloopenabled = true
        gamestate.gamepausedcountdown = Countdown("ResumeCountdown")
    end

end

-- Pause because a player disconnected (SavedPlayers/Server.lua). As in NSL: uses one of the
-- team's pauses, but pauses even when the team has none left, after a 1 second countdown. Only
-- where pausing is allowed. Returns true when it paused.
function SSMPause_TriggerDisconnectPause(name, teamNumber)

    local gamerules = GetGamerules()
    if not SSMPause_GetAllowedReason() or not Setting("PauseOnDisconnect") then
        return false
    end
    if not gamerules or not gamerules:GetGameStarted() or SSMPause_GetIsGamePaused()
            or gamestate.gamepausedcountdown ~= 0 or not ValidateTeamNumber(teamNumber) then
        return false
    end

    gamestate.teampauses[teamNumber] = math.min(Setting("PausesPerTeam"), (gamestate.teampauses[teamNumber] or 0) + 1)
    ClearResumeVotes()
    gamestate.gamepausedcountdown = 1
    gamestate.gamepausingteam = teamNumber
    gamestate.serverprepauseloopenabled = true

    SayAll(string.format("%s disconnected, pausing the game.", name))
    Log(string.format("%s (%s) disconnected, auto-pause; %s have %d pauses left", name, TeamName(teamNumber), TeamName(teamNumber), PausesLeft(teamNumber)))
    return true

end

Event.Hook("Console_gpause", function(client) OnCommandPause(client, true) end)
Event.Hook("Console_unpause", OnCommandUnPause)

-- Chat commands. Vanilla passes every chat message to ProcessSayCommand (NetworkMessages_Server.lua,
-- for tournament mode's ready commands), so this works without Shine (Thunderdome). SSM's own chat
-- router (Commands.lua) does not claim these words, so with Shine they still reach this.
local kPauseChat = { ["pause"] = false, ["!pause"] = true, ["/pause"] = true }
local kResumeChat = { ["unpause"] = true, ["!unpause"] = true, ["/unpause"] = true,
                      ["resume"] = true, ["!resume"] = true, ["/resume"] = true }

local oldProcessSayCommand = ProcessSayCommand
function ProcessSayCommand(player, command)

    local text = string.lower(StringTrim(command or ""))
    local client = player and Server.GetOwner(player)

    if client then
        if kPauseChat[text] ~= nil then
            OnCommandPause(client, kPauseChat[text])
        elseif kResumeChat[text] then
            OnCommandUnPause(client)
        end
    end

    if oldProcessSayCommand then
        return oldProcessSayCommand(player, command)
    end

end

SSM.ListCommand("!pause", "cmd_pause")
SSM.ListCommand("!unpause", "cmd_unpause")

-- Round start and reset ---------------------------------------------------------------------

local oldSetGameState
oldSetGameState = Class_ReplaceMethod("NS2Gamerules", "SetGameState", function(self, state, ...)
    local before = self:GetGameState()
    local result = oldSetGameState(self, state, ...)

    if state == kGameState.Started and before ~= kGameState.Started then
        local reason = SSMPause_GetAllowedReason()
        if reason then
            SayAll(kAnnouncements[reason])
            Log("round started, pause enabled (" .. reason .. ")")
        end
    end

    return result
end)

-- Every round starts with full pause counts. A reset during a pause (an admin reset, for example)
-- clears the pause first.
local oldResetGame
oldResetGame = Class_ReplaceMethod("NS2Gamerules", "ResetGame", function(self, ...)

    if gamestate.gamepaused or gamestate.gamepausedcountdown ~= 0 then
        gamestate.gamepaused = false
        gamestate.gamepausedcountdown = 0
        gamestate.serverprepauseloopenabled = false
        gamestate.serverpauseloopenabled = false
        ResumeEntStates()
        gamestate.gamepausedtime = 0
        gamestate.gamepausingteam = 0
        gamestate.gamepauseddelta = 0
        Log("round reset during a pause; pause cleared")
    end

    gamestate.teampauses = { }
    ClearResumeVotes()

    return oldResetGame(self, ...)

end)

Log(string.format("%s: %d pauses per team, %d s / %d s countdowns, auto-resume %s",
    Setting("PauseEnabled") and "on for Thunderdome and passworded games" or "switched off in " .. kSettingsFile,
    Setting("PausesPerTeam"), Countdown("PauseCountdown"), Countdown("ResumeCountdown"),
    Setting("AutoResumeAfter") > 0 and (Setting("AutoResumeAfter") .. " s") or "off"))
