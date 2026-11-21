# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## What this is

**NS2 SUD Server Admin (SSM; the GitHub repo is still named NS2-SUD-Server-Management)** is a standalone Natural Selection 2 mod for administrative
quality of life on the NS2 Sudamerica server. **No gameplay changes, ever.** It is deliberately
not a Shine extension: the author finds standalone mods easier to debug.

`README.md` is the server-admin facing doc; this file is for development. The Workshop description
lives in `mod.settings` and is written for players, not coders.

## Layout

NS2 Launch Pad layout, matching the author's other mods:

```
mod.settings                       Workshop metadata and description (never put a backslash in it)
preview.jpg                        Workshop preview, 512x512 (author's GPT artwork; Launch Pad scales it to 512)
source/lua/entry/SSM.entry         entry: Shared, Server and Client (since v1.2: the pause, and Saved Players' client fix)
source/lua/SSM/Shared.lua          loads Pause/Shared.lua (server, client and predict)
source/lua/SSM/Client.lua          loads Pause/Client.lua and SavedPlayers/Client.lua
source/lua/SSM/Server.lua          loads the shared files, then each feature's server file
source/lua/SSM/Messages.lua        the mod's chat voice ([NS2 SUD], magenta), console print, languages
source/lua/SSM/Strings.lua         every private text in English, Spanish and Portuguese
source/lua/SSM/Commands.lua        chat command router (Shine PlayerSay), !help, !lang
source/lua/SSM/<Feature>/...       one folder per feature
test/matchesinarow.lua             logic test, runs outside the game (also !lang and !help)
test/spectatoronconnect.lua        logic test for Spectator On Connect
test/commmatch.lua                 logic test for Commander Match
test/pause.lua                     logic test for the pause's server part
test/savedplayers.lua              logic test for Saved Players (with Spectator On Connect)
output/                            Launch Pad build output, gitignored
```

Build before publishing (no compile step): `rm -rf output && mkdir -p output && cp -r source/. output/`.
Launch Pad rewrites `mod.settings` on publish. Workshop id `3822092803` (`publish_id`, first published
2026-10-18). On that first publish Launch Pad refused the hand-written file; the author deleted it,
published, and the description was restored from git afterwards. Keep `image = "preview.jpg"` in it.

New features get their own folder under `lua/SSM/` and a line in `SSM/Server.lua`. Their chat
commands go through `SSM.AddChatCommand` and are listed for `!help` with `SSM.ListCommand`;
their private texts go in `Strings.lua` in all three languages. A feature that
needs client code or network messages adds `Client` / `Shared` (and `FileHooks` if needed) back to
the entry with matching loaders; network messages belong in a Shared script so server and client
register them in the same order.

## Feature: Matches In A Row

Counts rounds in a row and minutes played over them. `sud_streaks` (console) lists every
connected player with a count, ranked by rounds and by minutes; `!streakr` and `!streakm` (chat,
caller only) give the top 5 by rounds and by minutes. Built for a server with no
queue (16 players + 5 spectators) where players hand their slot to a spectator after 3-4 games.
Information only; never make it enforce anything.

**History:** v1 showed a `[3r 95m]` tag in front of names on the scoreboard. After feedback from
fellow admin LZZ the author scrapped the scoreboard entirely (2026-10-18), keeping only the
commands. Do not bring the tag back without being asked. The scoreboard code is in git history
(`6a4a488`) if it is ever wanted again, including how it coexisted with Devnull's Enhanced
ScoreBoard.

### Rules (agreed with the author, do not change without asking)

- A round counts for a player who was on Marines or Aliens at any moment of its first
  `GracePeriodSeconds` (120). Leaving and coming back later does not undo that, so hopping to the
  spectators mid-round cannot wipe a count.
- Anyone who first joins after the grace period is a **sub, and gets 0**: the round counts as one
  sat out. The author wants subbing in rewarded.
- Sitting a round out (spectator, ready room, absent) resets to 0.
- Rounds shorter than `MinimumRoundSeconds` (60, the author's pick: the threshold for skill
  changes) do not count as a round: no round count goes up and nobody is reset. Their time still
  counts: it is added to the minutes of anyone already on a run, even if it is under a minute.
  Time is kept in seconds and only rounded to minutes for display.
- Minutes are the player's own seconds on a team, summed over the rounds in the count. They are
  **not a tiebreak in the author's eyes**: with few games a night, equal rounds usually mean equal
  play, and minutes are what show a very short outlier round. (Ranking ties are still broken by
  the other value.)
- **Counts only change at round end**, because that is when the server decides who spectates.
- **Counts last one play session**: kept across map changes and restarts, dropped after
  `ForgetAfterMinutes` (60) with nobody playing a round. The author confirmed 60 minutes; rounds
  of 70+ minutes do happen, which is why activity is re-saved during rounds.
- **Command names are the author's pick**: `sud_` prefix for console commands (not Shine's
  `sh_`), chat command without the prefix. Names like `playerranks` were rejected because they
  read as skill ranks.
- **Asked mid-round, the commands show the ranking from the last finished round**, which falls
  out of counts only changing at round end. The author wants them answering at any time.
- **The commands are open to everyone**, for transparency. Ranked by rounds (ties by minutes,
  then name) and by minutes (ties by rounds, then name), connected players with a count only.
  **The console gets the full list** (the author: the console has room for all 16 players), one
  player per line. **Chat has one command per ranking** (1.0b, the author's pick, to save chat
  space): `!streakr` = top 5 by rounds, `!streakm` = top 5 by minutes, one player per chat line,
  because chat is small. `!streaks` was dropped before anyone used it. Each list shows only the value it is
  sorted by. Headers read "Players sorted by rounds played" / "... minutes played" (author's
  wording). Before any round, both commands answer the caller with one line instead.
- **The commands make no noise for others** (1.0b): no Shine admin-log line, and the typed
  chat command is dropped from public chat.
- **Every chat message from the mod uses the `[NS2 SUD]` tag in magenta** (`SSM.Notify` / `SSM.NotifyAll` in
  `Messages.lua`), the same magenta as Hive Spawn Selector's tag. One voice for all features;
  headers carry the tag, rows under them do not.

### How it works (`MatchesInARow/Server.lua`)

- Samples once a second from `Event.Hook("UpdateServer")`: who is on team 1/2, keyed by Steam ID
  (`client:GetUserId()`), bots skipped. Its own bookkeeping rather than `ScoringMixin` play
  time, so a disconnect mid-round loses nothing.
- Round start is seen in that loop (`GetGameStarted()` turning true). Round end is a post-wrap of
  `NS2Gamerules:EndGame` via `Class_ReplaceMethod`. A round that stops being Started without
  `EndGame` (reset, map change) is discarded.
- At round end the new count table is built from scratch out of the players who were there from
  the start; everyone else simply has no entry, which is what 0 is.
- The server Lua restarts on every map change, so counts are saved to
  `config://SSM_MatchesInARowData.json` (a list, because JSON object keys come back as strings)
  and loaded at startup. `ForgetAfterMinutes` is checked on load **and** at round start (the
  server can sit idle on one map for hours), measured from `LastActiveAt`. That is set and saved
  at round start, every `kActiveSaveSeconds` (300) during a round, and at round end, so a restart
  65 minutes into a 70-minute round still keeps the counts.
- **The commands are not Shine commands** (changed in 1.0b): Shine's `RunCommand` prints
  "X ran command ..." to every client with `sh_seelogechos` after each command, and there is no
  flag to stop it. `sud_streaks` is a plain game console command
  (`Event.Hook("Console_sud_streaks")`, works without Shine, prints with `ServerAdminPrint`, or
  `Shared.Message` from the server console). `!streakr` / `!streakm` (and with `/`) go through the
  shared chat router (`Commands.lua`, below). Chat lines are separate messages because a single
  chat message cannot hold line breaks.

## Shared: chat commands, !help and !lang (`Commands.lua`, `Messages.lua`, `Strings.lua`)

- **One chat router for every feature.** `Shine.Hook.Add("PlayerSay", "SSM_Chat", ...)` - not a
  Shine plugin, not Shine commands, so no admin-log line - matches `!word` or `/word` (any case,
  arguments after a space), runs the handler and returns `""` so nobody else sees the typed
  command. Unknown words are left alone. The hook is added on the first `UpdateServer`, because
  load order between mods is not guaranteed - the same opportunistic pattern Hive Spawn Selector
  uses for CustomSpawns.
- **`!help`** (author's request, 2026-11-16; first built as `!commands`, renamed because "!help" is shorter and everyone knows the word): one private chat
  line saying the list is in the console, and the list in the caller's console: every command
  registered with `SSM.ListCommand`, marked chat or console, `!help` and `!lang` included.
- **Private messages follow the player's language** (author's request, 2026-11-16): English,
  Spanish or Portuguese; everything else is English, and messages to everyone stay English.
  **The server cannot see the game's language** (client-side only; Shine translates on the
  client; the Hive data has no country), so the author chose **`!lang es|pt|br|en`**, remembered
  per Steam ID in `config://SSM_Languages.json` (string keys; English is not stored). The other
  options were a Steam-profile-country lookup (needs a Web API key, often wrong) and a client file
  sending the language (would end the "no client files" whitelist pitch).
- **Texts live in `Strings.lua`**, all three languages side by side; missing keys fall back to
  English. Spanish avoids "tú" and "vos" where it can (players from all over the region) and calls
  rounds in a row **"partidas sucesivas"** (the author's term); the round unit is `p`. Portuguese is
  Brazilian. Not reviewed by a native speaker yet.

## Feature: Spectator On Connect (`SpectatorOnConnect/Server.lua`)

Everyone who connects starts as a spectator instead of in the ready room. Built 2026-11-16,
released in v1.1 (2026-11-19).

- **Why:** the server caps non-spectators (16) and people in total (21), not spectators
  (the author: 12 players + 9 spectators is possible). Someone in the ready room uses one of the
  16, so a newcomer idling there could take the slot of a player who dropped mid-round. Joining
  a team from spectator is only let through while a player slot is free (vanilla
  `Gamerules:GetCanJoinPlayingTeam`).
- **Always**, pregame included (author's pick). Bots and clients the game already put in a
  spectator slot are left alone.
- **Map changes are exempt** (author's pick): every client reconnects then. Who is connected is
  saved every 5 s to `config://SSM_SpectatorOnConnectState.json` (anyone seen in the last 30 s, so
  clients dropped in the last frames of a map are not lost). If that save is under 2 minutes old
  when the map loads, those players land in the ready room on their first reconnect within 5
  minutes. A later reconnect (a crash) is moved like anyone else.
- **One private line** to the moved player, 5 s after connecting so it arrives in game, in their
  language: "You start as a spectator. Join a team when a player slot is free."
- Post-wrap of `NS2Gamerules:OnClientConnect` (which vanilla already uses to move spectator-slot
  clients); the move is `JoinTeam(player, kSpectatorIndex, true)`, which also calls
  `SetIsSpectator(true)` and so frees the player slot. Runs in a `pcall` so an error can never
  break a connect.
- The author will disable Shine-Epsilon readyroomqueue / Devnull AutoSpecKick if the live server
  runs them (AutoSpecKick could kick idle spectators, which every newcomer now is).

## Feature: Commander Match (`CommMatch/Server.lua`; built 2026-11-16, released in v1.1)

Before the round starts, when someone takes a command chair and the other team has no human
commander yet, everyone gets a chat message with the 5 players whose commander skill **for the
other team** is closest to the new commander's, with the signed gap. Information only.

### Rules (author's picks, 2026-11-16)

- **Everyone sees it** (`SSM.NotifyAll`, Shine broadcast).
- **Anyone connected can be listed**, any team, the commander's own team and spectators included.
  Bots never.
- **Players with a commander skill of exactly 0 are left out** (the Hive's "never commanded").
  Not the vanilla fallback to field skill. A new commander at 0 gets no message.
- **Cooldown per player, 30 s** (author, 2026-11-19; was 60 s server-wide): the same commander
  gets at most one list every 30 s on the same side. Switching side (Marine to Alien chair or back)
  skips it, and another player taking a chair is never held back by it ("we can always manually
  enforce"). Kept per Steam ID with the side of the last list.
- **Only the gap is shown**, not the skill numbers (`+` = above the commander, `-` = below).
  Sorted by smallest gap, ties by name.
- **Ignored players** (author, 2026-11-19, 1.1b): some players never command but carry a default
  commander skill, which the "exactly 0" rule cannot catch. Admins list their NS2 IDs
  (`client:GetUserId()`, numbers or numbers as text) in `IgnoredPlayers` in
  `config://SSM_CommMatch.json` (written empty on first run, read when the map loads). Ignored
  players are never listed. If one takes a chair, the list still goes out as for anyone (the
  author's pick, 2026-11-19; first built silent).

### How it works (`CommMatch/Server.lua`)

- Per-team commander skill is the game's own formula (`ScoringMixin:GetCommanderTeamSkill`):
  Marines `commSkill + commSkillOffset`, Aliens `commSkill - commSkillOffset`. Computed from the
  raw fields so it works for players on any team. The skill fields carry over when a player is
  replaced (`ScoringMixin:CopyPlayerDataFrom`), so the Commander entity has them.
- Post-wrap of `CommandStructure:LoginPlayer` via `Class_ReplaceMethod`; it returns the new
  Commander entity. `CommandStation:LoginPlayer` overrides it but calls
  `CommandStructure.LoginPlayer` inside, so both chairs pass through. The feature runs in a
  `pcall` so an error can never break a login.
- **Only in pregame** (author, 2026-11-19): game state `NotStarted`, `WarmUp` or `PreGame`, never
  `Countdown` or later. **Forced logins are ignored**: at round start `NS2Gamerules:ResetGame`
  rebuilds the map and calls `commandStructure:LoginPlayer(player, true)` for both commanders
  while the state is still `PreGame` and the other chair is briefly empty, which made 1.1 post
  the list again at round start (fixed in 1.1b).

## Feature: Pause (`Pause/Shared.lua`, `Pause/Server.lua`, `Pause/Client.lua`; v1.2)

Ported from Dragon's NSL Mod (https://github.com/xToken/NSL, `lua/NSL/pause/*`), first for Blast
to the Past v3.01 (never released there), handed over to SSM on 2026-11-20 when the author moved
every QoL feature out of B2TP. The handover notes and the B2TP code as it was are in
`docs/handoff/td-pause-reconnect/`. Credit Dragon in the description (the author asked).

### Rules (author's picks, 2026-11-20)

- **Only on Thunderdome or with a server password.** Password = `sv_password`, Shine's
  `sh_password` or `!password`; all three call `Server.SetPassword`, which the mod wraps. The
  engine keeps the password across map changes but the server Lua does not, so it is saved to
  `config://SSM_PauseState.json` every 5 s and trusted on load only if under 120 s old (a restart
  drops a password set with `sv_password`; a quick restart could leave pausing on for one map).
  **A password from the launch settings is invisible** (no getter in the engine API).
- **Round-start line to everyone:** `THUNDERDOME DETECTED: PAUSE ENABLED` /
  `PASSWORDED GAME DETECTED: PAUSE ENABLED` (author's wording), from a post-wrap of
  `NS2Gamerules:SetGameState` on the change to Started.
- Pause rules as built for B2TP: any team player during a round, 5 s countdown, both teams ready
  to resume (toggle, 2 s per team), auto-resume 300 s, reminders every 30 s, 4 pauses per team per
  round, counts cleared at round reset, chair blocked while paused or pausing, log lines, no admin
  override. Pause on disconnect (default on) uses a team pause but pauses even with none left.
- `!pause` / `gpause` on a server where pausing is off answer privately; plain `pause` stays
  quiet (may be talk). Messages to everyone are English; private ones use `Strings.lua`.

### How it works

- **The machinery is installed on every server** and is inert unless paused: the three Player
  network fields (always, so client and server layouts match), the `Shared.GetTime` /
  `GetPreviousTime` replacement, input/move/buy blocks, entity freezing. Only the command and the
  disconnect pause check `SSMPause_GetAllowedReason()`. That is why there is no gate on clients:
  they follow the `gamepaused` field the server sets.
- Chat words go through vanilla `ProcessSayCommand` (every chat message reaches it), not the SSM
  router, so they work without Shine (Thunderdome). The router does not claim them, so with Shine
  they still pass through. Chat lines use `SSM.Notify` / `NotifyAll` with `always`, which fall back
  to the game's own chat (`[NS2 SUD]` as the name) without Shine.
- `SSMPause_ReplaceMethod` (Shared) replaces in a class and its derived classes and skips names
  missing in the build; Saved Players uses it too.

## Feature: Saved Players (`SavedPlayers/Server.lua`, `SavedPlayers/Client.lua`; v1.2)

NSL's statesave (`lua/NSL/statesave/server.lua`), same history as the pause. Server side, plus
one client fix (below).

### Rules (author's picks, 2026-11-20)

- **On every server**, Thunderdome, passworded or not.
- A team player disconnecting mid-round leaves their player as `[D/C] Name`, held by a virtual
  placeholder client: gear, lifeform, pres, health, chair. Killable. Removed at round reset.
- **Original reconnects while held: straight back in.** Spectator On Connect's `ShouldMove` asks
  `SSM.SavedPlayers_IsHeld(steamId)` and leaves them alone.
- **Anyone joining a team that holds a body takes it over** ("equivalent to sud_swap, to
  simplify"), on every server, the oldest body first. The original then lands in spectator as
  usual and gets back in through `sud_swap`.
- **`sud_swap <player> <player>`** (console): a player into a held body (NSL's
  `sv_nslreplaceplayer`), or two connected players swap places (not in NSL). **One target is
  always a spectator or in the ready room** (author, 2026-11-20): never two players on teams, so
  never two held bodies either. Access: server
  console and Shine admins with `sud_swap` (`Shine:HasAccess`, which does not need a registered
  command); commanders for their own team only, the other target a spectator or in the ready room.
  Targets by Steam ID, exact name, then unique partial name; ambiguity lists the matches.
- **The body stays, the person moves.** ScoringMixin data (score, kills, play times, Hive skill)
  follows the person: `ScoringMixin.CopyPlayerDataFrom` only assigns fields, so it copies into
  and out of a plain table. A person whose body someone else plays has theirs kept in `Stash` and
  gets it back when they get a body again. The disconnect stand-in gets the person's data first,
  because vanilla logs the disconnecting client's round from it.
- **Slots:** the engine counts the placeholder as a player. The mod also counts held bodies on
  top of the humans, so the cap holds whether or not the engine does. A join that takes over a
  body bypasses the slot check and even teams (`joiningHeldTeam`), because it adds nobody.
  Lockteams (Shine `JoinTeam` hook) still blocks unforced joins; `sud_swap` joins forced.

### How it works

- Wraps (all `Class_ReplaceMethod` on `NS2Gamerules` unless noted): `OnClientDisconnect` (keep
  the body, NSL), `OnClientConnect` (placeholders get no player; the original goes back in),
  `JoinTeam` (takeover after a successful join), `Gamerules.GetCanJoinPlayingTeam` and
  `GetCanJoinTeamNumber` (slots), `ResetGame`, `RagdollMixin.OnTag` and
  `Player.GetDestructionAllowed` (a held body is not removed).
- Two connected players swap by exchanging controllers, then fixing each client's spectator flag
  (`client:SetIsSpectator`, not `Player:SetIsSpectator`, which would JoinTeam), names and stats.
- **Names are assigned directly** (`.name`), not with `Player:SetName`, when a person moves into a
  body or two people swap: `SetName` makes names unique, and the other entity still holding the
  name turned the first one into "Name (2)" (GitHub issue #1, LZZ, found on the 8v8 test).
- **Client fix (`SavedPlayers/Client.lua`):** the use prompt (`actionIconGUI` plus
  `lastAlien/MarineActionFindTime`) is only set up by `AlienActionFinderMixin`,
  `MarineActionFinderMixin` and `ReadyRoomPlayer` when the entity is created as the local player,
  so a client handed an existing entity hit a nil every move (issue #1). A `LocalPlayerChanged`
  hook (the event the game runs `OnInitLocalClient` from) creates it for the new player, only when
  controlling (not first-person spectating), and destroys the one left on the previous player.
- Untested in game: placeholders and the 21-person connection cap (a full server might keep the
  original from reconnecting), Thunderdome auto-concede, NS2+ stats, commander bodies.

## Open threads (remind the author)

- **v1.2 built on `feat/v1.2-pause-saved-players`, not tested in game, not published:** the
  pause (Thunderdome and passworded games) and saved players (every server), with `sud_swap`.
  First release with client files. Description drafted in `mod.settings`, including the Dragon
  credit line - the author to review.

- **v1.1b published and tagged 2026-11-20** (`7927ba4`, `main`; the author: "this will all be
  1.1b", no separate 1.1a): Commander Match no longer posts at round start (forced re-logins
  ignored, pregame states only), and admins can ignore players by NS2 ID. That publish also
  carried the 1.1 description to the Workshop page.
- **v1.1 published and tagged 2026-11-19** (`0ad93c0`): Spectator On Connect, Commander Match,
  `!help`, `!lang`.
- Add the NS2 IDs to ignore to `SSM_CommMatch.json` on the live server.
- Spanish and Portuguese texts in `Strings.lua` not reviewed by a native speaker yet.
- AutoSpecKick off on the live server (the author's call).
- Commander Match should use the shared chat router if it ever gets commands.

Parked or dropped (2026-11-16):

- **Round credit - parked, not short term** (the author: "we don't play that many in a row").
  Idea: spectating a round takes 3 off the count instead of resetting to 0; the first 10 to
  connect in a fresh session start at -1 (seeders). Open questions if it returns: -3 from the
  current count or reset-then-3; who counts as sitting out; subs as -3; whether -3 stacks;
  minutes as a session total.
- **Extra badge - dropped.** (It was a Shine badge-config change, not a mod: badges without a
  column land in column 5.)

## Planned (author's ideas, not built yet)

- Reminder messages so players learn the commands (now there is `!help` to point them to).

## Testing

- `luac -p` every file (Lua 5.4 at `C:\Users\maost\AppData\Local\Programs\Lua\bin\`; NS2 runs
  LuaJIT/5.1, so this proves parsing only).
- `lua test/matchesinarow.lua` from the repo root runs the real server file against stubbed
  globals: counting rules, void and reset rounds, saving and loading, expiry, the long-round
  restart, top-5 limits and the commands, plus `!lang` (saving, reload, br, unknown, back to
  English, Spanish answers) and `!help`.
- `lua test/spectatoronconnect.lua`: who is moved, bots and spectator slots left alone, the
  delayed line in the player's language, someone leaving first, an error not breaking the
  connect, the map-change exemption (used once, window, old save, empty last frames).
- `lua test/commmatch.lua` does the same for Commander Match: who is listed, order and gaps, the
  cooldown, the other chair taken, round started, commander at 0, bots, no Shine, and an error
  not breaking the login.
- `lua test/pause.lua`: when pausing is allowed (pub, password set and removed, remembered across
  a map change, not after a restart, Thunderdome, the off switch), the round-start line, pause and
  resume with their chat lines, the per-team limit and round reset, pause on disconnect, and the
  game-chat fallback without Shine. Not the frozen world itself.
- `lua test/savedplayers.lua`: who is kept, the held slot, Lockteams, taking over by joining
  (gear stays, name and stats follow the person), reconnecting straight back in with Spectator On
  Connect leaving them alone, `sud_swap` (access, commander rule, names, swap back with stats),
  round reset, the off switch. Not the engine hand-over itself.
- Real behavior has to be checked on a server (Launch Pad listen server with Shine loaded). No
  test-only console commands.

## Whitelisting

**Whitelisted** (requested from Ghoul for v1.0b, granted by 2026-11-08). The Workshop description
says so in bold on its first line, as the author's other whitelisted mods do.

The request described the mod as server-side only, with no client files and no network messages.
Anything that would change that (bringing back the scoreboard tag, for example) is worth raising
with Ghoul rather than slipping into an update. Before it was whitelisted, running it on the live
server made the server unranked and switched off consistency checking, which let some players'
client mods desync and drop them.

**v1.2 changes that** (the pause adds Shared and Client files and three Player network fields).
The author decided on 2026-11-20 to go ahead and rewrite the description rather than ask first:
Dragon's NSL Mod is whitelisted and does the same, and Dragon is no longer around.

## Versioning

Letter steps for fixes to existing features (v1.0 -> v1.0a -> v1.0b), the author's choice; new features step the number (v1.1: Spectator On Connect, Commander Match, !help, !lang - agreed 2026-11-19; v1.2: pause and saved players). Tag
`vX.Y` (annotated, `"vX.Y - Workshop release"`) only after the author says the Workshop publish
is live.
