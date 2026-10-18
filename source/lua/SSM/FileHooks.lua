-- NS2 SUD Server Management - file hooks for every feature.
--
-- Post hooks only. Scoreboard mods such as Devnull's Enhanced ScoreBoard take over
-- lua/GUIScoreboard.lua in "replace" mode, and a post hook runs after whichever version loaded,
-- so this layers on top of vanilla or a replacement alike.

ModLoader.SetupFileHook("lua/GUIScoreboard.lua", "lua/SSM/MatchesInARow/GUIScoreboard.lua", "post")
