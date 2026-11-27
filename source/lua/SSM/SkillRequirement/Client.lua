-- Skill Requirement - client side (v1.6, author 2026-11-27): two buttons in Shine's admin menu
-- (Commands tab, "NS2 SUD"), for the selected player: "Sud Allow" runs sud_allow and "Remove Sud
-- Allow" runs sud_disallow with their Steam ID. The server checks who may use them. Shine is
-- another mod and loads in no set order, so the buttons go in on the first client update that
-- finds its admin menu.

local kCategory = "NS2 SUD"
local added = false

Event.Hook("UpdateClient", function()
    if added then
        return
    end
    local menu = Shine and Shine.AdminMenu
    if not (menu and menu.AddCommand and menu.Commands) then
        return
    end
    added = true
    local ok, err = pcall(function()
        menu:AddCommand(kCategory, "Sud Allow", "sud_allow", false, nil,
            "Let this player play here even below the skill requirement.")
        menu:AddCommand(kCategory, "Remove Sud Allow", "sud_disallow", false, nil,
            "Take this player out of the skill requirement's allow group.")
    end)
    if not ok then
        Shared.Message("[NS2 SUD] Skill Requirement admin menu error: " .. tostring(err))
    end
end)
