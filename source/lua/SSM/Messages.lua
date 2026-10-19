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
-- Chat goes through Shine, which is what can color a line and send it to one player. Without
-- Shine nothing is sent.
--
-- Console: plain lines in the caller's own console, or the server console when there is no caller.

SSM = SSM or {}

local kPrefix = "[NS2 SUD]"
local kPrefixColor = { 255, 0, 255 }
local kTextColor = { 255, 255, 255 }

-- One chat line to one client only.
function SSM.Notify(client, text, continued)
    if not (client and Shine and Shine.NotifyDualColour) then
        return
    end

    Shine:NotifyDualColour(client,
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
