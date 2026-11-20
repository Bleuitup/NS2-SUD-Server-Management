-- NS2 SUD pause, shared part (Server, Client and Predict VMs).
--
-- Ported from Dragon's NSL Mod (lua/NSL/pause/shared.lua, https://github.com/xToken/NSL), first
-- for Blast to the Past, then moved here. NSL's league plumbing is replaced.
--
-- Installed on every server, and inert until the server pauses: whether pausing is allowed
-- (Thunderdome, or a server password) is decided on the server only (Pause/Server.lua). Clients
-- follow the gamepaused field the server sets on their player.
--
-- How the pause works: Shared.GetTime and Shared.GetPreviousTime are replaced. While paused they
-- return the time the pause started; after a pause they return real time minus the total time
-- spent paused (gSharedGetTimeAdjustments on the server, the player's timeadjustment field on
-- clients). Everything that reads the clock therefore stands still. Player input, movement,
-- gravity, buying and projectiles are blocked while paused. Pass true (Shared.GetTime(true)) to
-- read the real clock.

-- The three network fields are always added, so a client and a server agree on the Player network
-- layout (a mismatch would disconnect players). They stay at 0 / false unless the server pauses.
Class_Reload("Player", { timeadjustment = "float", timepaused = "float", gamepaused = "boolean" })

-- Replace a function on a class, a mixin or a plain table (Shared), and in every class derived from
-- it that still uses the original. Unlike core's Class_ReplaceMethod it does not assert: a name
-- that does not exist in this build is skipped and nil is returned, so the caller installs nothing.
function SSMPause_ReplaceMethod(className, methodName, method)

    local container = _G[className]
    if container == nil or container[methodName] == nil then
        return nil
    end

    local original = container[methodName]

    local function ReplaceIn(name)
        local c = _G[name]
        if c == nil or c[methodName] ~= original then
            return
        end
        c[methodName] = method
        local derived = Script.GetDerivedClasses(name)
        if derived then
            for _, d in ipairs(derived) do
                ReplaceIn(d)
            end
        end
    end

    ReplaceIn(className)
    return original

end

local oldPlayerOnCreate
oldPlayerOnCreate = SSMPause_ReplaceMethod("Player", "OnCreate",
    function(self, ...)
        oldPlayerOnCreate(self, ...)
        self.timeadjustment = 0
        self.timepaused = 0
        self.gamepaused = false
    end
)

gTimeBypass = false
gPreviousPausedTime = 0
gSharedGetTimeAdjustments = gSharedGetTimeAdjustments or 0

local function GetServerPaused()
    return SSMPause_GetIsGamePaused ~= nil and SSMPause_GetIsGamePaused()
end

local kClientPaused
local kClientView = { yaw = 0, pitch = 0 }
local kJetpackJumpWindow = 0.001

local function ValidateTeamNumber(teamnum)
    return teamnum ~= 3
end

local function SaveClientViewAngles(player)
    if Client then
        if not kClientPaused then
            kClientPaused = true
            kClientView.yaw = debug.getupvaluex(Client.SetYaw, "_cameraYaw")
            kClientView.pitch = debug.getupvaluex(Client.SetPitch, "_cameraPitch")
            return true
        else
            Client.SetYaw(kClientView.yaw)
            Client.SetPitch(kClientView.pitch)
        end
    end
    return false
end

local function RestoreClientViewAngles()
    if Client and kClientPaused then
        Client.SetYaw(kClientView.yaw)
        Client.SetPitch(kClientView.pitch)
        kClientPaused = false
        kClientView = { yaw = 0, pitch = 0 }
    end
end

-- Blocks input.
local originalOnProcessIntermediate
originalOnProcessIntermediate = SSMPause_ReplaceMethod("Player", "OnProcessIntermediate",
    function(self, input)
        if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
            if SaveClientViewAngles(self) then
                -- Run once more so the view angles are updated one last time.
                originalOnProcessIntermediate(self, input)
            end
            return
        else
            originalOnProcessIntermediate(self, input)
            RestoreClientViewAngles()
        end
    end
)

local oldFollowMoveMixinUpdateMove = FollowMoveMixin.UpdateMove
function FollowMoveMixin:UpdateMove(input)
    if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
        return
    end
    oldFollowMoveMixinUpdateMove(self, input)
end

local oldGetViewAnglesForRendering = CameraHolderMixin.GetViewAnglesForRendering
function CameraHolderMixin:GetViewAnglesForRendering()
    if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
        return Angles(kClientView.pitch, kClientView.yaw + self.baseYaw, self.viewRoll)
    end
    return oldGetViewAnglesForRendering(self)
end

-- Blocks movement.
local originalOnProcessMove
originalOnProcessMove = SSMPause_ReplaceMethod("Player", "OnProcessMove",
    function(self, input)
        if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
            return
        end
        originalOnProcessMove(self, input)
    end
)

local oldSetDesiredCamera = CameraHolderMixin.SetDesiredCamera
function CameraHolderMixin:SetDesiredCamera(...)
    if self.gamepaused then
        return
    end
    oldSetDesiredCamera(self, ...)
end

-- Blocks buying things.
local originalProcessBuyAction
originalProcessBuyAction = SSMPause_ReplaceMethod("Player", "ProcessBuyAction",
    function(self, upgrades)
        if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
            return false
        end
        return originalProcessBuyAction(self, upgrades)
    end
)

-- Blocks input.
local originalGetCanControl
originalGetCanControl = SSMPause_ReplaceMethod("Player", "GetCanControl",
    function(self)
        if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
            return false
        end
        return originalGetCanControl(self)
    end
)

-- Vanilla (build 345) compares timeJetpackingChanged == Shared.GetTime(); with the clock shifted by
-- the pause adjustments that equality can miss by a rounding error, so allow a tiny window instead.
-- Otherwise the same as vanilla's.
SSMPause_ReplaceMethod("JetpackMarine", "GetCanJump",
    function(self)
        local jetpackChangeTime = Shared.GetTime() - self.timeJetpackingChanged
        return self:GetIsOnGround() or (self.startedFromGround and jetpackChangeTime < kJetpackJumpWindow) or self:GetIsOnLadder()
    end
)

-- No gravity while paused, so players in mid air do not stutter.
local originalModifyGravityForce
originalModifyGravityForce = SSMPause_ReplaceMethod("Player", "ModifyGravityForce",
    function(self, gravityTable)
        if self.gamepaused and ValidateTeamNumber(self:GetTeamNumber()) then
            gravityTable.gravity = 0
        else
            originalModifyGravityForce(self, gravityTable)
        end
    end
)

-- Healing effects read the real clock, or they stop working after a pause.
local oldLiveMixinAddHealth = LiveMixin.AddHealth
function LiveMixin:AddHealth(...)
    gTimeBypass = true
    local healed = oldLiveMixinAddHealth(self, ...)
    gTimeBypass = false
    return healed
end

local oldLiveMixinSetArmor = LiveMixin.SetArmor
function LiveMixin:SetArmor(...)
    gTimeBypass = true
    oldLiveMixinSetArmor(self, ...)
    gTimeBypass = false
end

-- Pause (most) projectiles.
if Server then
    local originalShooterOnProcessMove = PredictedProjectileShooterMixin.OnProcessMove
    if originalShooterOnProcessMove then
        function PredictedProjectileShooterMixin.OnProcessMove(self, input)
            if self.gamepaused then
                return
            end
            originalShooterOnProcessMove(self, input)
        end
    end
elseif Client then
    local originalShooterOnProcessIntermediate = PredictedProjectileShooterMixin.OnProcessIntermediate
    if originalShooterOnProcessIntermediate then
        function PredictedProjectileShooterMixin.OnProcessIntermediate(self, input)
            if self.gamepaused then
                return
            end
            originalShooterOnProcessIntermediate(self, input)
        end
    end
end

local originalGetPreviousTime
originalGetPreviousTime = SSMPause_ReplaceMethod("Shared", "GetPreviousTime",
    function(RealTime)
        local localPlayer
        local timeadjustment = 0
        if Server then
            if GetServerPaused() then
                if gPreviousPausedTime == 0 then
                    gPreviousPausedTime = originalGetPreviousTime()
                end
                if gTimeBypass or RealTime then
                    return originalGetPreviousTime()
                end
                return gPreviousPausedTime
            else
                gPreviousPausedTime = 0
                timeadjustment = gSharedGetTimeAdjustments
            end
        elseif Client then
            localPlayer = Client.GetLocalPlayer()
        elseif Predict then
            localPlayer = Predict.GetLocalPlayer()
        end
        if localPlayer ~= nil then
            if localPlayer.gamepaused then
                if gPreviousPausedTime == 0 then
                    gPreviousPausedTime = originalGetPreviousTime()
                end
                if gTimeBypass or RealTime then
                    return originalGetPreviousTime()
                end
                return gPreviousPausedTime
            else
                gPreviousPausedTime = 0
                timeadjustment = localPlayer.timeadjustment
            end
        end
        if gTimeBypass or RealTime then
            timeadjustment = 0
        end
        return originalGetPreviousTime() - (timeadjustment or 0)
    end
)

local originalGetTime
originalGetTime = SSMPause_ReplaceMethod("Shared", "GetTime",
    function(RealTime)
        local timeadjustment = 0
        local localPlayer
        if Server then
            if GetServerPaused() and not (gTimeBypass or RealTime) then
                return SSMPause_GetPausedTime()
            else
                timeadjustment = gSharedGetTimeAdjustments
            end
        elseif Client then
            localPlayer = Client.GetLocalPlayer()
        elseif Predict then
            localPlayer = Predict.GetLocalPlayer()
        end
        if localPlayer ~= nil then
            if localPlayer.gamepaused and not (gTimeBypass or RealTime) then
                return localPlayer.timepaused
            else
                timeadjustment = localPlayer.timeadjustment
            end
        end
        if gTimeBypass or RealTime then
            timeadjustment = 0
        end
        return originalGetTime() - (timeadjustment or 0)
    end
)

-- Chat rate limiting uses the real clock, so chat keeps working while paused.
local function AddTokens(self)
    local now = Shared.GetTime(true)
    local timeSinceLastTokenAdded = now - self.lastTimeTokensAdded
    if timeSinceLastTokenAdded >= 1 / self.tokensAddedPerSecond then
        local numberOfTokensToAdd = math.floor(timeSinceLastTokenAdded * self.tokensAddedPerSecond)
        if numberOfTokensToAdd > 0 then
            self.tokens = math.min(self.maxTokensAllowed, self.tokens + numberOfTokensToAdd)
            self.lastTimeTokensAdded = now
        end
    end
end

local function RemoveTokens(self, numberToRemove)
    AddTokens(self)
    local tokensRemoved = self.tokens >= numberToRemove
    if tokensRemoved then
        self.tokens = self.tokens - numberToRemove
    end
    return tokensRemoved
end

local function GetNumberOfTokens(self)
    AddTokens(self)
    return self.tokens
end

ReplaceLocals(CreateTokenBucket, { GetNumberOfTokens = GetNumberOfTokens })
ReplaceLocals(CreateTokenBucket, { RemoveTokens = RemoveTokens })

-- BaseModelMixin caches Shared.GetTime / GetPreviousTime in locals at load; point them at the
-- replacements so animations pause too. (The only such cache in build 345.)
local UpdateAnimationState = debug.getupvaluex(BaseModelMixin.ProcessMoveOnModel, "UpdateAnimationState")
if UpdateAnimationState then
    ReplaceLocals(UpdateAnimationState, { Shared_GetTime = Shared.GetTime })
    ReplaceLocals(UpdateAnimationState, { Shared_GetPreviousTime = Shared.GetPreviousTime })
end
