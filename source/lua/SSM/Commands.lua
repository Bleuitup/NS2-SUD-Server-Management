-- NS2 SUD Server Admin - the chat commands of every feature, and the mod's own: !help, !lang.
--
-- Chat commands are caught through Shine's PlayerSay hook, not as Shine commands: Shine logs every
-- command it runs to the admins' consoles ("X ran command ..."), and this way nobody else even
-- sees the typed command (returning "" drops the message). Each command works with ! or /.
-- Shine is another mod and the order mods load in is not guaranteed, so the hook goes in on the
-- first server update rather than when this file loads.
--
-- Features add their commands with SSM.AddChatCommand and list them (chat and console ones) for
-- !help with SSM.ListCommand, in the order they should be shown.

local ChatCommands = {}   -- [word without ! or /] = function(client, args)
local Listed = {}         -- { usage, descriptionKey, isConsole } in display order

function SSM.AddChatCommand(word, handler)
    ChatCommands[string.lower(word)] = handler
end

function SSM.ListCommand(usage, descriptionKey, isConsole)
    Listed[#Listed + 1] = { usage = usage, key = descriptionKey, isConsole = isConsole }
end

local function OnPlayerSay(client, message)
    local text = message and message.message
    if type(text) ~= "string" then
        return
    end

    local word, args = text:match("^%s*[!/](%S+)%s*(.-)%s*$")
    local handler = word and ChatCommands[string.lower(word)]
    if not handler then
        return
    end

    -- A handler returns false to leave the message alone: it is shown in chat as usual, and other
    -- mods' commands of the same name (Shine's tournament mode !ready) are not disturbed.
    if handler(client, args) == false then
        return
    end
    return ""
end

local chatHooked = false
Event.Hook("UpdateServer", function()
    if chatHooked then
        return
    end
    chatHooked = true

    if Shine and Shine.Hook and Shine.Hook.Add then
        Shine.Hook.Add("PlayerSay", "SSM_Chat", OnPlayerSay)
    end
end)

-- !help: says so in chat, lists everything in the caller's console.
function SSM_GetCommandLines(language)
    local lines = { SSM.Text(language, "commands_header") }
    for _, command in ipairs(Listed) do
        local tag = SSM.Text(language, command.isConsole and "commands_console_tag" or "commands_chat_tag")
        lines[#lines + 1] = string.format("  %-14s (%s)  %s", command.usage, tag, SSM.Text(language, command.key))
    end
    return lines
end

SSM.AddChatCommand("help", function(client)
    local language = SSM.LanguageOf(client)
    SSM.Notify(client, SSM.Text(language, "commands_chat"))
    for _, line in ipairs(SSM_GetCommandLines(language)) do
        SSM.Print(client, line)
    end
end)
SSM.ListCommand("!help", "cmd_help")

-- !lang es / pt / en. "br" is taken as Portuguese. Anything else shows how to use it.
local kLanguageWords = { en = "en", es = "es", pt = "pt", br = "pt" }

SSM.AddChatCommand("lang", function(client, args)
    local language = kLanguageWords[string.lower(args or "")]
    if language then
        SSM.SetLanguage(client, language)
        SSM.Notify(client, SSM.Text(language, "lang_set"))
    else
        SSM.Notify(client, SSM.Text(SSM.LanguageOf(client), "lang_usage"))
    end
end)
SSM.ListCommand("!lang", "cmd_lang")
