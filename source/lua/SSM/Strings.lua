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

-- Join Pool. Team names stay as the game shows them in every language.
en.team_marines = "Marines"
es.team_marines = "Marines"
pt.team_marines = "Marines"

en.team_aliens = "Aliens"
es.team_aliens = "Aliens"
pt.team_aliens = "Aliens"

en.cmd_joinq = "Wait in the join pool during a live 6v6 or 7v7 with the teams locked (spectators and ready room). As a spectator, F4 does the same"
es.cmd_joinq = "Esperar en la cola para entrar durante una partida 6v6 o 7v7 en curso con los equipos bloqueados (espectadores y sala de espera). Como espectador, F4 hace lo mismo"
pt.cmd_joinq = "Esperar na fila para entrar durante uma partida 6v6 ou 7v7 em andamento com os times travados (espectadores e sala de espera). Como espectador, F4 faz o mesmo"

en.cmd_exitq = "Leave the join pool"
es.cmd_exitq = "Salir de la cola para entrar"
pt.cmd_exitq = "Sair da fila para entrar"

en.cmd_listq = "Who is in the join pool"
es.cmd_listq = "Quién está en la cola para entrar"
pt.cmd_listq = "Quem está na fila para entrar"

en.cmd_ready = "Confirm when the join pool asks you to"
es.cmd_ready = "Confirmar cuando la cola para entrar lo pida"
pt.cmd_ready = "Confirmar quando a fila para entrar pedir"

en.cmd_sud_joinpool = "sud_joinpool on|off: switch the join pool on or off for this round (admins)"
es.cmd_sud_joinpool = "sud_joinpool on|off: activar o desactivar la cola para entrar en esta partida (admins)"
pt.cmd_sud_joinpool = "sud_joinpool on|off: ligar ou desligar a fila para entrar nesta partida (admins)"

en.joinpool_off = "The join pool is switched off."
es.joinpool_off = "La cola para entrar está desactivada."
pt.joinpool_off = "A fila para entrar está desligada."

en.joinpool_thunderdome = "The join pool is off on Thunderdome games."
es.joinpool_thunderdome = "La cola para entrar está desactivada en las partidas de Thunderdome."
pt.joinpool_thunderdome = "A fila para entrar está desligada nas partidas do Thunderdome."

en.joinpool_not_live = "The join pool only runs during a live round."
es.joinpool_not_live = "La cola para entrar solo funciona con una partida en curso."
pt.joinpool_not_live = "A fila para entrar só funciona com uma partida em andamento."

en.joinpool_on_team = "You are already on a team."
es.joinpool_on_team = "Ya está en un equipo."
pt.joinpool_on_team = "Você já está em um time."

en.joinpool_no_lockteams = "The join pool needs Lockteams, which is not running on this server."
es.joinpool_no_lockteams = "La cola para entrar necesita Lockteams, que no está activo en este servidor."
pt.joinpool_no_lockteams = "A fila para entrar precisa do Lockteams, que não está ativo neste servidor."

en.joinpool_not_locked = "The teams are not locked, so you can join a team directly. The join pool only runs while the teams are locked."
es.joinpool_not_locked = "Los equipos no están bloqueados, así que se puede entrar a un equipo directamente. La cola para entrar solo funciona con los equipos bloqueados."
pt.joinpool_not_locked = "Os times não estão travados, então dá para entrar em um time direto. A fila para entrar só funciona com os times travados."

en.joinpool_unlocked = "The teams were unlocked, so you can join a team directly. The join pool is paused until they are locked again; you keep your place."
es.joinpool_unlocked = "Se desbloquearon los equipos, así que se puede entrar a un equipo directamente. La cola para entrar queda en pausa hasta que se vuelvan a bloquear; el lugar se mantiene."
pt.joinpool_unlocked = "Os times foram destravados, então dá para entrar em um time direto. A fila para entrar fica pausada até travarem de novo; você mantém o lugar."

en.joinpool_relocked = "The teams are locked again, so the join pool is running again."
es.joinpool_relocked = "Los equipos se volvieron a bloquear, así que la cola para entrar funciona otra vez."
pt.joinpool_relocked = "Os times foram travados de novo, então a fila para entrar voltou a funcionar."

en.joinpool_already ="You are already in the join pool (%d waiting)."
es.joinpool_already = "Ya está en la cola para entrar (%d esperando)."
pt.joinpool_already = "Você já está na fila para entrar (%d esperando)."

en.joinpool_already_f4 = "You are already in the join pool (%d waiting). Type !exitq to leave it."
es.joinpool_already_f4 = "Ya está en la cola para entrar (%d esperando). Escriba !exitq para salir."
pt.joinpool_already_f4 = "Você já está na fila para entrar (%d esperando). Digite !exitq para sair."

en.joinpool_added = "You are in the join pool (%d waiting). When you and another player can join and keep the teams within %d elo, you will be asked to type !readyq."
es.joinpool_added = "Está en la cola para entrar (%d esperando). Cuando haya otro jugador con quien entrar manteniendo los equipos a menos de %d de elo, se pedirá escribir !readyq."
pt.joinpool_added = "Você está na fila para entrar (%d esperando). Quando você e outro jogador puderem entrar mantendo os times a menos de %d de elo, vamos pedir para digitar !readyq."

en.joinpool_wait_start = "Pairs are picked from %d seconds into the round, so everyone has time to join the pool (%d s left)."
es.joinpool_wait_start = "Los pares se eligen a partir de los %d segundos de partida, para que todos tengan tiempo de entrar a la cola (faltan %d s)."
pt.joinpool_wait_start = "Os pares são escolhidos a partir dos %d segundos de partida, para que todos tenham tempo de entrar na fila (faltam %d s)."

en.joinpool_left ="You left the join pool."
es.joinpool_left = "Salió de la cola para entrar."
pt.joinpool_left = "Você saiu da fila para entrar."

en.joinpool_not_in = "You are not in the join pool."
es.joinpool_not_in = "No está en la cola para entrar."
pt.joinpool_not_in = "Você não está na fila para entrar."

en.joinpool_list = "Join pool (%d): %s"
es.joinpool_list = "Cola para entrar (%d): %s"
pt.joinpool_list = "Fila para entrar (%d): %s"

en.joinpool_list_empty = "Nobody is in the join pool."
es.joinpool_list_empty = "No hay nadie en la cola para entrar."
pt.joinpool_list_empty = "Não há ninguém na fila para entrar."

en.joinpool_ready_none = "Nobody has asked you to type !readyq."
es.joinpool_ready_none = "No hay ningún pedido de !readyq pendiente."
pt.joinpool_ready_none = "Ninguém pediu para você digitar !readyq."

en.joinpool_ready_wait = "Ready. Waiting for %s."
es.joinpool_ready_wait = "Listo. Esperando a %s."
pt.joinpool_ready_wait = "Pronto. Esperando %s."

en.joinpool_pair_public = "%s (Marines) and %s (Aliens) are the best suitable joiners. Elo difference now: %s. After joining: %s. They have %d seconds to type !readyq."
es.joinpool_pair_public = "%s (Marines) y %s (Aliens) son los jugadores más adecuados para entrar. Diferencia de elo ahora: %s. Después de entrar: %s. Tienen %d segundos para escribir !readyq."
pt.joinpool_pair_public = "%s (Marines) e %s (Aliens) são os jogadores mais adequados para entrar. Diferença de elo agora: %s. Depois de entrar: %s. Eles têm %d segundos para digitar !readyq."

en.joinpool_pair_you = "You and %s can join now, you on %s. Type !readyq within %d seconds."
es.joinpool_pair_you = "Hay lugar para entrar junto con %s, en %s. Para entrar, escribir !readyq en los próximos %d segundos."
pt.joinpool_pair_you = "Você e %s podem entrar agora, você nos %s. Digite !readyq nos próximos %d segundos."

en.joinpool_done = "%s joined Marines and %s joined Aliens. Elo difference now: %s."
es.joinpool_done = "%s entró a Marines y %s entró a Aliens. Diferencia de elo ahora: %s."
pt.joinpool_done = "%s entrou nos Marines e %s entrou nos Aliens. Diferença de elo agora: %s."

en.joinpool_cancel_you = "The teams changed, so that join would no longer keep them within %d elo. You stay in the join pool."
es.joinpool_cancel_you = "Los equipos cambiaron y esa entrada ya no los mantendría a menos de %d de elo. Sigue en la cola para entrar."
pt.joinpool_cancel_you = "Os times mudaram e essa entrada já não os manteria a menos de %d de elo. Você continua na fila para entrar."

en.joinpool_cancel_public = "The teams changed, so %s and %s will not join after all."
es.joinpool_cancel_public = "Los equipos cambiaron, así que %s y %s finalmente no entran."
pt.joinpool_cancel_public = "Os times mudaram, então %s e %s não vão entrar afinal."

en.joinpool_failed_you = "The server could not put you on the team. You stay in the join pool."
es.joinpool_failed_you = "El servidor no pudo hacer la entrada a los equipos. Sigue en la cola para entrar."
pt.joinpool_failed_you = "O servidor não conseguiu colocar você no time. Você continua na fila para entrar."

en.joinpool_expired_you = "You did not type !readyq in time and left the join pool. Type !joinq to wait again."
es.joinpool_expired_you = "No se escribió !readyq a tiempo y salió de la cola para entrar. Con !joinq se vuelve a esperar."
pt.joinpool_expired_you = "Você não digitou !readyq a tempo e saiu da fila para entrar. Digite !joinq para esperar de novo."

en.joinpool_expired_other = "%s did not type !readyq in time. You stay in the join pool."
es.joinpool_expired_other = "%s no escribió !readyq a tiempo. Sigue en la cola para entrar."
pt.joinpool_expired_other = "%s não digitou !readyq a tempo. Você continua na fila para entrar."

en.joinpool_expired_public = "Not ready in time: %s. Looking for another pair."
es.joinpool_expired_public = "No confirmaron a tiempo: %s. Buscando otro par."
pt.joinpool_expired_public = "Não confirmaram a tempo: %s. Procurando outro par."

en.joinpool_partner_left = "The other player left the join pool. You stay in it."
es.joinpool_partner_left = "El otro jugador salió de la cola para entrar. Sigue en ella."
pt.joinpool_partner_left = "O outro jogador saiu da fila para entrar. Você continua nela."

en.joinpool_round_over = "The round is over, so the join pool was cleared."
es.joinpool_round_over = "La partida terminó, así que se vació la cola para entrar."
pt.joinpool_round_over = "A partida terminou, então a fila para entrar foi esvaziada."

en.joinpool_no_access = "Only admins can switch the join pool."
es.joinpool_no_access = "Solo los admins pueden activar o desactivar la cola para entrar."
pt.joinpool_no_access = "Só admins podem ligar ou desligar a fila para entrar."

en.joinpool_usage = "Usage: sud_joinpool on|off"
es.joinpool_usage = "Uso: sud_joinpool on|off"
pt.joinpool_usage = "Uso: sud_joinpool on|off"

en.joinpool_admin_off = "An admin switched the join pool off for this round."
es.joinpool_admin_off = "Un admin desactivó la cola para entrar en esta partida."
pt.joinpool_admin_off = "Um admin desligou a fila para entrar nesta partida."

en.joinpool_admin_on = "An admin switched the join pool back on."
es.joinpool_admin_on = "Un admin volvió a activar la cola para entrar."
pt.joinpool_admin_on = "Um admin ligou de novo a fila para entrar."

en.joinpool_admin_off_you = "The join pool was switched off for this round, so you are no longer in it."
es.joinpool_admin_off_you = "La cola para entrar se desactivó en esta partida, así que ya no está en ella."
pt.joinpool_admin_off_you = "A fila para entrar foi desligada nesta partida, então você não está mais nela."
