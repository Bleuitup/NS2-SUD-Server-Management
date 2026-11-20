-- B2TP Thunderdome features, server part: the settings file, then the pause and the saved player
-- states. Nothing here runs unless the server is in Thunderdome mode.

if not B2TP_GetPauseInstalled or not B2TP_GetPauseInstalled() then
    return
end

-- Settings: config://B2TP_Thunderdome.json in the server's config folder. Written with these
-- defaults when missing (missing keys are added), read at every map load.
local kDefaultSettings =
{
    PauseEnabled = true,         -- false turns the pause off (also turns off PauseOnDisconnect)
    PausesPerTeam = 4,           -- per team, per round
    PauseCountdown = 5,          -- seconds between pause and the game freezing
    ResumeCountdown = 5,         -- seconds between both teams being ready and the game resuming
    AutoResumeAfter = 300,       -- seconds paused before the game resumes on its own; 0 = never
    ReadyReminderInterval = 30,  -- seconds between reminders of who still has to ready up
    SavePlayerStates = true,     -- keep a disconnected player's lifeform/gear until they reconnect
    PauseOnDisconnect = true,    -- pause when a saved player disconnects (uses one of their team's pauses)
}

local settings = LoadConfigFile("B2TP_Thunderdome.json", kDefaultSettings, true) or {}

function B2TPTD_Setting(name)
    local value = settings[name]
    if type(value) ~= type(kDefaultSettings[name]) then
        return kDefaultSettings[name]
    end
    return value
end

function B2TPTD_Log(text)
    Shared.Message("[B2TP] " .. text)
end

local function ChatMessage(text)
    return BuildChatMessage(false, "Server", -1, kTeamReadyRoom, kNeutralTeamType, text)
end

function B2TPTD_SayAll(text)
    Server.SendNetworkMessage("Chat", ChatMessage(text), true)
end

function B2TPTD_SayTo(client, text)
    local player = client and client:GetControllingPlayer()
    if player then
        Server.SendNetworkMessage(player, "Chat", ChatMessage(text), true)
    end
end

Script.Load("lua/B2TP/Thunderdome/Pause_Server.lua")
Script.Load("lua/B2TP/Thunderdome/PlayerStates_Server.lua")
