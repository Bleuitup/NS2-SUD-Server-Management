-- NS2 SUD pause, client part.
--
-- Ported from Dragon's NSL Mod (lua/NSL/pause/client.lua, https://github.com/xToken/NSL), first
-- for Blast to the Past, then moved here. Keeps effects, chat, the scoreboard, the minimap and the
-- menus working while the game clock is frozen. Inert unless the server pauses. NSL's spectator
-- and league GUI names are left out; the chat fix is done without replacing GUIChat.

-- Some effects (materials that read the time) do not call back into Lua, so these functions read
-- the real clock. Wrapped at LoadComplete, when every class exists.
local kTimeBypassFunctions =
{
    { "Alien", "UpdateClientEffects" },
    { "BiteLeap", "CreateBloodEffect" },
    { "LerkBite", "CreateBloodEffect" },
    { "DetectableMixin", "OnUpdateRender" },
    { "ClientWeaponEffectsMixin", "UpdateAttackEffects" },
    { "UmbraMixin", "OnUpdateRender" },
    { "CloakableMixin", "OnUpdateRender" },
    { "Fade", "OnUpdateRender" },
    { "ExoWeaponHolder", "OnUpdateRender" },
}

local function WrapWithTimeBypass(className, methodName)
    local original
    original = SSMPause_ReplaceMethod(className, methodName,
        function(...)
            gTimeBypass = true
            local a, b, c = original(...)
            gTimeBypass = false
            return a, b, c
        end
    )
end

Event.Hook("LoadComplete", function()
    for _, entry in ipairs(kTimeBypassFunctions) do
        WrapWithTimeBypass(entry[1], entry[2])
    end
end)

-- Chat while paused. GUIChat drops the keystroke that opened chat by comparing Shared.GetTime()
-- with the time chat was opened; with the clock frozen those are always equal, so nothing could be
-- typed. Same rule, but "same moment" is now measured on the real clock (NSL's 5 ms window).
local chatOpenedAt = -1
local kChatMinWindow = 0.005

local oldChatUI_EnterChatMessage = ChatUI_EnterChatMessage
if oldChatUI_EnterChatMessage then
    function ChatUI_EnterChatMessage(...)
        chatOpenedAt = Client.GetTime()
        return oldChatUI_EnterChatMessage(...)
    end

    function ChatUI_GetStartedChatTime()
        if Client.GetTime() - chatOpenedAt <= kChatMinWindow then
            return Shared.GetTime()
        end
        return -1
    end
end

-- GUI scripts that keep updating in real time while paused (the rest wait for the clock).
local kPausedUpdateScripts =
{
    GUIScoreboard = true, GUIChat = true, GUIMinimapFrame = true, GUITechMap = true, GUIEggDisplay = true,
    GUIInsight_PlayerFrames = true, GUIInsight_Overhead = true, GUIInsight_PenTool = true,
    GUIInsight_PlayerHealthbars = true, GUIInsight_Graphs = true
}

local function ScriptName(script)
    if script.classname then
        return script.classname
    end
    local path = script._scriptName
    if type(path) == "string" then
        return (path:match("([^/]+)$") or path):gsub("%.lua$", "")
    end
end

local kPausedScoreboardUpdateRate = 0.5
local scoreboardUpdate = kPausedScoreboardUpdateRate

local originalGUIManagerUpdate
originalGUIManagerUpdate = SSMPause_ReplaceMethod("GUIManager", "Update",
    function(self, deltaTime)
        local player = Client.GetLocalPlayer()
        if player and player.gamepaused and self.scripts then
            for s = self.scripts:GetCount(), 1, -1 do
                local script = self.scripts:GetValueAtIndex(s)
                if script and kPausedUpdateScripts[ScriptName(script)] then
                    script.lastUpdateTime = script.lastUpdateTime - deltaTime
                    script.nextUpdateTime = script.nextUpdateTime - deltaTime
                end
            end
            scoreboardUpdate = math.max(0, scoreboardUpdate - deltaTime)
            if scoreboardUpdate == 0 and Scoreboard_ReloadPlayerData then
                Scoreboard_ReloadPlayerData()
                scoreboardUpdate = kPausedScoreboardUpdateRate
            end
        end
        originalGUIManagerUpdate(self, deltaTime)
    end
)

-- The newer GUI system (menus and their animations) reads the clock in one UpdateClient hook;
-- give it the real clock so the menus keep working while paused. Skipped if the engine does not
-- expose its hook table.
local HookTable = Event.HookTable
if type(HookTable) == "table" and type(HookTable["UpdateClient"]) == "table" then
    local baseGUIManagerHook
    for i, e in ipairs(HookTable["UpdateClient"]) do
        if type(e) == "function" and string.find(ToString(e), "lua/GUI/BaseGUIManager.lua", 1, true) then
            baseGUIManagerHook = e
            table.remove(HookTable["UpdateClient"], i)
            break
        end
    end
    if baseGUIManagerHook then
        Event.Hook("UpdateClient", function(deltaTime)
            gTimeBypass = true
            baseGUIManagerHook(deltaTime)
            gTimeBypass = false
        end)
    end
end
