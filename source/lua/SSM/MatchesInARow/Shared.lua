-- Matches In A Row - network messages.

-- One player's count. Players at 0 are never sent.
Shared.RegisterNetworkMessage("SSM_MatchesInARow", {
    steamId = "integer",
    rounds = "integer (0 to 255)",
    minutes = "integer (0 to 4095)"
})

-- Forget every count. Always sent right before a full list, so a client never keeps a count the
-- server has already dropped.
Shared.RegisterNetworkMessage("SSM_MatchesInARowClear", {})
