-- Matches In A Row - post hook on lua/GUIScoreboard.lua.
--
-- Runs after whichever GUIScoreboard.lua loaded (vanilla, or a replacement such as Devnull's
-- Enhanced ScoreBoard), and only wraps methods both of them have.

local oldInitialize = GUIScoreboard.Initialize
function GUIScoreboard:Initialize(...)
    oldInitialize(self, ...)

    -- Every team's rows are built from its GetScores function, so tagging its result tags the
    -- names before the scoreboard positions and shortens them.
    for _, team in ipairs(self.teams) do
        local getScores = team.GetScores
        if getScores then
            team.GetScores = function()
                return SSM_MatchesInARow.TagScores(getScores())
            end
        end
    end
end

local oldUpdateTeam = GUIScoreboard.UpdateTeam
function GUIScoreboard:UpdateTeam(updateTeam, ...)
    oldUpdateTeam(self, updateTeam, ...)

    -- Enhanced ScoreBoard writes the commander's name into the team header from the same records.
    -- The tag belongs on player rows only, so put the real name back there.
    local teamInfo = updateTeam.GUIs and updateTeam.GUIs.TeamInfo
    local commanderName = type(teamInfo) == "table" and teamInfo.teamComm
    if commanderName then
        local realName = SSM_MatchesInARow.GetRealName(commanderName:GetText())
        if realName then
            commanderName:SetText(realName)
        end
    end
end
