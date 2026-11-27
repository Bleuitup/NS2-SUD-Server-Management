-- Skill Requirement - server side (v1.6, author 2026-11-27).
--
-- On a server that turns it on, players below a Hive skill tier stay in spectator: they cannot go
-- to the ready room, join a team or join the SUD Queue. They can stay and spectate. Admins let a
-- player play anyway by adding them to a Shine group (sud_allow, the admin menu, or Shine's own
-- sh_setusergroup).
--
-- Rules (the author's picks, 2026-11-27):
--   * Off unless the server's config says Enabled. Never on Thunderdome or while the server has
--     a password (the same password tracking as the pause).
--   * Tier = the scoreboard badge, the game's GetPlayerSkillTier formula, worked out here (the
--     game's own GetSkillTier caches its first answer, which can be from before the Hive data
--     came). Players at MinTier and above always play.
--   * Exempt: bots, everyone Shine lists in its user file (admins, trusted players and the allow
--     group), and players whose country is on AllowedCountries.
--   * Country: only looked up for players below MinTier who are not exempt, and only when
--     AllowedCountries has entries. The client's IP goes to ip-api.com, the same lookup Enhanced
--     Scoreboard makes (author's OK, 2026-11-27); only the 2-letter country code comes back and
--     it is kept in memory for this map only, never saved. An answer that does not come within
--     UnknownCountryHoldSeconds lets the player through. Private (LAN) addresses are let through.
--   * Hive skill not loaded yet (-1, the game's starting value): held, everyone not exempt, with
--     a "please wait" line; after HiveSkillGiveUpSeconds (the game has stopped asking Steam by
--     then) the line says to reconnect.
--   * Held players are refused every unforced move out of spectator or the ready room (forced
--     moves from admins, sud_swap and shuffles go through). Restricted players (and players whose
--     Hive skill never loaded) found in the ready room, after a map change for example, are moved
--     to spectator so a shuffle cannot place them.
--   * Messages: a welcome once when a player is found below the requirement; on refused moves the
--     Spanish line first, once, then the skill line; admins on the server get one line per player
--     per map with how to let them play. Welcome and Spanish line are remembered for 12 hours, so
--     map changes do not repeat them. Nothing in the messages names a region (author).

local kConfigFile = "SSM_SkillRequirement.json"
local kDefaultConfig = {
    Enabled = false,
    MinTier = 4,
    -- 2-letter country codes whose players are exempt. Empty: no lookups, nobody exempt by country.
    AllowedCountries = {},
    UnknownCountryHoldSeconds = 30,
    HiveSkillGiveUpSeconds = 60,
    -- The Shine group sud_allow puts players in (created when missing).
    AllowGroup = "SudAllow"
}
local kStateFile = "SSM_SkillRequirementState.json"
local kRememberSeconds = 12 * 60 * 60
local kLookupURL = "http://ip-api.com/json/%s?fields=status,countryCode"
local kLookupRetrySeconds = 5
local kLookupMaxAttempts = 3
local kCheckSeconds = 1
local kWelcomeDelaySeconds = 5
local kRefuseQuietSeconds = 1
local kPermission = "sud_allowed"

-- The game's tier names and where each starts (GetPlayerSkillTier).
local kTierNames = { [1] = "Recruit", [2] = "Frontiersman", [3] = "Squad Leader", [4] = "Veteran",
    [5] = "Commandant", [6] = "Special Ops", [7] = "Sanji Survivor" }
local kTierAbove = { [1] = 0, [2] = 300, [3] = 750, [4] = 1400, [5] = 2100, [6] = 2900, [7] = 4100 }

local function Log(text)
    Shared.Message("[NS2 SUD] Skill Requirement: " .. text)
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

local Allowed = {}
for _, code in ipairs(type(Config.AllowedCountries) == "table" and Config.AllowedCountries or {}) do
    if type(code) == "string" and code ~= "" then
        Allowed[string.upper(code)] = true
    end
end
local hasAllowedList = next(Allowed) ~= nil

local function AllowGroup()
    return type(Config.AllowGroup) == "string" and Config.AllowGroup ~= "" and Config.AllowGroup or "SudAllow"
end
SSM.AllowGroup = AllowGroup()

local function MinTier()
    return math.max(1, math.min(7, math.floor(tonumber(Config.MinTier) or 4)))
end

-- State -------------------------------------------------------------------------------------

-- Welcome and Spanish line already shown: [tostring(steamId)] = system time.
local Remembered = LoadConfigFile(kStateFile)
if type(Remembered) ~= "table" then
    Remembered = {}
end
Remembered.Welcomed = type(Remembered.Welcomed) == "table" and Remembered.Welcomed or {}
Remembered.Spanish = type(Remembered.Spanish) == "table" and Remembered.Spanish or {}

local function Recent(list, steamId)
    local at = list[tostring(steamId)]
    return type(at) == "number" and Shared.GetSystemTime() - at < kRememberSeconds
end

local function Remember(list, steamId)
    local now = Shared.GetSystemTime()
    for key, at in pairs(list) do
        if type(at) ~= "number" or now - at >= kRememberSeconds then
            list[key] = nil
        end
    end
    list[tostring(steamId)] = now
    SaveConfigFile(kStateFile, Remembered)
end

-- Per player, this map only: [steamId] = { firstSeen, country, lookupStarted, lookupBusy,
-- attempts, failedAt, adminTold, welcomeDue, quietUntil }. country: nil = not asked yet, a code,
-- "LAN" for private addresses.
local Info = {}

local function SteamIdOf(client)
    if client and not client:GetIsVirtual() then
        local steamId = client:GetUserId()
        if steamId and steamId > 0 then
            return steamId
        end
    end
end

local function InfoFor(steamId)
    local info = Info[steamId]
    if not info then
        info = { firstSeen = Shared.GetTime(), attempts = 0 }
        Info[steamId] = info
    end
    return info
end

Event.Hook("ClientConnect", function(client)
    local steamId = SteamIdOf(client)
    if steamId then
        Info[steamId] = { firstSeen = Shared.GetTime(), attempts = 0 }
    end
end)

-- When it applies ----------------------------------------------------------------------------

local function GetIsThunderdome()
    return Shared.GetThunderdomeEnabled ~= nil and Shared.GetThunderdomeEnabled() == true
end

local function Active()
    return Config.Enabled == true and not GetIsThunderdome() and not (SSM.HasPassword and SSM.HasPassword())
end

-- Anyone Shine lists (any group), or with the permission. Bots are never held either.
local function IsExempt(client)
    if not Shine then
        return false
    end
    if Shine.GetUserData and Shine:GetUserData(client) then
        return true
    end
    return Shine.HasAccess ~= nil and Shine:HasAccess(client, kPermission) == true
end

-- The badge tier, or nil while the Hive skill is not loaded.
local function TierOf(player)
    local skill = player.GetPlayerSkill and player:GetPlayerSkill()
    if type(skill) ~= "number" or skill < 0 then
        return nil
    end
    local rookie
    if player.GetIsRookie then
        rookie = player:GetIsRookie() == true
    else
        local level = player.GetPlayerLevel and player:GetPlayerLevel()
        rookie = type(level) == "number" and level >= 0 and level <= (kRookieLevel or 10)
    end
    local adagrad = player.GetAdagradSum and player:GetAdagradSum() or nil
    local tier = GetPlayerSkillTier(skill, rookie, adagrad)
    return type(tier) == "number" and tier >= 0 and tier or nil
end

-- Country lookup -----------------------------------------------------------------------------

local function AddressOf(client)
    if not (Server.GetClientAddress and IPAddressToString) then
        return nil
    end
    local ok, address = pcall(function() return IPAddressToString(Server.GetClientAddress(client)) end)
    return ok and type(address) == "string" and address or nil
end

local function IsPrivate(address)
    local a, b = address:match("^(%d+)%.(%d+)%.%d+%.%d+$")
    a, b = tonumber(a), tonumber(b)
    if not a then
        return true   -- not an IPv4 address: nothing to look up
    end
    return a == 10 or a == 127 or a == 0 or (a == 192 and b == 168) or (a == 172 and b >= 16 and b <= 31)
        or (a == 169 and b == 254)
end

local function StartLookup(client, info, now)
    info.lookupStarted = info.lookupStarted or now
    local address = AddressOf(client)
    if not address or IsPrivate(address) then
        info.country = "LAN"
        return
    end
    if not (Shared.SendHTTPRequest and json and json.decode) then
        info.country = "LAN"
        return
    end
    info.lookupBusy = true
    info.attempts = info.attempts + 1
    Shared.SendHTTPRequest(string.format(kLookupURL, address), "GET", {}, function(data)
        info.lookupBusy = false
        local ok, result = pcall(json.decode, data or "")
        if ok and type(result) == "table" and result.status == "success" and type(result.countryCode) == "string" then
            info.country = string.upper(result.countryCode)
        else
            info.failedAt = Shared.GetTime()
        end
    end)
end

-- Status -------------------------------------------------------------------------------------

-- "free", "loading" (Hive skill not loaded), "failed" (it never loaded), "checking" (country
-- lookup under way) or "restricted"; the tier as the second value when known.
local function StatusOf(client)
    if not Active() then
        return "free"
    end
    local steamId = SteamIdOf(client)
    local player = client and client:GetControllingPlayer()
    if not (steamId and player) or IsExempt(client) then
        return "free"
    end

    local info = InfoFor(steamId)
    local now = Shared.GetTime()
    local tier = TierOf(player)
    if not tier then
        return now - info.firstSeen < (tonumber(Config.HiveSkillGiveUpSeconds) or 60) and "loading" or "failed"
    end
    if tier >= MinTier() then
        return "free", tier
    end
    if not hasAllowedList then
        return "restricted", tier
    end

    if info.country == nil and not info.lookupBusy then
        local retryDue = not info.failedAt or now - info.failedAt >= kLookupRetrySeconds
        if info.attempts < kLookupMaxAttempts and retryDue then
            StartLookup(client, info, now)
        end
    end
    if info.country == "LAN" then
        return "free", tier
    end
    if info.country then
        return Allowed[info.country] and "free" or "restricted", tier
    end
    local hold = tonumber(Config.UnknownCountryHoldSeconds) or 30
    if now - (info.lookupStarted or now) < hold then
        return "checking", tier
    end
    return "free", tier
end

local function IsHeld(client)
    return StatusOf(client) ~= "free"
end
SSM.SkillRequirement_IsHeld = IsHeld

-- Messages -----------------------------------------------------------------------------------

local function Say(client, key, ...)
    SSM.Notify(client, SSM.Text(SSM.LanguageOf(client), key, ...))
end

local function SayLines(client, keys)
    local language = SSM.LanguageOf(client)
    for i, key in ipairs(keys) do
        SSM.Notify(client, SSM.Text(language, key), i > 1)
    end
end

local function Thousands(number)
    local text = tostring(math.floor(number))
    repeat
        local count
        text, count = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
    until count == 0
    return text
end

local function TierLine(client)
    local tier = MinTier()
    Say(client, "skill_too_low", tier, kTierNames[tier], Thousands(kTierAbove[tier]))
end

local function GameIdOf(client)
    local ids = Shine and Shine.GameIDs
    local id = ids and ids.Get and ids:Get(client)
    return id
end

local function TellAdmins(client, tier, country)
    local player = client:GetControllingPlayer()
    local name = player and player:GetName() or "?"
    local id = GameIdOf(client)
    local target = id and ("#" .. id) or tostring(client:GetUserId())
    Server.ForAllPlayers(function(other)
        local admin = Server.GetOwner(other)
        if admin and admin ~= client and SteamIdOf(admin) and SSM.IsAdmin(admin) then
            local language = SSM.LanguageOf(admin)
            if country and country ~= "" then
                SSM.Notify(admin, SSM.Text(language, "skill_admin_country", name, target, country, tier, target))
            else
                SSM.Notify(admin, SSM.Text(language, "skill_admin", name, target, tier, target))
            end
        end
    end)
end

-- Refuses a move for a held player and says why; true when refused. One line a second at most,
-- since one key press can try more than one move.
local function Refuse(client)
    local status = StatusOf(client)
    if status == "free" then
        return false
    end
    local steamId = SteamIdOf(client)
    local info = InfoFor(steamId)
    local now = Shared.GetTime()
    if info.quietUntil and now < info.quietUntil then
        return true
    end
    info.quietUntil = now + kRefuseQuietSeconds

    if status == "loading" then
        Say(client, "skill_loading")
    elseif status == "failed" then
        Say(client, "skill_failed")
    elseif status == "checking" then
        Say(client, "skill_checking")
    elseif not Recent(Remembered.Spanish, steamId) then
        Remember(Remembered.Spanish, steamId)
        -- Always in Spanish: it is for Spanish speakers who have not picked a language.
        SSM.Notify(client, SSM.Text("es", "skill_spanish"))
    else
        TierLine(client)
    end
    return true
end
SSM.SkillRequirement_Refuse = Refuse

-- Moves --------------------------------------------------------------------------------------

local oldJoinTeam
oldJoinTeam = Class_ReplaceMethod("NS2Gamerules", "JoinTeam", function(self, player, newTeamNumber, force, ...)
    if not force and player and newTeamNumber ~= kSpectatorIndex then
        local team = player:GetTeamNumber()
        if (team == kSpectatorIndex or team == kTeamReadyRoom) and newTeamNumber ~= team then
            local client = Server.GetOwner(player)
            local ok, refused = pcall(Refuse, client)
            if not ok then
                Log("error: " .. tostring(refused))
            elseif refused then
                return false
            end
        end
    end
    return oldJoinTeam(self, player, newTeamNumber, force, ...)
end)

-- Every second: welcome and admin lines for newly restricted players, and restricted players in
-- the ready room back to spectator.
local lastCheck = -math.huge

local function Check(now)
    if not Active() then
        return
    end
    local gamerules = GetGamerules and GetGamerules()
    Server.ForAllPlayers(function(player)
        local client = Server.GetOwner(player)
        local steamId = SteamIdOf(client)
        if not steamId then
            return
        end
        local status, tier = StatusOf(client)
        if status ~= "restricted" and status ~= "failed" then
            return
        end
        local info = InfoFor(steamId)

        if status == "restricted" then
            if not info.adminTold then
                info.adminTold = true
                local country = info.country ~= "LAN" and info.country or nil
                TellAdmins(client, tier, country)
            end
            if not Recent(Remembered.Welcomed, steamId) then
                info.welcomeDue = info.welcomeDue or math.max(now, info.firstSeen + kWelcomeDelaySeconds)
                if now >= info.welcomeDue then
                    Remember(Remembered.Welcomed, steamId)
                    SayLines(client, { "skill_welcome_1", "skill_welcome_2", "skill_welcome_3" })
                end
            end
        end

        if player:GetTeamNumber() == kTeamReadyRoom and gamerules then
            gamerules:JoinTeam(player, kSpectatorIndex, true)
        end
    end)
end

Event.Hook("UpdateServer", function()
    local now = Shared.GetTime()
    if now - lastCheck < kCheckSeconds then
        return
    end
    lastCheck = now
    local ok, err = pcall(Check, now)
    if not ok then
        Log("error: " .. tostring(err))
    end
end)

Event.Hook("ClientDisconnect", function(client)
    local steamId = SteamIdOf(client)
    if steamId then
        Info[steamId] = nil
    end
end)

-- sud_allow / sud_disallow -------------------------------------------------------------------

-- A player from "#12" (the sh_status number), a name, an NS2 ID or a STEAM_0:x:y ID. Offline
-- players by ID only. Returns client (or nil), NS2 ID, name.
local function Resolve(text)
    text = text and text:match("^%s*(.-)%s*$") or ""
    if text == "" or not Shine then
        return nil
    end
    local client
    local gameId = text:match("^#(%d+)$")
    if gameId then
        client = Shine.GetClientByID and Shine.GetClientByID(tonumber(gameId))
    elseif Shine.GetClient then
        client = Shine:GetClient(text)
    end
    if client and SteamIdOf(client) then
        local player = client:GetControllingPlayer()
        return client, client:GetUserId(), player and player:GetName() or tostring(client:GetUserId())
    end
    if gameId then
        return nil
    end
    local id = text:match("^%d+$") and tonumber(text) or (Shine.SteamIDToNS2 and Shine.SteamIDToNS2(text))
    if id and id > 0 then
        return nil, id, tostring(id)
    end
    return nil
end

local function Reply(caller, key, ...)
    local text = SSM.Text(SSM.LanguageOf(caller), key, ...)
    SSM.Print(caller, text)
    if caller then
        SSM.Notify(caller, text)
    end
end

local function UsersReady()
    return Shine and Shine.UserData and type(Shine.UserData.Users) == "table" and Shine.SaveUsers
end

local function EnsureGroup(group)
    local data = Shine:GetGroupData(group)
    if not data then
        data = Shine:CreateGroup(group, 0, false)
    end
    data.Commands = type(data.Commands) == "table" and data.Commands or {}
    for _, command in ipairs(data.Commands) do
        if command == kPermission then
            return
        end
    end
    data.Commands[#data.Commands + 1] = kPermission
    Shine:SaveUsers(true)
end

local function OnAllow(caller, ...)
    if caller and not SSM.IsAdmin(caller, "sud_allow") then
        Reply(caller, "allow_no_access")
        return
    end
    if not UsersReady() then
        Reply(caller, "allow_no_shine")
        return
    end
    local client, id, name = Resolve(table.concat({ ... }, " "))
    if not id then
        Reply(caller, select("#", ...) == 0 and "allow_usage" or "allow_not_found")
        return
    end
    local group = AllowGroup()
    local user = Shine:GetUserData(id)
    if user then
        if user.Group == group then
            Reply(caller, "allow_already", name, group)
        else
            Reply(caller, "allow_other_group", name, tostring(user.Group))
        end
        return
    end

    EnsureGroup(group)
    local created = Shine:CreateUser(id, group)
    if created then
        created.Note = name
        Shine:SaveUsers(true)
    end
    Log(string.format("%s added %s (%d) to %s", caller and Shine.GetClientInfo and Shine.GetClientInfo(caller) or "Console", name, id, group))
    Reply(caller, "allow_done", name, group)
    if client then
        Say(client, "allow_you")
    end
end

local function OnDisallow(caller, ...)
    if caller and not SSM.IsAdmin(caller, "sud_allow") then
        Reply(caller, "allow_no_access")
        return
    end
    if not UsersReady() then
        Reply(caller, "allow_no_shine")
        return
    end
    local _, id, name = Resolve(table.concat({ ... }, " "))
    if not id then
        Reply(caller, select("#", ...) == 0 and "disallow_usage" or "allow_not_found")
        return
    end
    local group = AllowGroup()
    local user, key = Shine:GetUserData(id)
    if not user then
        Reply(caller, "disallow_not_in", name, group)
    elseif user.Group ~= group then
        Reply(caller, "disallow_other_group", name, tostring(user.Group), group)
    else
        Shine:DeleteUser(key or id)
        Log(string.format("%s removed %s (%d) from %s", caller and Shine.GetClientInfo and Shine.GetClientInfo(caller) or "Console", name, id, group))
        Reply(caller, "disallow_done", name, group)
    end
end

Event.Hook("Console_sud_allow", OnAllow)
Event.Hook("Console_sud_disallow", OnDisallow)
SSM.ListCommand("sud_allow", "cmd_sud_allow", true)
SSM.ListCommand("sud_disallow", "cmd_sud_disallow", true)

-- For the tests.
SSM.SkillRequirement_StatusOf = StatusOf
