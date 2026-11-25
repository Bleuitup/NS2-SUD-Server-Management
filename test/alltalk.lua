-- Logic test for All Talk, run outside the game against the real mod file:
--   lua test/alltalk.lua        (from the repo root)
--
-- Stubs Shine's basecommands plugin, the round end and the server tick. Proves all talk goes on
-- at round end and at map load (also when Shine's plugin enables late), is never turned off or
-- saved to Shine's config, is left alone on Thunderdome, without Shine and when switched off.
-- It says nothing about voice chat itself, which only a server shows.

local kServerFile = "source/lua/SSM/AllTalk/Server.lua"

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

local Files = {}
local Now = 0
local Hooks = {}
local Thunderdome = false
local Plugin              -- Shine's basecommands plugin, or nil
local PluginEnabled = true
local Notified = 0        -- Shine's "all talk enabled" lines
local Saved = 0           -- writes to Shine's config file
local Ended = 0           -- vanilla EndGame calls

function LoadConfigFile(name, default)
    if Files[name] ~= nil then return Files[name] end
    return default
end

Shared = {
    GetTime = function() return Now end,
    GetThunderdomeEnabled = function() return Thunderdome end,
    Message = function(text) if text:find("error") then print("server: " .. text) end end
}

local function NewPlugin(allTalk)
    return {
        Config = { AllTalk = allTalk },
        IsAllTalkEnabled = function(self, type) return self.Config[type] end,
        SetAllTalkEnabled = function(self, type, enabled, dontSave)
            self.Config[type] = enabled
            if not dontSave then Saved = Saved + 1 end
        end,
        NotifyAllTalkState = function(self, type, enabled)
            if type == "AllTalk" and enabled then Notified = Notified + 1 end
        end
    }
end

local function Load()
    Hooks = {}
    Event = { Hook = function(name, fn) Hooks[name] = fn end }
    NS2Gamerules = { EndGame = function(self, winner) Ended = Ended + 1 return "ended" end }
    function Class_ReplaceMethod(className, methodName, method)
        local original = _G[className][methodName]
        _G[className][methodName] = method
        return original
    end
    dofile(kServerFile)
end

local function SetShine(present)
    if present then
        Shine = { IsExtensionEnabled = function(self, name)
            if name == "basecommands" and Plugin then return PluginEnabled, Plugin end
            return false
        end }
    else
        Shine = nil
    end
end

local function Run(seconds)
    local stop = Now + seconds
    while Now < stop do
        Now = Now + 0.5
        Hooks.UpdateServer()
    end
end

local function EndRound()
    return NS2Gamerules.EndGame({}, 1)
end

local function AllTalk()
    return Plugin and Plugin.Config.AllTalk
end

-- ---------------------------------------------------------------------------------------------
-- Map load, round end

SetShine(true)
Plugin = NewPlugin(false)
Load()
Run(2)
check(AllTalk() == true and Notified == 1, "a map load turns all talk on and Shine says so")
check(Saved == 0, "not saved to Shine's config file")

Run(10)
check(Notified == 1, "only once per map")

-- An admin turns it off: the mod leaves it off until the round ends.
Plugin.Config.AllTalk = false
Run(10)
check(AllTalk() == false, "turned off by an admin: stays off during the round")
check(EndRound() == "ended" and Ended == 1, "the round still ends as usual")
check(AllTalk() == true and Notified == 2, "round end turns it on again")

-- Already on: nothing to say.
EndRound()
check(AllTalk() == true and Notified == 2, "already on at round end: no second line")

-- Never turned off.
Run(60)
check(AllTalk() == true, "the mod never turns it off")

-- Already on at map load (the admin left it on in Shine's config): no line.
Plugin = NewPlugin(true)
Notified = 0
Load()
Run(2)
check(AllTalk() == true and Notified == 0, "already on at map load: no line")

-- ---------------------------------------------------------------------------------------------
-- Shine's plugin enables late

Plugin = NewPlugin(false)
PluginEnabled = false
Notified = 0
Now = 0
Load()
Run(5)
check(AllTalk() == false, "plugin not enabled yet: nothing")
PluginEnabled = true
Run(2)
check(AllTalk() == true and Notified == 1, "turned on once the plugin enables")

-- Never enables: gives up quietly.
PluginEnabled = false
Plugin = NewPlugin(false)
Now = 0
Load()
Run(70)
PluginEnabled = true
Run(5)
check(AllTalk() == false, "after 60 s without the plugin, the map load leaves it alone")
EndRound()
check(AllTalk() == true, "the round end still turns it on")

-- ---------------------------------------------------------------------------------------------
-- Left alone

-- Thunderdome.
Thunderdome = true
Plugin = NewPlugin(false)
Now = 0
Load()
Run(2)
EndRound()
check(AllTalk() == false, "Thunderdome: left alone")
Thunderdome = false

-- No Shine.
SetShine(false)
Now = 0
Load()
Run(2)
check(EndRound() == "ended", "without Shine: nothing breaks")
SetShine(true)

-- Switched off.
Files["SSM_AllTalk.json"] = { Enabled = false }
Plugin = NewPlugin(false)
Now = 0
Load()
Run(2)
EndRound()
check(AllTalk() == false, "Enabled false: left alone")

print(string.format("%d passed, %d failed", passes, failures))
os.exit(failures == 0 and 0 or 1)
