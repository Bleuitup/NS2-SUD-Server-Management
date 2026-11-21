-- Join Pool - server side.
--
-- During a live 6v6 or 7v7 round, spectators and ready-room players type !joinq to wait for a
-- place. When two of them can join, one per team, and keep the average elo gap within the limit,
-- both are asked to type !ready within 30 seconds; once both have, they are put on the teams that
-- keep the gap smallest. It replaces admins pairing joiners by hand. The work started as the
-- balanced queue of Lockteams v2 2.3 (never released), which is where the pair maths comes from.
--
-- Rules (the author's picks, 2026-11-21):
--   * Only during a live round (state Started): typing !joinq and then !ready shows the player is
--     actually there. The pool is cleared when the round ends or resets.
--   * Only when the teams are exactly 6v6 or 7v7 (TeamSizes). Uneven teams are left alone: they
--     usually mean someone crashed, and Saved Players then holds their body, which a joiner would
--     take over. Any held body (or bot) on a team pauses the pool the same way.
--   * Team averages: fielders at their field skill for that team, the commander at their
--     commander skill for that team (the game's own formulas). Joiners come in as fielders.
--   * The gap after the pair joins must be within MaxDifference (75), or, when the game is already
--     further apart than that, smaller than it is now.
--   * Of all possible pairs, both ways round, the one with the smallest gap afterwards is picked.
--     Queue order only breaks ties.
--   * Everyone else gets one line naming the pair and the gap before and after; each of the two
--     gets a private line, and their game window flashes on the taskbar (client part).
--   * No pair before 30 s into the round (OfferDelaySeconds; author, 2026-11-21): !joinq works from
--     the start, but the best pair of everyone who asked is picked then, so it is not a race to
--     type !joinq first.
--   * 30 s to type !ready (ReadySeconds). Whoever does not leaves the pool; whoever did stays.
--     When both are ready, the pair is checked again against the teams as they are then.
--   * Lockteams is required (author, 2026-11-21): the pool only runs while Lockteams v2 is loaded
--     and the teams are locked, because with open teams people come and go and break the pairing.
--     !joinq is refused otherwise. If the teams are unlocked mid-round the pool is kept but paused
--     (members are told once, a pending pair is cancelled) until they are locked again. For the
--     two joins the lock is lifted and put straight back, silently.
--   * Queued players are shielded from Shine's AFK kick while they wait (the !ready deadline
--     catches anyone who walked away).
--   * Off on Thunderdome by default (author, 2026-11-21): EnabledOnThunderdome (false) turns it on
--     there; an admin's sud_joinpool on turns it on for the round.
--   * Commands: !joinq, !exitq, !listq, !ready; sud_joinpool on|off for admins (this round only).
--   * The scoreboard shows "SUD Queue" in the status column of queued players (client part).

local kConfigFile = "SSM_JoinPool.json"
local kDefaultConfig = {
    Enabled = true,
    -- Off on Thunderdome unless this is true (an admin's sud_joinpool on still works there).
    EnabledOnThunderdome = false,
    MaxDifference = 75,
    ReadySeconds = 30,
    -- No pair is offered before this many seconds into the round, so the first two to type !joinq
    -- do not get in just for being first; the best pair of everyone who asked is picked then.
    OfferDelaySeconds = 30,
    TeamSizes = { 6, 7 }
}
-- How often the pool is looked at, and how often the queued list is re-sent to every client
-- (so players who connect later get it too).
local kEvaluateSeconds = 1
local kBroadcastSeconds = 5
local kAFKShieldSeconds = 10

local function Log(text)
    Shared.Message("[NS2 SUD] Join Pool: " .. text)
end

-- Config ------------------------------------------------------------------------------------

local Config = LoadConfigFile(kConfigFile)
if type(Config) ~= "table" then
    Config = {}
end
local configChanged = false
for key, value in pairs(kDefaultConfig) do
    if Config[key] == nil then
        Config[key] = value
        configChanged = true
    end
end
if configChanged then
    SaveConfigFile(kConfigFile, Config)
end

local function IsAllowedSize(size)
    for _, allowed in ipairs(Config.TeamSizes or {}) do
        if allowed == size then
            return true
        end
    end
    return false
end

-- State -------------------------------------------------------------------------------------

local Pool = {}           -- { steamId, since } in the order they asked
local Proposal = nil      -- the pair asked to type !ready
local offThisRound = false
local onThisRound = false    -- an admin's sud_joinpool on: lifts the Thunderdome default this round
local lastEvaluate, lastBroadcast, lastShield = -math.huge, -math.huge, -math.huge
local poolChanged = true
local roundStartedAt = nil   -- Shared.GetTime() when the current round went live

-- Still inside the round-start wait (OfferDelaySeconds): seconds left, or nil.
local function OfferWaitLeft()
    if not roundStartedAt then
        return nil
    end
    local left = (Config.OfferDelaySeconds or 0) - (Shared.GetTime() - roundStartedAt)
    return left > 0 and left or nil
end

local function SteamIdOf(client)
    if client and not client:GetIsVirtual() then
        local steamId = client:GetUserId()
        if steamId and steamId > 0 then
            return steamId
        end
    end
end

local function FindClient(steamId)
    local found
    Server.ForAllPlayers(function(player)
        local client = Server.GetOwner(player)
        if not found and SteamIdOf(client) == steamId then
            found = client
        end
    end)
    return found
end

local function PoolIndex(steamId)
    for i, entry in ipairs(Pool) do
        if entry.steamId == steamId then
            return i
        end
    end
end

local function RemoveFromPool(steamId)
    local index = PoolIndex(steamId)
    if index then
        table.remove(Pool, index)
        poolChanged = true
        return true
    end
    return false
end

local function IsBench(team)
    return team == kTeamReadyRoom or team == kSpectatorIndex
end

local function IsLive()
    local gamerules = GetGamerules and GetGamerules()
    return gamerules ~= nil and gamerules:GetGameStarted()
end

-- "missing" when Lockteams v2 is not loaded or not enabled, "open" when its teams are not locked,
-- "locked" otherwise.
local function LockState()
    local lockTeams = Shine and Shine.Plugins and Shine.Plugins.lockteamsv2
    if not (lockTeams and lockTeams.Enabled) then
        return "missing"
    end
    return lockTeams.TeamLock and "locked" or "open"
end

local function Say(client, key, ...)
    SSM.Notify(client, SSM.Text(SSM.LanguageOf(client), key, ...))
end

-- One line to every connected player in their own language, except the ones in `skip`.
local function SayToEveryone(skip, key, argsFor)
    Server.ForAllPlayers(function(player)
        local client = Server.GetOwner(player)
        local steamId = SteamIdOf(client)
        if steamId and not (skip and skip[steamId]) then
            local language = SSM.LanguageOf(client)
            SSM.Notify(client, SSM.Text(language, key, argsFor(language)))
        end
    end)
end

-- Skill -------------------------------------------------------------------------------------

-- A fielder's skill for a team: the game's ScoringMixin:GetPlayerTeamSkill, computed from the raw
-- fields so it works for players who are not on that team yet.
local function FieldSkill(player, team)
    if not (player.GetPlayerSkill and player.GetPlayerSkillOffset) then
        return nil
    end
    local skill = player:GetPlayerSkill()
    local offset = player:GetPlayerSkillOffset() or 0
    if type(skill) ~= "number" then
        return nil
    end
    return team == kTeam1Index and skill + offset or skill - offset
end

-- What a player on a team counts for: commanders at their commander skill for that team
-- (ScoringMixin:GetCommanderTeamSkill), everyone else at their field skill.
local function TeamMemberSkill(player, team)
    if player.isa and player:isa("Commander") and player.GetCommanderTeamSkill then
        return player:GetCommanderTeamSkill()
    end
    return FieldSkill(player, team)
end

-- { size, total } for a team, or nil when it cannot be judged (a held body, a bot, no skill).
local function ReadTeam(gamerules, teamNumber)
    local team = gamerules:GetTeam(teamNumber)
    if not team then
        return nil
    end
    local info = { size = 0, total = 0 }
    local ok = true
    team:ForEachPlayer(function(player)
        local client = Server.GetOwner(player)
        if not client or client:GetIsVirtual() then
            ok = false
            return
        end
        local skill = TeamMemberSkill(player, teamNumber)
        if not skill then
            ok = false
            return
        end
        info.size = info.size + 1
        info.total = info.total + skill
    end)
    return ok and info or nil
end

-- The gap is always marines minus aliens.
local function Gap(marines, aliens, marineAdd, alienAdd)
    local m = (marines.total + (marineAdd or 0)) / (marines.size + (marineAdd and 1 or 0))
    local a = (aliens.total + (alienAdd or 0)) / (aliens.size + (alienAdd and 1 or 0))
    return m - a
end

-- "+75 Marines", "+20 Aliens" or "0", in the given language.
local function FormatGap(language, gap)
    local rounded = math.floor(math.abs(gap) + 0.5)
    if rounded == 0 then
        return "0"
    end
    return string.format("+%d %s", rounded, SSM.Text(language, gap > 0 and "team_marines" or "team_aliens"))
end
SSM.JoinPool_FormatGap = FormatGap

-- Whether a pair moving the gap from `before` to `after` is allowed.
local function IsAcceptable(before, after)
    local limit = Config.MaxDifference
    return math.abs(after) <= limit or (math.abs(before) > limit and math.abs(after) < math.abs(before))
end

-- Player slots: someone in the ready room already holds one; a spectator needs a free one, and
-- without reserved-slot access cannot use the reserved ones (vanilla GetCanJoinPlayingTeam, checked
-- here so a failed check does not pop a join error on the player's screen).
local function FreeSlots()
    local free = Server.GetMaxPlayers() - (Server.GetNumClientsTotal() - Server.GetNumSpectators())
    local reserved = Server.GetReservedSlotLimit and Server.GetReservedSlotLimit() or 0
    return free, free - reserved
end

local function CanSeat(candidates)
    local free, freeUnreserved = FreeSlots()
    local needed, neededUnreserved = 0, 0
    for _, candidate in ipairs(candidates) do
        if candidate.needsSlot then
            needed = needed + 1
            if not candidate.reserved then
                neededUnreserved = neededUnreserved + 1
            end
        end
    end
    return needed <= free and neededUnreserved <= freeUnreserved
end

-- The pool members who can be placed right now, in queue order.
local function Candidates()
    local list = {}
    for index, entry in ipairs(Pool) do
        local client = FindClient(entry.steamId)
        local player = client and client:GetControllingPlayer()
        if player and IsBench(player:GetTeamNumber()) then
            local marine, alien = FieldSkill(player, kTeam1Index), FieldSkill(player, kTeam2Index)
            if marine and alien then
                list[#list + 1] = {
                    steamId = entry.steamId, index = index, client = client, player = player,
                    marine = marine, alien = alien,
                    needsSlot = client:GetIsSpectator(),
                    reserved = GetHasReservedSlotAccess and GetHasReservedSlotAccess(entry.steamId) and true or false
                }
            end
        end
    end
    return list
end

local function GetIsThunderdome()
    return Shared.GetThunderdomeEnabled ~= nil and Shared.GetThunderdomeEnabled() == true
end

-- nil when the pool is on; "off" (config or an admin, this round) or "thunderdome" otherwise.
local function OffReason()
    if not Config.Enabled or offThisRound then
        return "off"
    end
    if GetIsThunderdome() and Config.EnabledOnThunderdome ~= true and not onThisRound then
        return "thunderdome"
    end
    return nil
end

-- The teams as they stand, if the pool may run now: live round, switched on, both teams the same
-- allowed size, nobody held or a bot. Returns marines, aliens or nil.
local function CurrentTeams()
    if OffReason() or not IsLive() or LockState() ~= "locked" then
        return nil
    end
    local gamerules = GetGamerules()
    local marines, aliens = ReadTeam(gamerules, kTeam1Index), ReadTeam(gamerules, kTeam2Index)
    if not (marines and aliens) or marines.size ~= aliens.size or not IsAllowedSize(marines.size) then
        return nil
    end
    return marines, aliens
end

-- The best way round for two candidates: marine, alien, gap after.
local function BestOrientation(first, second, marines, aliens)
    local gapA = Gap(marines, aliens, first.marine, second.alien)
    local gapB = Gap(marines, aliens, second.marine, first.alien)
    if math.abs(gapB) < math.abs(gapA) then
        return second, first, gapB
    end
    return first, second, gapA
end

-- The pair leaving the smallest gap, if it is allowed. Ties go to whoever has waited longest.
local function FindBestPair(marines, aliens)
    local list = Candidates()
    local before = Gap(marines, aliens)
    local best
    for i = 1, #list - 1 do
        for j = i + 1, #list do
            local first, second = list[i], list[j]
            if CanSeat({ first, second }) then
                local marine, alien, after = BestOrientation(first, second, marines, aliens)
                local better = not best or math.abs(after) < math.abs(best.after) - 1e-9
                    or (math.abs(math.abs(after) - math.abs(best.after)) <= 1e-9 and i + j < best.order)
                if better then
                    best = { marine = marine, alien = alien, after = after, order = i + j }
                end
            end
        end
    end
    if best and IsAcceptable(before, best.after) then
        best.before = before
        return best
    end
end

-- Network: who is queued (for the scoreboard) and the taskbar flash -------------------------

local function BroadcastQueue()
    local ids = {}
    for _, entry in ipairs(Pool) do
        local client = FindClient(entry.steamId)
        if client then
            ids[#ids + 1] = client:GetId()
        end
    end
    table.sort(ids)
    local encoded = #ids > 0 and ("," .. table.concat(ids, ",") .. ",") or ""
    Server.SendNetworkMessage("SSM_JoinPoolQueue", { clients = encoded }, true)
end

local function Flash(client)
    Server.SendNetworkMessage(client, "SSM_JoinPoolAttention", { seconds = Config.ReadySeconds }, true)
end

-- Lockteams ---------------------------------------------------------------------------------

-- Runs `fn` with Lockteams v2's lock lifted if it is on, and puts it back afterwards, even if `fn`
-- fails. Done on the plugin's flag rather than its lock/unlock commands, which would announce both.
local function WithTeamsUnlocked(fn)
    local lockTeams = Shine and Shine.Plugins and Shine.Plugins.lockteamsv2
    local relock = lockTeams and lockTeams.Enabled and lockTeams.TeamLock
    if relock then
        lockTeams.TeamLock = false
    end
    local ok, result = pcall(fn)
    if relock then
        lockTeams.TeamLock = true
    end
    if not ok then
        Log("placing the pair failed: " .. tostring(result))
        return false
    end
    return result
end

-- The proposal ------------------------------------------------------------------------------

local function ClearProposal()
    Proposal = nil
end

local function NamesOf(proposal)
    return proposal.marineName, proposal.alienName
end

local function Offer(pair)
    local seconds = Config.ReadySeconds
    Proposal = {
        marine = pair.marine.steamId, alien = pair.alien.steamId,
        marineName = pair.marine.player:GetName(), alienName = pair.alien.player:GetName(),
        before = pair.before, after = pair.after,
        ready = {}, expires = Shared.GetTime() + seconds
    }
    local marineName, alienName = NamesOf(Proposal)
    local skip = { [Proposal.marine] = true, [Proposal.alien] = true }

    SayToEveryone(skip, "joinpool_pair_public", function(language)
        return marineName, alienName, FormatGap(language, pair.before), FormatGap(language, pair.after), seconds
    end)

    local marineClient, alienClient = pair.marine.client, pair.alien.client
    Say(marineClient, "joinpool_pair_you", alienName, SSM.Text(SSM.LanguageOf(marineClient), "team_marines"), seconds)
    Say(alienClient, "joinpool_pair_you", marineName, SSM.Text(SSM.LanguageOf(alienClient), "team_aliens"), seconds)
    Flash(marineClient)
    Flash(alienClient)

    Log(string.format("offered %s (Marines) and %s (Aliens), gap %.0f -> %.0f", marineName, alienName, pair.before, pair.after))
end

-- Moves the pair in. Ready-room players first (they already hold a slot), then spectators.
local function Place(marineClient, alienClient)
    local gamerules = GetGamerules()
    local order = {
        { client = marineClient, team = kTeam1Index },
        { client = alienClient, team = kTeam2Index }
    }
    table.sort(order, function(a, b)
        return (a.client:GetIsSpectator() and 1 or 0) < (b.client:GetIsSpectator() and 1 or 0)
    end)

    return WithTeamsUnlocked(function()
        local placed = {}
        for _, step in ipairs(order) do
            local player = step.client:GetControllingPlayer()
            local fromTeam = player and player:GetTeamNumber()
            local joined = player and gamerules:JoinTeam(player, step.team)
            if not joined then
                -- Undo the first join so the teams are not left uneven.
                for _, done in ipairs(placed) do
                    local back = done.client:GetControllingPlayer()
                    if back then
                        gamerules:JoinTeam(back, done.fromTeam, true)
                    end
                end
                return false
            end
            placed[#placed + 1] = { client = step.client, fromTeam = fromTeam }
        end
        return true
    end)
end

-- Both typed !ready: check the pair again against the teams as they are now, then place them.
local function Complete()
    local proposal = Proposal
    ClearProposal()

    local marineClient, alienClient = FindClient(proposal.marine), FindClient(proposal.alien)
    local marines, aliens = CurrentTeams()
    local marinePlayer = marineClient and marineClient:GetControllingPlayer()
    local alienPlayer = alienClient and alienClient:GetControllingPlayer()

    local after, before
    if marines and marinePlayer and alienPlayer and IsBench(marinePlayer:GetTeamNumber()) and IsBench(alienPlayer:GetTeamNumber()) then
        local m, a = FieldSkill(marinePlayer, kTeam1Index), FieldSkill(alienPlayer, kTeam2Index)
        if m and a and CanSeat({
            { needsSlot = marineClient:GetIsSpectator(), reserved = GetHasReservedSlotAccess and GetHasReservedSlotAccess(proposal.marine) },
            { needsSlot = alienClient:GetIsSpectator(), reserved = GetHasReservedSlotAccess and GetHasReservedSlotAccess(proposal.alien) }
        }) then
            before = Gap(marines, aliens)
            after = Gap(marines, aliens, m, a)
        end
    end

    local marineName, alienName = NamesOf(proposal)

    if not after or not IsAcceptable(before, after) then
        for _, client in ipairs({ marineClient, alienClient }) do
            Say(client, "joinpool_cancel_you", Config.MaxDifference)
        end
        SayToEveryone({ [proposal.marine] = true, [proposal.alien] = true }, "joinpool_cancel_public", function()
            return marineName, alienName
        end)
        Log("pair no longer fits, cancelled")
        return
    end

    if not Place(marineClient, alienClient) then
        for _, client in ipairs({ marineClient, alienClient }) do
            Say(client, "joinpool_failed_you")
        end
        Log("pair could not be placed")
        return
    end

    RemoveFromPool(proposal.marine)
    RemoveFromPool(proposal.alien)

    SayToEveryone(nil, "joinpool_done", function(language)
        return marineName, alienName, FormatGap(language, after)
    end)
    Log(string.format("placed %s (Marines) and %s (Aliens), gap %.0f -> %.0f", marineName, alienName, before, after))
end

local function Expire()
    local proposal = Proposal
    ClearProposal()

    local marineName, alienName = NamesOf(proposal)
    local names = { [proposal.marine] = marineName, [proposal.alien] = alienName }
    local other = { [proposal.marine] = proposal.alien, [proposal.alien] = proposal.marine }
    local late = {}

    for _, steamId in ipairs({ proposal.marine, proposal.alien }) do
        local client = FindClient(steamId)
        if proposal.ready[steamId] then
            if client then
                Say(client, "joinpool_expired_other", names[other[steamId]])
            end
        else
            late[#late + 1] = names[steamId]
            RemoveFromPool(steamId)
            if client then
                Say(client, "joinpool_expired_you")
            end
        end
    end

    SayToEveryone({ [proposal.marine] = true, [proposal.alien] = true }, "joinpool_expired_public", function()
        return table.concat(late, ", ")
    end)
    Log("pair expired: " .. table.concat(late, ", "))
end

-- Keeps the pool honest: drops anyone who left the server or got on a team some other way.
local function Prune()
    for i = #Pool, 1, -1 do
        local client = FindClient(Pool[i].steamId)
        local player = client and client:GetControllingPlayer()
        if not (player and IsBench(player:GetTeamNumber())) then
            table.remove(Pool, i)
            poolChanged = true
        end
    end
end

local function ClearPool(notifyKey)
    if notifyKey then
        for _, entry in ipairs(Pool) do
            local client = FindClient(entry.steamId)
            if client then
                Say(client, notifyKey)
            end
        end
    end
    Pool = {}
    ClearProposal()
    poolChanged = true
end

local function ShieldFromAFKKick()
    local afkKick = Shine and Shine.Plugins and Shine.Plugins.afkkick
    if not (afkKick and afkKick.Enabled and afkKick.ResetAFKTime) then
        return
    end
    for _, entry in ipairs(Pool) do
        local client = FindClient(entry.steamId)
        if client then
            afkKick:ResetAFKTime(client, "NS2 SUD join pool")
        end
    end
end

-- Teams unlocked (or Lockteams gone) while people wait: keep them, cancel a pending pair, and
-- tell everyone in the pool once. Locked again: tell them the pool is running again.
local wasLocked = true
local function WatchLock()
    local locked = LockState() == "locked"
    if locked == wasLocked then
        return
    end
    wasLocked = locked
    if #Pool == 0 then
        return
    end
    if not locked and Proposal then
        ClearProposal()
    end
    for _, entry in ipairs(Pool) do
        local client = FindClient(entry.steamId)
        if client then
            Say(client, locked and "joinpool_relocked" or "joinpool_unlocked")
        end
    end
end

local function Evaluate()
    Prune()
    WatchLock()

    if Proposal then
        local stillThere = FindClient(Proposal.marine) and FindClient(Proposal.alien)
        if not stillThere then
            -- One of them left the server: whoever is still here stays in the pool.
            local proposal = Proposal
            ClearProposal()
            for _, steamId in ipairs({ proposal.marine, proposal.alien }) do
                local client = FindClient(steamId)
                if client then
                    Say(client, "joinpool_partner_left")
                end
            end
        elseif Shared.GetTime() >= Proposal.expires then
            Expire()
        end
        return
    end

    if #Pool < 2 or OfferWaitLeft() then
        return
    end
    local marines, aliens = CurrentTeams()
    if not marines then
        return
    end
    local pair = FindBestPair(marines, aliens)
    if pair then
        Offer(pair)
    end
end

Event.Hook("UpdateServer", function()
    local ok, err = pcall(function()
        local now = Shared.GetTime()

        if IsLive() then
            roundStartedAt = roundStartedAt or now
        else
            roundStartedAt = nil
        end

        if (#Pool > 0 or Proposal) and not IsLive() then
            ClearPool("joinpool_round_over")
        end

        if now - lastEvaluate >= kEvaluateSeconds then
            lastEvaluate = now
            Evaluate()
        end

        if poolChanged or now - lastBroadcast >= kBroadcastSeconds then
            poolChanged = false
            lastBroadcast = now
            BroadcastQueue()
        end

        if #Pool > 0 and now - lastShield >= kAFKShieldSeconds then
            lastShield = now
            ShieldFromAFKKick()
        end
    end)
    if not ok then
        Log("error: " .. tostring(err))
    end
end)

-- A new round starts with the pool switched back on.
local oldResetGame
oldResetGame = Class_ReplaceMethod("NS2Gamerules", "ResetGame", function(self, ...)
    oldResetGame(self, ...)
    offThisRound = false
    onThisRound = false
    ClearPool(nil)
end)

-- Commands ----------------------------------------------------------------------------------

SSM.AddChatCommand("joinq", function(client)
    local steamId = SteamIdOf(client)
    local player = client and client:GetControllingPlayer()
    if not (steamId and player) then
        return
    end
    local offReason = OffReason()
    if offReason == "off" then
        Say(client, "joinpool_off")
    elseif offReason == "thunderdome" then
        Say(client, "joinpool_thunderdome")
    elseif not IsLive() then
        Say(client, "joinpool_not_live")
    elseif not IsBench(player:GetTeamNumber()) then
        Say(client, "joinpool_on_team")
    elseif LockState() == "missing" then
        Say(client, "joinpool_no_lockteams")
    elseif LockState() == "open" then
        Say(client, "joinpool_not_locked")
    elseif PoolIndex(steamId) then
        Say(client, "joinpool_already", #Pool)
    else
        Pool[#Pool + 1] = { steamId = steamId, since = Shared.GetTime() }
        poolChanged = true
        Say(client, "joinpool_added", #Pool, Config.MaxDifference)
        local left = OfferWaitLeft()
        if left then
            Say(client, "joinpool_wait_start", Config.OfferDelaySeconds, math.ceil(left))
        end
    end
end)
SSM.ListCommand("!joinq", "cmd_joinq")

SSM.AddChatCommand("exitq", function(client)
    local steamId = SteamIdOf(client)
    if not steamId then
        return
    end
    if RemoveFromPool(steamId) then
        if Proposal and (Proposal.marine == steamId or Proposal.alien == steamId) then
            local partner = FindClient(Proposal.marine == steamId and Proposal.alien or Proposal.marine)
            ClearProposal()
            if partner then
                Say(partner, "joinpool_partner_left")
            end
        end
        Say(client, "joinpool_left")
    else
        Say(client, "joinpool_not_in")
    end
end)
SSM.ListCommand("!exitq", "cmd_exitq")

SSM.AddChatCommand("listq", function(client)
    local names = {}
    for _, entry in ipairs(Pool) do
        local queued = FindClient(entry.steamId)
        local player = queued and queued:GetControllingPlayer()
        if player then
            names[#names + 1] = player:GetName()
        end
    end
    if #names == 0 then
        Say(client, "joinpool_list_empty")
    else
        Say(client, "joinpool_list", #names, table.concat(names, ", "))
    end
end)
SSM.ListCommand("!listq", "cmd_listq")

SSM.AddChatCommand("ready", function(client)
    local steamId = SteamIdOf(client)
    if not (steamId and Proposal and (Proposal.marine == steamId or Proposal.alien == steamId)) then
        Say(client, "joinpool_ready_none")
        return
    end
    Proposal.ready[steamId] = true
    if Proposal.ready[Proposal.marine] and Proposal.ready[Proposal.alien] then
        Complete()
    else
        local other = Proposal.marine == steamId and Proposal.alienName or Proposal.marineName
        Say(client, "joinpool_ready_wait", other)
    end
end)
SSM.ListCommand("!ready", "cmd_ready")

-- sud_joinpool on|off, this round only (the pool is on by default and every new round starts on).
-- Who: the server console and every Shine admin, i.e. anyone in a Shine user group, with no
-- config change (author, 2026-11-21: "naturally Shine admins should have access"). Shine access
-- to sud_joinpool also works, for anyone given it explicitly.
local function IsShineAdmin(client)
    if not Shine then
        return false
    end
    if Shine.GetUserData and Shine:GetUserData(client) then
        return true
    end
    return Shine.HasAccess and Shine:HasAccess(client, "sud_joinpool") or false
end
SSM.JoinPool_IsAdmin = IsShineAdmin

Event.Hook("Console_sud_joinpool", function(caller, word)
    local allowed = not caller or IsShineAdmin(caller)
    local function Reply(key)
        local text = SSM.Text(SSM.LanguageOf(caller), key)
        SSM.Print(caller, text)
        if caller then
            SSM.Notify(caller, text)
        end
    end
    if not allowed then
        Reply("joinpool_no_access")
        return
    end
    word = word and string.lower(word)
    if word == "off" then
        offThisRound = true
        ClearPool("joinpool_admin_off_you")
        SayToEveryone(nil, "joinpool_admin_off", function() end)
    elseif word == "on" then
        offThisRound = false
        onThisRound = true
        SayToEveryone(nil, "joinpool_admin_on", function() end)
    else
        Reply("joinpool_usage")
    end
end)
SSM.ListCommand("sud_joinpool", "cmd_sud_joinpool", true)

-- For the tests.
SSM.JoinPool_GetPool = function() return Pool end
SSM.JoinPool_GetProposal = function() return Proposal end
SSM.JoinPool_GetConfig = function() return Config end
