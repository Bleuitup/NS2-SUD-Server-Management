-- NS2 SUD Server Admin - how every feature talks to players.
--
-- Chat: the mod speaks as one voice, "[NS2 SUD]" in magenta (the same magenta as Hive Spawn
-- Selector's tag), with the message in white. Magenta is neither team's color and stands out from
-- normal chat. Every feature uses this one prefix, so players learn a single "server" voice; when
-- it matters which feature is talking, the message text says so.
--
-- In a block of lines only the headers carry the prefix; the rows under them pass `continued`, so
-- a list does not repeat the tag on every row.
--
-- Chat goes through Shine, which is what can color a line and send it to one player or to all.
-- Without Shine nothing is sent, except lines sent with `always` (the pause and saved players,
-- which must work on Thunderdome servers too): those fall back to the game's own chat.
--
-- Console: plain lines in the caller's own console, or the server console when there is no caller.
--
-- Language: messages sent to one player (chat and console) are in that player's language:
-- English, Spanish or Portuguese. The server cannot see the game's language setting (it stays on
-- the player's machine), so players pick it with !lang, remembered per Steam ID in
-- config://SSM_Languages.json. English until they do. Messages to everyone stay in English. The
-- texts themselves are in Strings.lua.

SSM = SSM or {}
SSM.Strings = SSM.Strings or { en = {}, es = {}, pt = {} }

local kPrefix = "[NS2 SUD]"
local kPrefixColor = { 255, 0, 255 }
local kTextColor = { 255, 255, 255 }

local kLanguagesFile = "SSM_Languages.json"
SSM.kLanguages = { "en", "es", "pt" }

-- Without Shine (Thunderdome servers, for example), the features that must work there anyway
-- (the pause, saved players) use the game's own chat: plain colors, "[NS2 SUD]" as the name.
local function SendPlainChat(target, text)
    if not (Server.SendNetworkMessage and BuildChatMessage) then
        return
    end
    local message = BuildChatMessage(false, kPrefix, -1, kTeamReadyRoom, kNeutralTeamType, text)
    if target then
        Server.SendNetworkMessage(target, "Chat", message, true)
    else
        Server.SendNetworkMessage("Chat", message, true)
    end
end

-- One chat line to one client only. `always` sends it without Shine too (game chat).
function SSM.Notify(client, text, continued, always)
    if not client then
        return
    end
    if not (Shine and Shine.NotifyDualColour) then
        if always then
            local player = client:GetControllingPlayer()
            if player then
                SendPlainChat(player, text)
            end
        end
        return
    end

    Shine:NotifyDualColour(client,
        kPrefixColor[1], kPrefixColor[2], kPrefixColor[3], continued and "" or kPrefix,
        kTextColor[1], kTextColor[2], kTextColor[3], text)
end

-- One chat line to everyone on the server (Shine sends to all when the target is nil).
function SSM.NotifyAll(text, continued, always)
    if not (Shine and Shine.NotifyDualColour) then
        if always then
            SendPlainChat(nil, text)
        end
        return
    end

    Shine:NotifyDualColour(nil,
        kPrefixColor[1], kPrefixColor[2], kPrefixColor[3], continued and "" or kPrefix,
        kTextColor[1], kTextColor[2], kTextColor[3], text)
end

-- One line in the client's console.
function SSM.Print(client, text)
    if client then
        ServerAdminPrint(client, text)
    else
        Shared.Message(text)
    end
end

-- Languages ----------------------------------------------------------------------------------

-- [tostring(steamId)] = "es" / "pt". English is the default and is not stored.
local Languages = LoadConfigFile(kLanguagesFile)
if type(Languages) ~= "table" then
    Languages = {}
end

local function SteamIdOf(client)
    if client and not client:GetIsVirtual() then
        local steamId = client:GetUserId()
        if steamId and steamId > 0 then
            return steamId
        end
    end
end

-- The client's language code; English for the server console, bots and anyone who has not picked.
function SSM.LanguageOf(client)
    local steamId = SteamIdOf(client)
    local language = steamId and Languages[tostring(steamId)]
    if language and SSM.Strings[language] then
        return language
    end
    return "en"
end

function SSM.SetLanguage(client, language)
    local steamId = SteamIdOf(client)
    if not steamId then
        return
    end

    Languages[tostring(steamId)] = language ~= "en" and language or nil
    SaveConfigFile(kLanguagesFile, Languages)
end

-- A text in the given language (falling back to English), formatted with any extra arguments.
function SSM.Text(language, key, ...)
    local text = SSM.Strings[language] and SSM.Strings[language][key] or SSM.Strings.en[key] or key
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end
