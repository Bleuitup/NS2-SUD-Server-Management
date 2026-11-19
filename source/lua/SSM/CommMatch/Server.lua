-- Commander Match - server side.
--
-- When someone takes the Marine or Alien command chair before the round has started, and the other
-- team has no commander yet, everyone gets a chat message listing the 5 players whose commander
-- skill for the other team is closest to the new commander's, with the gap:
--
--   [NS2 SUD] Bleu took Marine commander. Closest alien commanders:
--   1. Pepe  +12
--   2. LZZ  -35
--
-- Rules (the author's picks):
--   * Everyone sees it.
--   * Anyone connected can be on the list, whatever team they are on, the commander's own team
--     included. Bots never are.
--   * Players whose commander skill is exactly 0 (never commanded) are left out. A new commander
--     at 0 gets no message, since there is nothing to compare.
--   * Cooldown per player (author, 2026-11-19): at most one message every kCooldownSeconds for
--     the same commander, so hopping in and out of the chair does not flood chat. It does not
--     apply when that player switches side (Marine to Alien chair or back), and another player
--     taking a chair is never held back by it. Anything beyond that admins enforce by hand.
--   * Only the gap is shown, signed: + means that player is above the new commander.
--
-- Commander skill per team is the game's own: the Hive gives one commander skill plus an offset,
-- Marines are skill + offset and Aliens skill - offset (ScoringMixin:GetCommanderTeamSkill).
-- A Marine commander is compared with everyone's Alien commander skill, and the other way round.

local kListCount = 5
local kCooldownSeconds = 30

local kTeamNames = {
    [kTeam1Index] = { title = "Marine", other = "alien" },
    [kTeam2Index] = { title = "Alien", other = "marine" }
}

-- [steamId] = { time = Shared.GetTime(), team = team number } of that player's last message.
local LastPost = {}

local function GetHumanClient(player)
    local client = Server.GetOwner(player)
    if client and not client:GetIsVirtual() then
        return client
    end
end

-- The player's commander skill for one team, or nil for someone who has never commanded.
local function GetCommanderSkillFor(player, teamNumber)
    if not (player.GetCommanderSkill and player.GetCommanderSkillOffset) then
        return nil
    end

    local skill = player:GetCommanderSkill()
    if type(skill) ~= "number" or skill == 0 then
        return nil
    end

    local offset = player:GetCommanderSkillOffset() or 0
    if teamNumber == kTeam1Index then
        return skill + offset
    end
    return skill - offset
end

local function TeamHasHumanCommander(teamNumber)
    local found = false
    Server.ForAllPlayers(function(player)
        if not found and player:GetTeamNumber() == teamNumber and player:isa("Commander")
        and GetHumanClient(player) then
            found = true
        end
    end)
    return found
end

local function Round(value)
    return math.floor(value + 0.5)
end

-- The message lines, or nil when there is nothing to say.
function SSM_CommMatch_GetLines(commander)
    local team = commander:GetTeamNumber()
    local names = kTeamNames[team]
    if not names then
        return nil
    end
    local otherTeam = team == kTeam1Index and kTeam2Index or kTeam1Index

    local own = GetCommanderSkillFor(commander, team)
    if not own then
        return nil
    end

    local list = {}
    Server.ForAllPlayers(function(player)
        if player ~= commander and GetHumanClient(player) then
            local skill = GetCommanderSkillFor(player, otherTeam)
            if skill then
                list[#list + 1] = { name = player:GetName(), gap = Round(skill - own) }
            end
        end
    end)

    if #list == 0 then
        return nil
    end

    table.sort(list, function(a, b)
        if math.abs(a.gap) ~= math.abs(b.gap) then
            return math.abs(a.gap) < math.abs(b.gap)
        end
        return a.name < b.name
    end)

    local lines = {
        { string.format("%s took %s commander. Closest %s commanders:", commander:GetName(), names.title, names.other) }
    }
    for i = 1, math.min(kListCount, #list) do
        local entry = list[i]
        lines[#lines + 1] = { string.format("%d. %s  %+d", i, entry.name, entry.gap), true }
    end

    return lines
end

local function OnCommanderLogin(commander)
    if not (commander and commander.isa and commander:isa("Commander")) then
        return
    end

    local gamerules = GetGamerules()
    if not gamerules or gamerules:GetGameStarted() then
        return
    end

    local client = GetHumanClient(commander)
    if not client then
        return
    end

    local team = commander:GetTeamNumber()
    if not kTeamNames[team] then
        return
    end

    -- Per player, and only for the same side: switching chairs is never held back.
    local steamId = client:GetUserId()
    local now = Shared.GetTime()
    local last = LastPost[steamId]
    if last and last.team == team and now - last.time < kCooldownSeconds then
        return
    end
    if TeamHasHumanCommander(team == kTeam1Index and kTeam2Index or kTeam1Index) then
        return
    end

    local lines = SSM_CommMatch_GetLines(commander)
    if not lines then
        return
    end

    LastPost[steamId] = { time = now, team = team }
    for _, line in ipairs(lines) do
        SSM.NotifyAll(line[1], line[2])
    end
end

-- Post-wrap of the login itself, which returns the new Commander entity. CommandStation overrides
-- LoginPlayer but calls CommandStructure.LoginPlayer inside, so both chairs pass through here.
-- An error in this feature must never break a login, hence the pcall.
local oldLoginPlayer
oldLoginPlayer = Class_ReplaceMethod("CommandStructure", "LoginPlayer", function(self, ...)
    local commander = oldLoginPlayer(self, ...)

    local ok, err = pcall(OnCommanderLogin, commander)
    if not ok then
        Shared.Message("[NS2 SUD] Commander Match error: " .. tostring(err))
    end

    return commander
end)
