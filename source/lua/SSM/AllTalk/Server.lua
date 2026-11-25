-- All Talk - server side.
--
-- Turns on Shine's all talk, the same switch as !alltalk and sh_alltalk, so everyone can hear
-- each other between rounds.
--
-- Rules (the author's picks, 2026-11-25):
--   * On when a round ends, and when a map loads, if it is off.
--   * Never turned off by the mod: an admin does that with !alltalk. So once a round has ended,
--     all talk stays on until someone turns it off.
--   * Not on Thunderdome: Thunderdome games are set up by their lobby.
--   * Needs Shine with its basecommands plugin (where all talk lives). Without it nothing happens.
--
-- The change is not saved to Shine's config file, so the admin's own AllTalk setting there stays
-- as it was. That is why a map change turns it off again (Shine reloads its config), and why the
-- map load turns it back on.

local kSettingsFile = "SSM_AllTalk.json"
local kDefaultSettings = { Enabled = true }   -- false: the mod never touches all talk

-- After a map loads, how often and for how long to look for Shine's plugin, which may enable
-- after this file runs.
local kMapLoadCheckSeconds = 1
local kMapLoadWaitSeconds = 60

local settings = LoadConfigFile(kSettingsFile, kDefaultSettings, true)
if type(settings) ~= "table" or type(settings.Enabled) ~= "boolean" then
    settings = { Enabled = true }
end

local function Log(text)
    Shared.Message("[NS2 SUD] all talk: " .. text)
end

local function GetIsThunderdome()
    return Shared.GetThunderdomeEnabled ~= nil and Shared.GetThunderdomeEnabled() == true
end

local function GetPlugin()
    if not (Shine and Shine.IsExtensionEnabled) then
        return nil
    end
    local enabled, plugin = Shine:IsExtensionEnabled("basecommands")
    if enabled and plugin and plugin.SetAllTalkEnabled and plugin.IsAllTalkEnabled then
        return plugin
    end
end

-- Turns all talk on if it is off. Returns false only while Shine's plugin is not there yet.
local function TurnOn(reason)
    if not settings.Enabled or GetIsThunderdome() then
        return true
    end

    local plugin = GetPlugin()
    if not plugin then
        return false
    end
    if plugin:IsAllTalkEnabled("AllTalk") then
        return true
    end

    -- true: not saved to Shine's config file.
    plugin:SetAllTalkEnabled("AllTalk", true, true)
    -- Shine's own "all talk enabled" line to everyone, in each player's Shine language.
    if plugin.NotifyAllTalkState then
        plugin:NotifyAllTalkState("AllTalk", true)
    end
    Log("on (" .. reason .. ")")
    return true
end

local function SafeTurnOn(reason)
    local ok, result = pcall(TurnOn, reason)
    if not ok then
        Log("error: " .. tostring(result))
        return true
    end
    return result
end

-- Round end.
local oldEndGame
oldEndGame = Class_ReplaceMethod("NS2Gamerules", "EndGame", function(self, ...)
    local result = { oldEndGame(self, ...) }
    SafeTurnOn("round ended")
    return (table.unpack or unpack)(result)
end)

-- Map load: once Shine's plugin is there, or give up after kMapLoadWaitSeconds.
local mapLoadStart
local lastMapLoadCheck = -math.huge
local mapLoadDone = not settings.Enabled

Event.Hook("UpdateServer", function()
    if mapLoadDone then
        return
    end

    local now = Shared.GetTime()
    mapLoadStart = mapLoadStart or now
    if now - lastMapLoadCheck < kMapLoadCheckSeconds then
        return
    end
    lastMapLoadCheck = now

    if SafeTurnOn("map loaded") then
        mapLoadDone = true
    elseif now - mapLoadStart >= kMapLoadWaitSeconds then
        mapLoadDone = true
        Log("Shine's basecommands plugin is not enabled, all talk left alone")
    end
end)

Log(settings.Enabled and "on at round end and map load (Shine), not on Thunderdome"
    or ("switched off in " .. kSettingsFile))
