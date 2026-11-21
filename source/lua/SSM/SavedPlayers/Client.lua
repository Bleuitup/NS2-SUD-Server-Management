-- NS2 SUD saved players, client part (v1.2).
--
-- When the server hands this client a player that already existed (going back into a
-- disconnected body, taking one over, sud_swap), the game's "use" prompt (evolve, hive, pick up)
-- was never set up for it on this machine: AlienActionFinderMixin, MarineActionFinderMixin and
-- ReadyRoomPlayer only create it when the entity is created as the local player. Their move code
-- then hit a nil every frame (GitHub issue #1, found by LZZ). The game raises LocalPlayerChanged
-- whenever this client starts controlling another entity, and runs its own per-player setup
-- (OnInitLocalClient) from it; this adds the missing prompt there, the way those classes do, and
-- removes the one left on the player this client just left.

local previousLocalId

local function SetUpUsePrompt(player)
    if player.actionIconGUI then
        return
    end

    local color, hide
    if HasMixin(player, "AlienActionFinder") then
        color = kAlienFontColor
        player.lastAlienActionFindTime = 0
    elseif HasMixin(player, "MarineActionFinder") then
        color = kMarineFontColor
        player.lastMarineActionFindTime = 0
    elseif player:isa("ReadyRoomPlayer") then
        color, hide = kMarineFontColor, true
    else
        return
    end

    player.actionIconGUI = GetGUIManager():CreateGUIScript("GUIActionIcon")
    player.actionIconGUI:SetColor(color)
    if hide then
        player.actionIconGUI:Hide()
    end
end

local function DropUsePrompt(player)
    if player.actionIconGUI then
        GetGUIManager():DestroyGUIScript(player.actionIconGUI)
        player.actionIconGUI = nil
    end
end

Event.Hook("LocalPlayerChanged", function()
    local ok, err = pcall(function()
        local player = Client.GetLocalPlayer()

        local previous = previousLocalId and Shared.GetEntity(previousLocalId)
        if previous and previous ~= player then
            DropUsePrompt(previous)
        end
        previousLocalId = player and player:GetId() or nil

        -- Only for a player this client controls, not one it is spectating in first person.
        if player and Client.GetIsControllingPlayer() then
            SetUpUsePrompt(player)
        end
    end)
    if not ok then
        Shared.Message("[NS2 SUD] use prompt error: " .. tostring(err))
    end
end)
