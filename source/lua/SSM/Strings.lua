-- NS2 SUD Server Admin - every text the mod sends to a single player, in English, Spanish and
-- Portuguese. Missing keys fall back to English. Messages to everyone (Commander Match, the pause,
-- saved players) stay in English and are not here.
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

-- !help
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

en.cmd_help = "This list, in the console"
es.cmd_help = "Esta lista, en la consola"
pt.cmd_help = "Esta lista, no console"

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

-- Pause (Thunderdome and passworded games)
en.cmd_pause = "Pause the game (Thunderdome and passworded games)"
es.cmd_pause = "Pausar la partida (Thunderdome y partidas con contraseña)"
pt.cmd_pause = "Pausar a partida (Thunderdome e partidas com senha)"

en.cmd_unpause = "Ready your team to resume a paused game"
es.cmd_unpause = "Marcar al equipo como listo para reanudar"
pt.cmd_unpause = "Marcar o time como pronto para retomar"

en.pause_unavailable = "Pausing is only available on Thunderdome and passworded games."
es.pause_unavailable = "La pausa solo está disponible en Thunderdome y en partidas con contraseña."
pt.pause_unavailable = "A pausa só está disponível no Thunderdome e em partidas com senha."

en.pause_none_left = "Your team is out of pauses."
es.pause_none_left = "A tu equipo no le quedan pausas."
pt.pause_none_left = "Seu time não tem mais pausas."

-- sud_swap (console)
en.cmd_sud_swap = "sud_swap <player> <player>: put a player into a disconnected player's place, or swap a player with a spectator (admins; commanders on their own team)"
es.cmd_sud_swap = "sud_swap <jugador> <jugador>: poner a un jugador en el lugar de uno desconectado, o intercambiar a un jugador con un espectador (admins; comandantes en su propio equipo)"
pt.cmd_sud_swap = "sud_swap <jogador> <jogador>: colocar um jogador no lugar de um desconectado, ou trocar um jogador com um espectador (admins; comandantes no próprio time)"

en.swap_usage = "Usage: sud_swap <player> <player> (a name, part of one, or a Steam ID)"
es.swap_usage = "Uso: sud_swap <jugador> <jugador> (un nombre, parte de uno o un Steam ID)"
pt.swap_usage = "Uso: sud_swap <jogador> <jogador> (um nome, parte de um ou um Steam ID)"

en.swap_no_access = "Only admins, and commanders for their own team, can use sud_swap."
es.swap_no_access = "Solo los admins, y los comandantes para su propio equipo, pueden usar sud_swap."
pt.swap_no_access = "Só admins, e comandantes para o próprio time, podem usar sud_swap."

en.swap_not_found = "No player matches \"%s\"."
es.swap_not_found = "Ningún jugador coincide con \"%s\"."
pt.swap_not_found = "Nenhum jogador corresponde a \"%s\"."

en.swap_ambiguous = "\"%s\" matches more than one player: %s"
es.swap_ambiguous = "\"%s\" coincide con más de un jugador: %s"
pt.swap_ambiguous = "\"%s\" corresponde a mais de um jogador: %s"

en.swap_same = "Those are the same player."
es.swap_same = "Es el mismo jugador."
pt.swap_same = "É o mesmo jogador."

en.swap_needs_bench = "One of the two players must be a spectator or in the ready room."
es.swap_needs_bench = "Uno de los dos jugadores tiene que ser espectador o estar en la sala de espera."
pt.swap_needs_bench = "Um dos dois jogadores precisa ser espectador ou estar na sala de espera."

en.swap_commander_rule = "Commanders can only swap a player on their team with a spectator or someone in the ready room."
es.swap_commander_rule = "Los comandantes solo pueden intercambiar a un jugador de su equipo con un espectador o alguien en la sala de espera."
pt.swap_commander_rule = "Comandantes só podem trocar um jogador do próprio time com um espectador ou alguém na sala de espera."

en.swap_done = "Done."
es.swap_done = "Listo."
pt.swap_done = "Pronto."

en.swap_failed = "The swap did not work. The server log has the details."
es.swap_failed = "El intercambio no funcionó. El log del servidor tiene los detalles."
pt.swap_failed = "A troca não funcionou. O log do servidor tem os detalhes."
