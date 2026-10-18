-- Matches In A Row - post hook on lua/GUIScoreboard.lua.
--
-- Runs after whichever GUIScoreboard.lua loaded (vanilla, or a replacement such as Devnull's
-- Enhanced ScoreBoard), and only wraps methods and row fields both of them have.

-- The tag's own text item, made like both scoreboards make the name item so the two line up.
-- A child of the row background, so it is hidden and destroyed along with the row.
local function GetTagItem(row)
    local tagItem = row.SSMTag
    if tagItem then
        return tagItem
    end

    tagItem = GUIManager:CreateTextItem()
    tagItem:SetFontName(GUIScoreboard.kPlayerStatsFontName)
    tagItem:SetScale(Vector(1, 1, 1) * GUIScoreboard.kScalingFactor)
    GUIMakeFontScale(tagItem)
    tagItem:SetAnchor(GUIItem.Left, GUIItem.Center)
    tagItem:SetTextAlignmentX(GUIItem.Align_Min)
    tagItem:SetTextAlignmentY(GUIItem.Align_Center)
    tagItem:SetColor(SSM_MatchesInARow.kTagColor)
    tagItem:SetStencilFunc(GUIItem.NotEqual)
    row.Background:AddChild(tagItem)

    row.SSMTag = tagItem
    return tagItem
end

-- By now the scoreboard has positioned and, if needed, shortened the tagged name. Move the tag
-- into its own gray item where the name started, and the name to just after it. Both scoreboards
-- set the name's text and position on every pass, so this never builds up.
--
-- Rows are pooled and recycled between teams, so every row is touched on every pass.
local function SplitTags(playerList)
    for _, row in ipairs(playerList) do
        local nameItem = row.Name
        if nameItem and row.Background then
            local tag = SSM_MatchesInARow.GetTag(row.ClientIndex)
            local text = nameItem:GetText()

            -- A name so long that shortening it cut into the tag simply keeps the tag inline.
            if tag and string.sub(text, 1, #tag) == tag then
                local tagItem = GetTagItem(row)
                local position = nameItem:GetPosition()
                local width = nameItem:GetTextWidth(tag) * GUIScoreboard.kScalingFactor

                tagItem:SetText(tag)
                tagItem:SetPosition(position)
                tagItem:SetIsVisible(true)

                nameItem:SetText(string.sub(text, #tag + 1))
                nameItem:SetPosition(position + Vector(width, 0, 0))
            elseif row.SSMTag then
                row.SSMTag:SetIsVisible(false)
            end
        end
    end
end

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

    if updateTeam.PlayerList then
        SplitTags(updateTeam.PlayerList)
    end

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
