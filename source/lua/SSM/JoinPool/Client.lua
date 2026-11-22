-- Join Pool - client side.
--
-- Two things the server cannot do on its own:
--   * The scoreboard: players in the join pool show "SUD Queue" in the status column of the
--     spectator / ready room block, where it would otherwise say "Spectator" (or nothing).
--   * The taskbar: when a player is asked to type !readyq, their game window flashes, the same
--     call the game makes when a round is about to start (Client.WindowNeedsAttention).

local kLabel = "SUD Queue"

local Queued = {}   -- [client index] = true

Client.HookNetworkMessage("SSM_JoinPoolQueue", function(message)
    Queued = {}
    for id in string.gmatch(message.clients or "", "%d+") do
        Queued[tonumber(id)] = true
    end
end)

Client.HookNetworkMessage("SSM_JoinPoolAttention", function()
    if Client.WindowNeedsAttention then
        Client.WindowNeedsAttention()
    end
end)

-- The scoreboard class only exists once the game's GUI scripts are loaded, and other mods may
-- rewrite the same status column, so the wrap goes in on the first client update after the class
-- exists, after the others.
local function LabelQueued(updateTeam, scores)
    if updateTeam.TeamNumber ~= kTeamReadyRoom or not next(Queued) then
        return
    end
    local rows = updateTeam.PlayerList
    scores = scores or (updateTeam.GetScores and updateTeam.GetScores())
    if not (rows and scores) then
        return
    end
    for i, record in ipairs(scores) do
        local row = rows[i]
        if not row then
            return
        end
        if row.Status and Queued[record.ClientIndex] then
            row.Status:SetText(kLabel)
        end
    end
end

local hooked = false
Event.Hook("UpdateClient", function()
    if hooked or not GUIScoreboard then
        return
    end
    hooked = true

    local oldUpdateTeam
    oldUpdateTeam = Class_ReplaceMethod("GUIScoreboard", "UpdateTeam", function(self, updateTeam, scores, ...)
        local a, b, c = oldUpdateTeam(self, updateTeam, scores, ...)
        local ok, err = pcall(LabelQueued, updateTeam, scores)
        if not ok then
            Shared.Message("[NS2 SUD] Join Pool scoreboard: " .. tostring(err))
        end
        return a, b, c
    end)
end)
