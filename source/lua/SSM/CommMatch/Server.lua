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
--   * Admins can ignore players by NS2 ID (author, 2026-11-19): some players never command but
--     carry a default commander skill. Ignored players are never listed; if one takes a chair,
--     the list still goes out as for anyone (the author's pick). The list is IgnoredPlayers in
--     config://SSM_CommMatch.json, read when the map loads.
--   * Off on Thunderdome by default (author, 2026-11-21): EnabledOnThunderdome (false) in the same
--     file turns it on there.
--   * !mycomm and !comm (v1.5, author 2026-11-27) send the same list to one player on request;
--     see the bottom of this file.
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

-- Settings: IgnoredPlayers is a list of NS2 IDs (numbers, or numbers written as text).
local kSettingsFile = "SSM_CommMatch.json"
local Settings = LoadConfigFile(kSettingsFile, { IgnoredPlayers = {}, EnabledOnThunderdome = false })
if type(Settings) ~= "table" then
    Settings = {}
end
local settingsChanged = false
if type(Settings.IgnoredPlayers) ~= "table" then
    Settings.IgnoredPlayers = {}
    settingsChanged = true
end
if type(Settings.EnabledOnThunderdome) ~= "boolean" then
    Settings.EnabledOnThunderdome = false
    settingsChanged = true
end
if settingsChanged then
    SaveConfigFile(kSettingsFile, Settings)
end

local function GetIsThunderdome()
    return Shared.GetThunderdomeEnabled ~= nil and Shared.GetThunderdomeEnabled() == true
end

local Ignored = {}   -- [NS2 ID] = true
for _, value in ipairs(Settings.IgnoredPlayers) do
    local ns2Id = tonumber(value)
    if ns2Id then
        Ignored[ns2Id] = true
    end
end

-- The player's client when it is a human who is not on the ignore list.
local function GetHumanClient(player)
    local client = Server.GetOwner(player)
    if client and not client:GetIsVirtual() then
        return client
    end
end

local function GetListedClient(player)
    local client = GetHumanClient(player)
    if client and not Ignored[client:GetUserId()] then
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

-- The closest players to `subject` commanding `team`, as rows ("1. Pepe  +12"), closest first.
-- Returns "no_skill" when the subject has never commanded, or an empty table when nobody else has.
local function GetRows(subject, team)
    local otherTeam = team == kTeam1Index and kTeam2Index or kTeam1Index

    local own = GetCommanderSkillFor(subject, team)
    if not own then
        return "no_skill"
    end

    local list = {}
    Server.ForAllPlayers(function(player)
        if player ~= subject and GetListedClient(player) then
            local skill = GetCommanderSkillFor(player, otherTeam)
            if skill then
                list[#list + 1] = { name = player:GetName(), gap = Round(skill - own) }
            end
        end
    end)

    table.sort(list, function(a, b)
        if math.abs(a.gap) ~= math.abs(b.gap) then
            return math.abs(a.gap) < math.abs(b.gap)
        end
        return a.name < b.name
    end)

    local rows = {}
    for i = 1, math.min(kListCount, #list) do
        local entry = list[i]
        rows[i] = string.format("%d. %s  %+d", i, entry.name, entry.gap)
    end
    return rows
end

-- The message lines, or nil when there is nothing to say.
function SSM_CommMatch_GetLines(commander)
    local team = commander:GetTeamNumber()
    local names = kTeamNames[team]
    if not names then
        return nil
    end

    local rows = GetRows(commander, team)
    if type(rows) ~= "table" or #rows == 0 then
        return nil
    end

    local lines = {
        { string.format("%s took %s commander. Closest %s commanders:", commander:GetName(), names.title, names.other) }
    }
    for _, row in ipairs(rows) do
        lines[#lines + 1] = { row, true }
    end

    return lines
end

-- Only before the round: not during the countdown, not once it has started.
local function IsPregame(gamerules)
    local state = gamerules:GetGameState()
    return state == kGameState.NotStarted or state == kGameState.WarmUp or state == kGameState.PreGame
end

local function OnCommanderLogin(commander, forced)
    -- Forced logins are the game putting commanders back in their chairs, above all when the
    -- round starts: ResetGame rebuilds the map and logs both commanders in again while the state
    -- is still PreGame (fixed in 1.1b; 1.1 posted the list again at round start).
    if forced then
        return
    end

    if GetIsThunderdome() and not Settings.EnabledOnThunderdome then
        return
    end

    if not (commander and commander.isa and commander:isa("Commander")) then
        return
    end

    local gamerules = GetGamerules()
    if not gamerules or not IsPregame(gamerules) then
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
oldLoginPlayer = Class_ReplaceMethod("CommandStructure", "LoginPlayer", function(self, player, forced, ...)
    local commander = oldLoginPlayer(self, player, forced, ...)

    local ok, err = pcall(OnCommanderLogin, commander, forced)
    if not ok then
        Shared.Message("[NS2 SUD] Commander Match error: " .. tostring(err))
    end

    return commander
end)

-- Chat commands (v1.5, author 2026-11-27). Only the caller sees the answer, in their language,
-- at any point in the game. Off on Thunderdome like the rest of the feature.
--   !mycomm  the caller's own list: for their team's chair when they are on Marines or Aliens,
--            for both chairs from spectator or the ready room. It works for ignored players too.
--   !comm    the list again for whoever sits in a command chair, only when exactly one chair is
--            taken (bots count as a commander).

local kHeaderKeys = {
    [kTeam1Index] = { mine = "comm_mine_marine", seated = "comm_seated_marine" },
    [kTeam2Index] = { mine = "comm_mine_alien", seated = "comm_seated_alien" }
}

-- Sends one header and its rows, if there are any. True when something was sent.
local function SendRows(client, header, rows)
    if type(rows) ~= "table" or #rows == 0 then
        return false
    end
    SSM.Notify(client, header)
    for _, row in ipairs(rows) do
        SSM.Notify(client, row, true)
    end
    return true
end

local function IsOff(client, language)
    if GetIsThunderdome() and not Settings.EnabledOnThunderdome then
        SSM.Notify(client, SSM.Text(language, "comm_off"))
        return true
    end
    return false
end

SSM.AddChatCommand("mycomm", function(client)
    local language = SSM.LanguageOf(client)
    if IsOff(client, language) then
        return
    end

    local player = client and client:GetControllingPlayer()
    if not player then
        return
    end

    local team = player:GetTeamNumber()
    local teams = kTeamNames[team] and { team } or { kTeam1Index, kTeam2Index }

    local sent = false
    for _, side in ipairs(teams) do
        local rows = GetRows(player, side)
        if rows == "no_skill" then
            SSM.Notify(client, SSM.Text(language, "comm_no_skill"))
            return
        end
        sent = SendRows(client, SSM.Text(language, kHeaderKeys[side].mine), rows) or sent
    end
    if not sent then
        SSM.Notify(client, SSM.Text(language, "comm_nobody_listed"))
    end
end)
SSM.ListCommand("!mycomm", "cmd_mycomm")

SSM.AddChatCommand("comm", function(client)
    local language = SSM.LanguageOf(client)
    if IsOff(client, language) then
        return
    end

    local seated = {}
    Server.ForAllPlayers(function(player)
        if kTeamNames[player:GetTeamNumber()] and player:isa("Commander") then
            seated[#seated + 1] = player
        end
    end)

    if #seated == 0 then
        SSM.Notify(client, SSM.Text(language, "comm_no_chair"))
        return
    end
    if #seated > 1 then
        SSM.Notify(client, SSM.Text(language, "comm_both_chairs"))
        return
    end

    local commander = seated[1]
    local team = commander:GetTeamNumber()
    local rows = GetHumanClient(commander) and GetRows(commander, team) or "no_skill"
    if rows == "no_skill" then
        SSM.Notify(client, SSM.Text(language, "comm_seated_no_skill", commander:GetName()))
        return
    end
    if not SendRows(client, SSM.Text(language, kHeaderKeys[team].seated, commander:GetName()), rows) then
        SSM.Notify(client, SSM.Text(language, "comm_nobody_listed"))
    end
end)
SSM.ListCommand("!comm", "cmd_comm")
