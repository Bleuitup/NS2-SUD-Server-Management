-- NS2 SUD Server Admin - every text the mod sends to a single player, in English, Spanish and
-- Portuguese. Missing keys fall back to English. Messages to everyone (Commander Match) stay in
-- English and are not here.
--
-- Spanish avoids both "tú" and "vos" where it can, since players come from all over the region;
-- "rounds in a row" is "partidas sucesivas" (the author's term).

local en = SSM.Strings.en
local es = SSM.Strings.es
local pt = SSM.Strings.pt

-- !lang
en.lang_set = "Server messages will now be in English."
es.lang_set = "Los mensajes del servidor ahora estarán en español."
pt.lang_set = "As mensagens do servidor agora estarão em português."

en.lang_usage = "To pick the language of server messages: !lang es, !lang pt or !lang en"
es.lang_usage = "Para elegir el idioma de los mensajes del servidor: !lang es, !lang pt o !lang en"
pt.lang_usage = "Para escolher o idioma das mensagens do servidor: !lang es, !lang pt ou !lang en"

-- !commands
en.commands_chat = "All server commands are listed in your console."
es.commands_chat = "La lista de comandos del servidor está en la consola."
pt.commands_chat = "A lista de comandos do servidor está no console."

en.commands_header = "NS2 SUD server commands"
es.commands_header = "Comandos del servidor NS2 SUD"
pt.commands_header = "Comandos do servidor NS2 SUD"

en.commands_chat_tag = "chat"
es.commands_chat_tag = "chat"
pt.commands_chat_tag = "chat"

en.commands_console_tag = "console"
es.commands_console_tag = "consola"
pt.commands_console_tag = "console"

en.cmd_commands = "This list, in the console"
es.cmd_commands = "Esta lista, en la consola"
pt.cmd_commands = "Esta lista, no console"

en.cmd_lang = "Language of server messages: es, pt or en"
es.cmd_lang = "Idioma de los mensajes del servidor: es, pt o en"
pt.cmd_lang = "Idioma das mensagens do servidor: es, pt ou en"

en.cmd_streakr = "Top 5 players by rounds in a row"
es.cmd_streakr = "Top 5 de jugadores por partidas sucesivas"
pt.cmd_streakr = "Top 5 de jogadores por partidas seguidas"

en.cmd_streakm = "Top 5 players by minutes played over those rounds"
es.cmd_streakm = "Top 5 de jugadores por minutos jugados en esas partidas"
pt.cmd_streakm = "Top 5 de jogadores por minutos jogados nessas partidas"

en.cmd_sud_streaks = "Every player, ranked by rounds in a row and by minutes"
es.cmd_sud_streaks = "Todos los jugadores, por partidas sucesivas y por minutos"
pt.cmd_sud_streaks = "Todos os jogadores, por partidas seguidas e por minutos"

-- Matches in a row
en.streaks_rounds_header = "Players sorted by rounds played"
es.streaks_rounds_header = "Jugadores por partidas sucesivas"
pt.streaks_rounds_header = "Jogadores por partidas seguidas"

en.streaks_minutes_header = "Players sorted by minutes played"
es.streaks_minutes_header = "Jugadores por minutos jugados"
pt.streaks_minutes_header = "Jogadores por minutos jogados"

-- Short unit after the number: 4r / 140m.
en.streaks_rounds_unit = "r"
es.streaks_rounds_unit = "p"
pt.streaks_rounds_unit = "p"

en.streaks_minutes_unit = "m"
es.streaks_minutes_unit = "m"
pt.streaks_minutes_unit = "m"

en.streaks_nobody = "No rounds have been counted yet this session."
es.streaks_nobody = "Todavía no se contó ninguna partida en esta sesión."
pt.streaks_nobody = "Nenhuma partida foi contada ainda nesta sessão."

-- Spectator on connect
en.spectator_joined = "You start as a spectator. Join a team when a player slot is free."
es.spectator_joined = "Ingresaste como espectador. Cuando se libere un lugar de jugador, ya se puede entrar a un equipo."
pt.spectator_joined = "Você entrou como espectador. Entre em um time quando houver uma vaga de jogador livre."
