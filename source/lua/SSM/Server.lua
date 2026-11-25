-- NS2 SUD Server Admin - server files for every feature.

-- Shared by every feature, so they load first: the chat voice and languages, the texts, and the
-- chat command router with !help and !lang.
Script.Load("lua/SSM/Messages.lua")
Script.Load("lua/SSM/Strings.lua")
Script.Load("lua/SSM/Commands.lua")

Script.Load("lua/SSM/MatchesInARow/Server.lua")
Script.Load("lua/SSM/SpectatorOnConnect/Server.lua")
Script.Load("lua/SSM/CommMatch/Server.lua")
Script.Load("lua/SSM/Pause/Server.lua")
Script.Load("lua/SSM/SavedPlayers/Server.lua")
Script.Load("lua/SSM/JoinPool/Server.lua")
Script.Load("lua/SSM/AllTalk/Server.lua")
