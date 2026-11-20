-- B2TP pause, server part. Thunderdome only.
--
-- Ported from Dragon's NSL Mod (lua/NSL/pause/server.lua, https://github.com/xToken/NSL). What is
-- B2TP's own: the Thunderdome-only switch, the settings file, English chat messages instead of
-- NSL's message system, chat and console commands without NSL's command registry, pause counts that
-- reset every round, and a server log line for every pause and resume. NSL's referee commands are
-- left out. Pause-on-disconnect is triggered from PlayerStates_Server.lua.
--
-- Players: type pause (or !pause) in chat, or gpause in the console, during a round. After a
-- countdown the game freezes. To resume, someone on EACH team types unpause (or !unpause, resume,
-- !resume); typing it again un-readies your team. The game resumes on its own after AutoResumeAfter
-- seconds. Each team has PausesPerTeam pauses per round.

if not B2TP_GetPauseInstalled or not B2TP_GetPauseInstalled() then
    return
end

local Setting = B2TPTD_Setting

-- A countdown of 0 would mean "no countdown running", so never go below 1 second.
local function Countdown(name)
    return math.max(1, math.floor(Setting(name)))
end

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

function B2TPPause_GetIsGamePaused()
    return gamestate.gamepaused
end

function B2TPPause_GetIsGamePausing()
    return gamestate.gamepausedcountdown ~= 0
end

function B2TPPause_GetPausedTime()
    return gamestate.gamepausedtime
end

if not Setting("PauseEnabled") then
    B2TPTD_Log("pause is switched off in B2TP_Thunderdome.json")
    return
end

local kTeamNames = { [1] = "Marines", [2] = "Aliens" }

local function TeamName(teamNumber)
    return kTeamNames[teamNumber] or ("Team " .. tostring(teamNumber))
end

local SayAll = B2TPTD_SayAll
local SayTo = B2TPTD_SayTo

local function Log(text)
    B2TPTD_Log("pause: " .. text)
end

local function ValidateTeamNumber(teamnum)
    return teamnum == 1 or teamnum == 2
end

-- Classes whose entities keep updating normally; everything else stops updating while paused.
local UpdatingClasses =
{
    "ScriptActor", "Clog", "DeathTrigger", "Gamerules", "ObjectiveInfo", "ParticleEffect", "Pheromone",
    "PredictedProjectile", "Ragdoll", "SoundEffect", "SpawnBlocker", "SporeCloud", "TeamInfo", "TeamJoin",
    "TimedEmitter", "Tunnel", "TunnelProp", "ViewModel", "Web"
}

local AllowedCallbackClassNames = { "PlayerInfoEntity" }

-- Mixins whose OnProcessMove stops while paused. Names that do not exist in this build (or have no
-- OnProcessMove) are skipped by B2TPPause_ReplaceMethod.
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
    original = B2TPPause_ReplaceMethod(name, "OnProcessMove",
        function(self, input)
            if B2TPPause_GetIsGamePaused() then
                return
            end
            return original(self, input)
        end
    )
end

-- Commanders cannot build or research while paused.
for _, name in ipairs({ "Commander", "AlienCommander", "MarineCommander" }) do
    local original
    original = B2TPPause_ReplaceMethod(name, "ProcessTechTreeAction",
        function(...)
            if B2TPPause_GetIsGamePaused() then
                return false
            end
            return original(...)
        end
    )
end

local originalAddTimedCallback
originalAddTimedCallback = B2TPPause_ReplaceMethod("Entity", "AddTimedCallback",
    function(self, func, interval, early)
        local function BlockCallsIfPaused(self, deltaTime)
            if B2TPPause_GetIsGamePaused() and not table.contains(AllowedCallbackClassNames, self:GetClassName()) then
                return true
            end
            return func(self, deltaTime)
        end
        return originalAddTimedCallback(self, BlockCallsIfPaused, interval, early)
    end
)

local originalMoveToTarget
originalMoveToTarget = B2TPPause_ReplaceMethod("PathingMixin", "MoveToTarget",
    function(...)
        if B2TPPause_GetIsGamePaused() then
            return false
        end
        return originalMoveToTarget(...)
    end
)

local originalWhipOnTag
originalWhipOnTag = B2TPPause_ReplaceMethod("Whip", "OnTag",
    function(self, tagName)
        if B2TPPause_GetIsGamePaused() then
            return
        end
        originalWhipOnTag(self, tagName)
    end
)

local originalWhipUpdateOrders
originalWhipUpdateOrders = B2TPPause_ReplaceMethod("Whip", "UpdateOrders",
    function(self, deltaTime)
        if B2TPPause_GetIsGamePaused() then
            return
        end
        originalWhipUpdateOrders(self, deltaTime)
    end
)

-- No getting into or out of the command chair while paused or about to pause.
local originalCommandStructureOnUse
originalCommandStructureOnUse = B2TPPause_ReplaceMethod("CommandStructure", "OnUse",
    function(self, player, elapsedTime, useSuccessTable)
        if B2TPPause_GetIsGamePaused() or B2TPPause_GetIsGamePausing() then
            useSuccessTable.useSuccess = false
        else
            originalCommandStructureOnUse(self, player, elapsedTime, useSuccessTable)
        end
    end
)

local oldGetCommanderLogoutAllowed = GetCommanderLogoutAllowed
function GetCommanderLogoutAllowed(...)
    if B2TPPause_GetIsGamePaused() then
        return false
    end
    return oldGetCommanderLogoutAllowed(...)
end

local function SetPlayerPauseFields(player)
    player.gamepaused = B2TPPause_GetIsGamePaused()
    player.timepaused = B2TPPause_GetPausedTime()
    player.timeadjustment = gSharedGetTimeAdjustments
end

local originalCopyPlayerDataFrom
originalCopyPlayerDataFrom = B2TPPause_ReplaceMethod("Player", "CopyPlayerDataFrom",
    function(self, player)
        originalCopyPlayerDataFrom(self, player)
        SetPlayerPauseFields(self)
    end
)

local originalPlayerOnCreate
originalPlayerOnCreate = B2TPPause_ReplaceMethod("Player", "OnCreate",
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

        if B2TPPause_GetIsGamePaused() then

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
                SayAll(string.format("Game will %s in %d seconds.", B2TPPause_GetIsGamePaused() and "resume" or "pause", gamestate.gamepausedcountdown))
            else
                if not B2TPPause_GetIsGamePaused() then
                    SaveEntStates()
                    gamestate.serverpauseloopenabled = true
                    SayAll("Game paused.")
                    Log("game paused")
                    gamestate.gamepausedtime = Shared.GetTime()
                end
                -- When resuming, the paused loop above runs the resume on the next frame.
                gamestate.serverprepauseloopenabled = false
                gamestate.gamepaused = not B2TPPause_GetIsGamePaused()
                gamestate.gamepausedcountdown = 0
            end

            gamestate.gameprepausedelta = gamestate.gameprepausedelta - 1

        end

    end

end

Event.Hook("UpdateServer", UpdatePause)

local function OnCommandPause(client)

    if client == nil or not GetGamerules():GetGameStarted() then
        return
    end

    local player = client:GetControllingPlayer()
    if player == nil or B2TPPause_GetIsGamePaused() or gamestate.gamepausedcountdown ~= 0 then
        return
    end

    local teamNumber = player:GetTeamNumber()
    if not ValidateTeamNumber(teamNumber) then
        return
    end

    if PausesLeft(teamNumber) <= 0 then
        SayTo(client, "Your team is out of pauses.")
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
    if player == nil or not B2TPPause_GetIsGamePaused() then
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

-- Pause because a player disconnected (PlayerStates_Server.lua). As in NSL: uses one of the team's
-- pauses, but pauses even when the team has none left, after a 1 second countdown.
function B2TPPause_TriggerDisconnectPause(name, teamNumber)

    if not GetGamerules():GetGameStarted() or B2TPPause_GetIsGamePaused() or gamestate.gamepausedcountdown ~= 0
            or not ValidateTeamNumber(teamNumber) then
        return
    end

    gamestate.teampauses[teamNumber] = math.min(Setting("PausesPerTeam"), (gamestate.teampauses[teamNumber] or 0) + 1)
    ClearResumeVotes()
    gamestate.gamepausedcountdown = 1
    gamestate.gamepausingteam = teamNumber
    gamestate.serverprepauseloopenabled = true

    SayAll(string.format("%s disconnected, pausing the game.", name))
    Log(string.format("%s (%s) disconnected, auto-pause; %s have %d pauses left", name, TeamName(teamNumber), TeamName(teamNumber), PausesLeft(teamNumber)))

end

Event.Hook("Console_gpause", OnCommandPause)
Event.Hook("Console_unpause", OnCommandUnPause)

-- Chat commands. Vanilla passes every chat message to ProcessSayCommand (NetworkMessages_Server.lua,
-- for tournament mode's ready commands), so B2TP listens there.
local kPauseChat = { ["pause"] = true, ["!pause"] = true }
local kResumeChat = { ["unpause"] = true, ["!unpause"] = true, ["resume"] = true, ["!resume"] = true }

local oldProcessSayCommand = ProcessSayCommand
function ProcessSayCommand(player, command)

    local text = string.lower(StringTrim(command or ""))
    local client = player and Server.GetOwner(player)

    if client then
        if kPauseChat[text] then
            OnCommandPause(client)
        elseif kResumeChat[text] then
            OnCommandUnPause(client)
        end
    end

    if oldProcessSayCommand then
        return oldProcessSayCommand(player, command)
    end

end

-- Every round starts with full pause counts. A reset during a pause (an admin reset, for example)
-- clears the pause first.
local oldResetGame = NS2Gamerules.ResetGame
function NS2Gamerules:ResetGame(...)

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

end

Log(string.format("on: %d pauses per team, %d s / %d s countdowns, auto-resume %s",
    Setting("PausesPerTeam"), Countdown("PauseCountdown"), Countdown("ResumeCountdown"),
    Setting("AutoResumeAfter") > 0 and (Setting("AutoResumeAfter") .. " s") or "off"))
