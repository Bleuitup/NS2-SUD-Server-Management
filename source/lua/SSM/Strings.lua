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

-- Commander Match: !mycomm and !comm. The list posted when someone takes a chair goes to
-- everyone and stays in English; these answers go to one player.
en.cmd_mycomm = "The 5 players whose commander skill is closest to yours, for the other team"
es.cmd_mycomm = "Los 5 jugadores con la habilidad de comandante más cercana a la suya, para el otro equipo"
pt.cmd_mycomm = "Os 5 jogadores com a habilidade de comandante mais próxima da sua, para o outro time"

en.cmd_comm = "The same list for whoever is in the command chair, when only one chair is taken"
es.cmd_comm = "La misma lista para quien esté en la silla de comandante, cuando hay una sola ocupada"
pt.cmd_comm = "A mesma lista para quem estiver na cadeira de comandante, quando só uma está ocupada"

en.comm_mine_marine = "If you command Marines, closest alien commanders:"
es.comm_mine_marine = "Si comanda Marines, los comandantes alien más cercanos:"
pt.comm_mine_marine = "Se você comandar Marines, os comandantes alien mais próximos:"

en.comm_mine_alien = "If you command Aliens, closest marine commanders:"
es.comm_mine_alien = "Si comanda Aliens, los comandantes marine más cercanos:"
pt.comm_mine_alien = "Se você comandar Aliens, os comandantes marine mais próximos:"

en.comm_seated_marine = "%s is Marine commander. Closest alien commanders:"
es.comm_seated_marine = "%s es comandante Marine. Comandantes alien más cercanos:"
pt.comm_seated_marine = "%s é comandante Marine. Comandantes alien mais próximos:"

en.comm_seated_alien = "%s is Alien commander. Closest marine commanders:"
es.comm_seated_alien = "%s es comandante Alien. Comandantes marine más cercanos:"
pt.comm_seated_alien = "%s é comandante Alien. Comandantes marine mais próximos:"

en.comm_no_skill = "You have never commanded, so there is nothing to compare."
es.comm_no_skill = "Todavía no comandó ninguna partida, así que no hay con qué comparar."
pt.comm_no_skill = "Você ainda não comandou, então não há com o que comparar."

en.comm_seated_no_skill = "%s has never commanded, so there is nothing to compare."
es.comm_seated_no_skill = "%s todavía no comandó ninguna partida, así que no hay con qué comparar."
pt.comm_seated_no_skill = "%s ainda não comandou, então não há com o que comparar."

en.comm_nobody_listed = "Nobody else on the server has commanded yet."
es.comm_nobody_listed = "Nadie más en el servidor comandó todavía."
pt.comm_nobody_listed = "Ninguém mais no servidor comandou ainda."

en.comm_no_chair = "Nobody is in a command chair."
es.comm_no_chair = "No hay nadie en una silla de comandante."
pt.comm_no_chair = "Não há ninguém em uma cadeira de comandante."

en.comm_both_chairs = "Both command chairs are taken, so there is no list."
es.comm_both_chairs = "Las dos sillas de comandante están ocupadas, así que no hay lista."
pt.comm_both_chairs = "As duas cadeiras de comandante estão ocupadas, então não há lista."

en.comm_off = "Commander match is off on Thunderdome games."
es.comm_off = "La comparación de comandantes está desactivada en Thunderdome."
pt.comm_off = "A comparação de comandantes está desligada no Thunderdome."

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

en.cmd_joinq = "Wait in the SUD Queue during a live 6v6 or 7v7 with the teams locked (spectators and ready room). As a spectator, F4 does the same"
es.cmd_joinq = "Esperar en la SUD Queue durante una partida 6v6 o 7v7 en curso con los equipos bloqueados (espectadores y sala de espera). Como espectador, F4 hace lo mismo"
pt.cmd_joinq = "Esperar na SUD Queue durante uma partida 6v6 ou 7v7 em andamento com os times travados (espectadores e sala de espera). Como espectador, F4 faz o mesmo"

en.cmd_exitq = "Leave the SUD Queue"
es.cmd_exitq = "Salir de la SUD Queue"
pt.cmd_exitq = "Sair da SUD Queue"

en.cmd_listq = "Who is in the SUD Queue"
es.cmd_listq = "Quién está en la SUD Queue"
pt.cmd_listq = "Quem está na SUD Queue"

en.cmd_ready = "Confirm when the SUD Queue asks you to"
es.cmd_ready = "Confirmar cuando la SUD Queue lo pida"
pt.cmd_ready = "Confirmar quando a SUD Queue pedir"

en.cmd_sud_joinpool = "sud_joinpool on|off: switch the SUD Queue on or off for this round (admins)"
es.cmd_sud_joinpool = "sud_joinpool on|off: activar o desactivar la SUD Queue en esta partida (admins)"
pt.cmd_sud_joinpool = "sud_joinpool on|off: ligar ou desligar a SUD Queue nesta partida (admins)"

en.joinpool_off = "The SUD Queue is switched off."
es.joinpool_off = "La SUD Queue está desactivada."
pt.joinpool_off = "A SUD Queue está desligada."

en.joinpool_thunderdome = "The SUD Queue is off on Thunderdome games."
es.joinpool_thunderdome = "La SUD Queue está desactivada en las partidas de Thunderdome."
pt.joinpool_thunderdome = "A SUD Queue está desligada nas partidas do Thunderdome."

en.joinpool_not_live = "The SUD Queue only runs during a live round."
es.joinpool_not_live = "La SUD Queue solo funciona con una partida en curso."
pt.joinpool_not_live = "A SUD Queue só funciona com uma partida em andamento."

en.joinpool_on_team = "You are already on a team."
es.joinpool_on_team = "Ya está en un equipo."
pt.joinpool_on_team = "Você já está em um time."

en.joinpool_no_lockteams = "The SUD Queue needs Lockteams, which is not running on this server."
es.joinpool_no_lockteams = "La SUD Queue necesita Lockteams, que no está activo en este servidor."
pt.joinpool_no_lockteams = "A SUD Queue precisa do Lockteams, que não está ativo neste servidor."

en.joinpool_not_locked = "The teams are not locked, so you can join a team directly. The SUD Queue only runs while the teams are locked."
es.joinpool_not_locked = "Los equipos no están bloqueados, así que se puede entrar a un equipo directamente. La SUD Queue solo funciona con los equipos bloqueados."
pt.joinpool_not_locked = "Os times não estão travados, então dá para entrar em um time direto. A SUD Queue só funciona com os times travados."

en.joinpool_unlocked = "The teams were unlocked, so you can join a team directly. The SUD Queue is paused until they are locked again; you keep your place."
es.joinpool_unlocked = "Se desbloquearon los equipos, así que se puede entrar a un equipo directamente. La SUD Queue queda en pausa hasta que se vuelvan a bloquear; el lugar se mantiene."
pt.joinpool_unlocked = "Os times foram destravados, então dá para entrar em um time direto. A SUD Queue fica pausada até travarem de novo; você mantém o lugar."

en.joinpool_relocked = "The teams are locked again, so the SUD Queue is running again."
es.joinpool_relocked = "Los equipos se volvieron a bloquear, así que la SUD Queue funciona otra vez."
pt.joinpool_relocked = "Os times foram travados de novo, então a SUD Queue voltou a funcionar."

en.joinpool_already ="You are already in the SUD Queue (%d waiting)."
es.joinpool_already = "Ya está en la SUD Queue (%d esperando)."
pt.joinpool_already = "Você já está na SUD Queue (%d esperando)."

en.joinpool_already_f4 = "You are already in the SUD Queue (%d waiting). Type !exitq to leave it."
es.joinpool_already_f4 = "Ya está en la SUD Queue (%d esperando). Escriba !exitq para salir."
pt.joinpool_already_f4 = "Você já está na SUD Queue (%d esperando). Digite !exitq para sair."

-- Every 60 s during a live round, to spectators who are not queued (v1.5).
en.joinpool_hint = "Want to play? Press F4 or type !joinq to join the SUD Queue and wait for a place."
es.joinpool_hint = "Para jugar: presione F4 o escriba !joinq y espere un lugar en la SUD Queue."
pt.joinpool_hint = "Quer jogar? Aperte F4 ou digite !joinq para entrar na SUD Queue e esperar uma vaga."

en.joinpool_hint_no_f4 = "Want to play? Type !joinq to join the SUD Queue and wait for a place."
es.joinpool_hint_no_f4 = "Para jugar: escriba !joinq y espere un lugar en la SUD Queue."
pt.joinpool_hint_no_f4 = "Quer jogar? Digite !joinq para entrar na SUD Queue e esperar uma vaga."

en.joinpool_added = "You are in the SUD Queue (%d waiting). When you and another player can join and keep the teams within %d elo, you will be asked to type !readyq."
es.joinpool_added = "Está en la SUD Queue (%d esperando). Cuando haya otro jugador con quien entrar manteniendo los equipos a menos de %d de elo, se pedirá escribir !readyq."
pt.joinpool_added = "Você está na SUD Queue (%d esperando). Quando você e outro jogador puderem entrar mantendo os times a menos de %d de elo, vamos pedir para digitar !readyq."

en.joinpool_wait_start = "Pairs are picked from %d seconds into the round, so everyone has time to join the SUD Queue (%d s left)."
es.joinpool_wait_start = "Los pares se eligen a partir de los %d segundos de partida, para que todos tengan tiempo de entrar a la SUD Queue (faltan %d s)."
pt.joinpool_wait_start = "Os pares são escolhidos a partir dos %d segundos de partida, para que todos tenham tempo de entrar na SUD Queue (faltam %d s)."

en.joinpool_left ="You left the SUD Queue."
es.joinpool_left = "Salió de la SUD Queue."
pt.joinpool_left = "Você saiu da SUD Queue."

en.joinpool_not_in = "You are not in the SUD Queue."
es.joinpool_not_in = "No está en la SUD Queue."
pt.joinpool_not_in = "Você não está na SUD Queue."

en.joinpool_list = "SUD Queue (%d): %s"
es.joinpool_list = "SUD Queue (%d): %s"
pt.joinpool_list = "SUD Queue (%d): %s"

en.joinpool_list_empty = "Nobody is in the SUD Queue."
es.joinpool_list_empty = "No hay nadie en la SUD Queue."
pt.joinpool_list_empty = "Não há ninguém na SUD Queue."

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

en.joinpool_cancel_you = "The teams changed, so that join would no longer keep them within %d elo. You stay in the SUD Queue."
es.joinpool_cancel_you = "Los equipos cambiaron y esa entrada ya no los mantendría a menos de %d de elo. Sigue en la SUD Queue."
pt.joinpool_cancel_you = "Os times mudaram e essa entrada já não os manteria a menos de %d de elo. Você continua na SUD Queue."

en.joinpool_cancel_public = "The teams changed, so %s and %s will not join after all."
es.joinpool_cancel_public = "Los equipos cambiaron, así que %s y %s finalmente no entran."
pt.joinpool_cancel_public = "Os times mudaram, então %s e %s não vão entrar afinal."

en.joinpool_failed_you = "The server could not put you on the team. You stay in the SUD Queue."
es.joinpool_failed_you = "El servidor no pudo hacer la entrada a los equipos. Sigue en la SUD Queue."
pt.joinpool_failed_you = "O servidor não conseguiu colocar você no time. Você continua na SUD Queue."

en.joinpool_expired_you = "You did not type !readyq in time and left the SUD Queue. Type !joinq to wait again."
es.joinpool_expired_you = "No se escribió !readyq a tiempo y salió de la SUD Queue. Con !joinq se vuelve a esperar."
pt.joinpool_expired_you = "Você não digitou !readyq a tempo e saiu da SUD Queue. Digite !joinq para esperar de novo."

en.joinpool_expired_other = "%s did not type !readyq in time. You stay in the SUD Queue."
es.joinpool_expired_other = "%s no escribió !readyq a tiempo. Sigue en la SUD Queue."
pt.joinpool_expired_other = "%s não digitou !readyq a tempo. Você continua na SUD Queue."

en.joinpool_expired_public = "Not ready in time: %s. Looking for another pair."
es.joinpool_expired_public = "No confirmaron a tiempo: %s. Buscando otro par."
pt.joinpool_expired_public = "Não confirmaram a tempo: %s. Procurando outro par."

en.joinpool_partner_left = "The other player left the SUD Queue. You stay in it."
es.joinpool_partner_left = "El otro jugador salió de la SUD Queue. Sigue en ella."
pt.joinpool_partner_left = "O outro jogador saiu da SUD Queue. Você continua nela."

en.joinpool_round_over = "The round is over, so the SUD Queue was cleared."
es.joinpool_round_over = "La partida terminó, así que se vació la SUD Queue."
pt.joinpool_round_over = "A partida terminou, então a SUD Queue foi esvaziada."

en.joinpool_no_access = "Only admins can switch the SUD Queue."
es.joinpool_no_access = "Solo los admins pueden activar o desactivar la SUD Queue."
pt.joinpool_no_access = "Só admins podem ligar ou desligar a SUD Queue."

en.joinpool_usage = "Usage: sud_joinpool on|off"
es.joinpool_usage = "Uso: sud_joinpool on|off"
pt.joinpool_usage = "Uso: sud_joinpool on|off"

en.joinpool_admin_off = "An admin switched the SUD Queue off for this round."
es.joinpool_admin_off = "Un admin desactivó la SUD Queue en esta partida."
pt.joinpool_admin_off = "Um admin desligou a SUD Queue nesta partida."

en.joinpool_admin_on = "An admin switched the SUD Queue back on."
es.joinpool_admin_on = "Un admin volvió a activar la SUD Queue."
pt.joinpool_admin_on = "Um admin ligou de novo a SUD Queue."

en.joinpool_admin_off_you = "The SUD Queue was switched off for this round, so you are no longer in it."
es.joinpool_admin_off_you = "La SUD Queue se desactivó en esta partida, así que ya no está en ella."
pt.joinpool_admin_off_you = "A SUD Queue foi desligada nesta partida, então você não está mais nela."

-- Skill Requirement (v1.6). The welcome and the refusals never name a region (author,
-- 2026-11-27). skill_spanish is sent in Spanish to everyone, so it is only in es.
en.cmd_sud_allow = "sud_allow <#id|name|Steam ID>: let a player play even below the skill requirement (admins)"
es.cmd_sud_allow = "sud_allow <#id|nombre|Steam ID>: dejar jugar a alguien aunque no llegue al nivel pedido (admins)"
pt.cmd_sud_allow = "sud_allow <#id|nome|Steam ID>: deixar alguém jogar mesmo abaixo do nível pedido (admins)"

en.cmd_sud_disallow = "sud_disallow <#id|name|Steam ID>: undo sud_allow (admins)"
es.cmd_sud_disallow = "sud_disallow <#id|nombre|Steam ID>: deshacer sud_allow (admins)"
pt.cmd_sud_disallow = "sud_disallow <#id|nome|Steam ID>: desfazer sud_allow (admins)"

en.skill_welcome_1 = "Welcome to NS2 SUD! Games here are semi-competitive, and most of our players speak Spanish or Portuguese, so it is hard for them to guide newcomers in English during a round."
es.skill_welcome_1 = "Bienvenido a NS2 SUD! Las partidas aquí son semicompetitivas y la mayoría de los jugadores habla español o portugués, así que es difícil guiar a los nuevos en inglés durante una partida."
pt.skill_welcome_1 = "Bem-vindo ao NS2 SUD! As partidas aqui são semicompetitivas e a maioria dos jogadores fala espanhol ou português, então é difícil orientar novatos em inglês durante uma partida."

en.skill_welcome_2 = "The NA and EU 10v10 servers are a great place to learn the game, and our Discord (in the server name) has tutorials and game guides."
es.skill_welcome_2 = "Los servidores 10v10 de NA y EU son un gran lugar para aprender el juego, y nuestro Discord (en el nombre del servidor) tiene tutoriales y guías del juego."
pt.skill_welcome_2 = "Os servidores 10v10 de NA e EU são um ótimo lugar para aprender o jogo, e nosso Discord (no nome do servidor) tem tutoriais e guias do jogo."

en.skill_welcome_3 = "You're welcome to stay and spectate, and we hope to see you on a team here soon!"
es.skill_welcome_3 = "Puede quedarse como espectador, y esperamos que pronto juegue en un equipo aquí."
pt.skill_welcome_3 = "Fique à vontade para assistir como espectador. Esperamos ver você num time aqui em breve!"

es.skill_spanish = "¿Habla español? Avise en el chat y un admin puede darle acceso para jugar."

en.skill_too_low = "Your Hive skill isn't high enough to play on this server yet. We ask for a tier %d badge (%s, Hive skill above %s), and our Discord has guides to help you get there."
es.skill_too_low = "Su habilidad Hive todavía no alcanza para jugar en este servidor. Pedimos una insignia de nivel %d (%s, habilidad Hive mayor a %s), y nuestro Discord tiene guías que le pueden ayudar a llegar."
pt.skill_too_low = "Sua habilidade Hive ainda não é suficiente para jogar neste servidor. Pedimos uma insígnia de nível %d (%s, habilidade Hive acima de %s), e nosso Discord tem guias para ajudar você a chegar lá."

en.skill_loading = "You can't join a team yet because your Hive skill hasn't loaded, and team shuffles and balance need it. Please wait a few seconds."
es.skill_loading = "Todavía no puede unirse a un equipo porque su habilidad Hive no cargó, y el sorteo y el balance de equipos la necesitan. Espere unos segundos."
pt.skill_loading = "Você ainda não pode entrar num time porque sua habilidade Hive não carregou, e o sorteio e o balanço dos times precisam dela. Aguarde alguns segundos."

en.skill_failed = "Your Hive skill didn't load. Reconnect to the server to try again."
es.skill_failed = "Su habilidad Hive no cargó. Vuelva a conectarse al servidor para intentarlo de nuevo."
pt.skill_failed = "Sua habilidade Hive não carregou. Reconecte ao servidor para tentar de novo."

en.skill_checking = "You can't join a team just yet: the server is still checking your account. Please wait a few seconds."
es.skill_checking = "Todavía no puede unirse a un equipo: el servidor sigue revisando su cuenta. Espere unos segundos."
pt.skill_checking = "Você ainda não pode entrar num time: o servidor ainda está verificando sua conta. Aguarde alguns segundos."

en.skill_admin = "%s (%s, T%d) is restricted. To let them play: sud_allow %s, or Sud Allow in the admin menu."
es.skill_admin = "%s (%s, T%d) está restringido. Para que pueda jugar: sud_allow %s, o Sud Allow en el menú de admin."
pt.skill_admin = "%s (%s, T%d) está restrito. Para deixar jogar: sud_allow %s, ou Sud Allow no menu de admin."

en.skill_admin_country = "%s (%s, %s, T%d) is restricted. To let them play: sud_allow %s, or Sud Allow in the admin menu."
es.skill_admin_country = "%s (%s, %s, T%d) está restringido. Para que pueda jugar: sud_allow %s, o Sud Allow en el menú de admin."
pt.skill_admin_country = "%s (%s, %s, T%d) está restrito. Para deixar jogar: sud_allow %s, ou Sud Allow no menu de admin."

en.allow_no_access = "Only admins can use sud_allow and sud_disallow."
es.allow_no_access = "Solo los admins pueden usar sud_allow y sud_disallow."
pt.allow_no_access = "Só admins podem usar sud_allow e sud_disallow."

en.allow_no_shine = "Shine's user list isn't available, so nothing was changed."
es.allow_no_shine = "La lista de usuarios de Shine no está disponible, así que no se cambió nada."
pt.allow_no_shine = "A lista de usuários do Shine não está disponível, então nada foi alterado."

en.allow_usage = "Usage: sud_allow <#id|name|Steam ID>. The #id is the number sh_status shows."
es.allow_usage = "Uso: sud_allow <#id|nombre|Steam ID>. El #id es el número que muestra sh_status."
pt.allow_usage = "Uso: sud_allow <#id|nome|Steam ID>. O #id é o número que o sh_status mostra."

en.disallow_usage = "Usage: sud_disallow <#id|name|Steam ID>. The #id is the number sh_status shows."
es.disallow_usage = "Uso: sud_disallow <#id|nombre|Steam ID>. El #id es el número que muestra sh_status."
pt.disallow_usage = "Uso: sud_disallow <#id|nome|Steam ID>. O #id é o número que o sh_status mostra."

en.allow_not_found = "No player found. Use the #id from sh_status, a name, or a Steam ID."
es.allow_not_found = "No se encontró al jugador. Use el #id de sh_status, un nombre o un Steam ID."
pt.allow_not_found = "Jogador não encontrado. Use o #id do sh_status, um nome ou um Steam ID."

en.allow_already = "%s is already in %s."
es.allow_already = "%s ya está en %s."
pt.allow_already = "%s já está em %s."

en.allow_other_group = "%s is in the Shine group %s, so they can already play. Nothing was changed."
es.allow_other_group = "%s está en el grupo de Shine %s, así que ya puede jugar. No se cambió nada."
pt.allow_other_group = "%s está no grupo do Shine %s, então já pode jogar. Nada foi alterado."

en.allow_done = "%s can now play here (added to %s)."
es.allow_done = "%s ya puede jugar aquí (agregado a %s)."
pt.allow_done = "%s já pode jogar aqui (adicionado a %s)."

en.allow_you = "An admin let you play on this server. Welcome!"
es.allow_you = "Un admin le dio acceso para jugar en este servidor. Bienvenido."
pt.allow_you = "Um admin liberou você para jogar neste servidor. Bem-vindo!"

en.disallow_not_in = "%s is not in %s."
es.disallow_not_in = "%s no está en %s."
pt.disallow_not_in = "%s não está em %s."

en.disallow_other_group = "%s is in the Shine group %s, not %s. Nothing was changed."
es.disallow_other_group = "%s está en el grupo de Shine %s, no en %s. No se cambió nada."
pt.disallow_other_group = "%s está no grupo do Shine %s, não em %s. Nada foi alterado."

en.disallow_done = "%s was removed from %s."
es.disallow_done = "%s fue quitado de %s."
pt.disallow_done = "%s foi removido de %s."
