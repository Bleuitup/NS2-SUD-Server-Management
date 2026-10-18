-- Matches In A Row - client side.
--
-- Keeps the counts the server sends and puts them in front of names on the scoreboard, as
-- "[3r 95m] Name": 3 rounds in a row, 95 minutes played over them, the tag in light gray.
-- Players at 0 show no tag, and nobody shows one while a round is being played: the tag is for
-- deciding who spectates, which happens between rounds.
--
-- The tag first goes into the name itself, in a copy of the score records the scoreboard reads
-- (see GUIScoreboard.lua next to this file). That way the scoreboard lays out and shortens the
-- tagged name exactly as it would any long name, whether it is vanilla's or a replacement such as
-- Devnull's Enhanced ScoreBoard. After the scoreboard is done with a row, the tag is split back
-- off into its own gray text item. The cached records themselves are never changed.

SSM_MatchesInARow = {}

SSM_MatchesInARow.kTagColor = Color(0.7, 0.7, 0.7, 1)

-- [steamId] = "[3r 95m] "
local Tags = {}

-- [tagged name] = real name, for the places the scoreboard compares names (see below). Never
-- cleared: Enhanced ScoreBoard keeps the last commander's name across rounds, and that copy can
-- still carry last round's tag. A few entries per round is nothing.
local RealNames = {}

Client.HookNetworkMessage("SSM_MatchesInARowClear", function()
    Tags = {}
end)

Client.HookNetworkMessage("SSM_MatchesInARow", function(message)
    Tags[message.steamId] = string.format("[%dr %dm] ", message.rounds, message.minutes)
end)

local function IsRoundBeingPlayed()
    local gameInfo = GetGameInfoEntity()
    return gameInfo ~= nil and gameInfo:GetState() == kGameState.Started
end

function SSM_MatchesInARow.GetRealName(name)
    return name and RealNames[name]
end

-- The tag to show for a scoreboard row right now, or nil.
function SSM_MatchesInARow.GetTag(clientIndex)
    if IsRoundBeingPlayed() then
        return nil
    end

    -- nil until that player's PlayerInfoEntity has arrived, which just means no tag yet.
    local steamId = clientIndex and GetSteamIdForClientIndex(clientIndex)
    return steamId and Tags[steamId]
end

-- Returns the score list with tagged copies of every record that has a tag to show. Returns the
-- same list untouched when nobody on it has one.
function SSM_MatchesInARow.TagScores(scores)
    local tagged

    for i = 1, #scores do
        local record = scores[i]
        local tag = SSM_MatchesInARow.GetTag(record.ClientIndex)

        if tag and record.Name then
            if not tagged then
                tagged = {}
                for j = 1, #scores do
                    tagged[j] = scores[j]
                end
            end

            local copy = {}
            for key, value in pairs(record) do
                copy[key] = value
            end
            copy.Name = tag .. record.Name

            RealNames[copy.Name] = record.Name
            tagged[i] = copy
        end
    end

    return tagged or scores
end

-- The scoreboard finds the local player's row (to highlight it) by comparing the row's name with
-- the local player's real name, so it has to be handed the real name back.
if ScoreboardUI_IsPlayerLocal then
    local oldIsPlayerLocal = ScoreboardUI_IsPlayerLocal
    function ScoreboardUI_IsPlayerLocal(playerName)
        return oldIsPlayerLocal(RealNames[playerName] or playerName)
    end
end
