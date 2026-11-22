# NS2 SUD Server Admin

Server administration quality of life for the NS2 Sudamerica server. No gameplay changes.
Mostly server side: since v1.2 the pause also runs a small part on players' machines, so the game
clock can stand still for everyone. It does nothing unless the server pauses. Disconnected players
have one small client part too, which sets up the use prompt for a player who takes over a body.
The join pool (v1.3) has one as well: the `SUD Queue` label on the scoreboard and the taskbar flash.

## Commands and language

- `!help` in chat lists every command of the mod in the player's console (and says so in
  chat).
- `!lang es`, `!lang pt` (or `!lang br`) and `!lang en` pick the language of the messages the mod
  sends to that player alone: English, Spanish or Portuguese. Remembered per Steam ID; English
  until set. Messages to everyone stay in English. The server cannot see the game's own language
  setting, which is why players pick it here.

Every chat command also works with `/`, and the typed command is hidden from everyone else. The
chat commands need Shine; console commands work without it. Languages are kept in
`SSM_Languages.json` in the server's config folder.

## Matches in a row

Built for a server with no queue, where players hand their slot to a waiting spectator after a few
games. The server counts how many rounds in a row each player has played and how many minutes they
played over them. Anyone can check:

- `!streakr` in chat gives the top 5 by rounds, and `!streakm` the top 5 by minutes (`/streakr`
  and `/streakm` work too). The answer is shown only to whoever typed it, and the typed command
  itself is hidden from everyone else:

  ```
  [NS2 SUD] Players sorted by rounds played
  1. Pepe  4r
  2. Bleu  4r
  3. Ana  3r
  4. Juan  3r
  5. Leo  2r
  ```

- `sud_streaks` in the console lists every player with a count, ranked both ways:

  ```
  Players sorted by rounds played
    1. Pepe  4r
    2. Bleu  4r
  ...

  Players sorted by minutes played
    1. Pepe  140m
    2. Bleu  128m
  ...
  ```

Only connected players are listed, and players at 0 are left out. Ties on rounds are broken by
minutes, and the other way round. Before any round has been counted, both commands say so in one
line. The console command works on its own; the chat commands need Shine. Nothing is enforced.

All of the mod's chat messages carry a magenta `[NS2 SUD]` tag.

- A round counts when the player was on Marines or Aliens at any moment of its first 2 minutes.
- Joining later than that is subbing in, and counts as sitting the round out: back to 0.
- Sitting a round out (spectator, ready room, not connected) puts the count back to 0.
- Rounds shorter than 1 minute don't count as a round: no round counts go up and nobody is reset.
  The time played in them is still added to the minutes of anyone already on a run.
- Counts only change when a round ends.
- Counts survive map changes and restarts. After 60 minutes with nobody playing a round they are
  forgotten, so each play session starts fresh.

### Server settings

`SSM_MatchesInARow.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `GracePeriodSeconds` | 120 | Being on a team this early in a round counts as playing it |
| `MinimumRoundSeconds` | 60 | Shorter rounds add minutes but not a round, and reset nobody |
| `ForgetAfterMinutes` | 60 | Counts are dropped after this long with nobody playing a round |

The counts themselves are kept in `SSM_MatchesInARowData.json` next to it.

## Spectator on connect

Everyone who connects starts as a spectator instead of in the ready room, and gets one private
line saying so. The server caps players who are not spectators (and people in total), so someone
idling in the ready room takes a player slot; starting everyone as a spectator keeps a slot freed
by a dropped player free until a spectator joins a team, which the game only allows while a
player slot is open.

- Always on, pregame included, except on Thunderdome: there everyone lands in the ready room as
  usual.
- Map changes are the exception: players who were on the server when the map ended land in the
  ready room as usual. Who was connected is kept in `SSM_SpectatorOnConnectState.json`.
- Bots, and anyone the game already put in a spectator slot, are left alone.
- Plugins that kick idle spectators (Devnull's AutoSpecKick, for example) should be off, since
  every newcomer is now a spectator.

## Commander match

Before the round starts, when someone takes the Marine or Alien chair and the other team has no
commander yet, everyone gets a chat message with the 5 players whose commander skill for the other
team is closest to the new commander's, and the gap:

```
[NS2 SUD] Bleu took Marine commander. Closest alien commanders:
1. Juan  +0
2. Pepe  +10
3. Ana  -20
4. LZZ  -35
5. Leo  +400
```

- A Marine commander is compared with everyone's Alien commander skill, and the other way round,
  using the game's own per-team commander skill.
- Anyone connected can be listed, on any team (the commander's own included) or spectating.
  Bots and players with a commander skill of exactly 0 (never commanded) are left out.
- `+` means that player is above the new commander, `-` below.
- At most one list every 30 seconds per commander on the same side. Switching between the Marine
  and Alien chair skips that wait, and another player taking a chair is never held back by it.
  Only in pregame: never during the countdown or when the round starts (the game logging the
  commanders back in at round start does not count).
- Off on Thunderdome unless `EnabledOnThunderdome` is set.
- Needs Shine for the chat message. Nothing is enforced.

### Server settings

`SSM_CommMatch.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `EnabledOnThunderdome` | `false` | `true` also posts the list on Thunderdome games |
| `IgnoredPlayers` | `[]` | NS2 IDs left out of the lists, for players who never command but carry a default commander skill. If one takes a chair, the list still goes out |

For example `{ "IgnoredPlayers": [ 37745947, 12345678 ] }`. The NS2 ID is the number Shine and
the Hive use for a player (the one in Shine's `UserConfig.json`). Changes apply from the next map.

## Pause

A pause for Thunderdome and passworded games, ported from Dragon's NSL Mod.

- Only on Thunderdome servers, or while the server has a password. A password counts when it is
  set with `sv_password`, Shine's `sh_password` or `!password`; the mod remembers it across map
  changes. **A password from the server's launch settings cannot be seen by the mod.**
- When a round starts, everyone gets `THUNDERDOME DETECTED: PAUSE ENABLED` or
  `PASSWORDED GAME DETECTED: PAUSE ENABLED`.
- Any player on a team, during a round: `pause` or `!pause` in chat, or `gpause` in the console.
  After a countdown the game freezes; chat, voice, the scoreboard, the minimap and menus keep
  working. On a server without a password, `!pause` answers privately that pausing is not
  available there (plain `pause` stays quiet, since it may just be talk).
- To resume, someone on each team types `unpause` (or `!unpause`, `resume`, `!resume`); typing it
  again un-readies the team. The game resumes on its own after `AutoResumeAfter` seconds.
- Each team has `PausesPerTeam` pauses per round. The command chair cannot be entered or left
  while paused.
- When a team player disconnects, the game pauses by itself (`PauseOnDisconnect`). That uses one
  of the team's pauses, and pauses even when the team has none left.
- Works without Shine: the pause's chat lines fall back to the game's own chat.

### Server settings

`SSM_Pause.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `PauseEnabled` | `true` | `false` turns the pause off everywhere, Thunderdome included |
| `PausesPerTeam` | 4 | Pauses per team per round |
| `PauseCountdown` | 5 | Seconds between pausing and the game freezing |
| `ResumeCountdown` | 5 | Seconds between both teams being ready and the game resuming |
| `AutoResumeAfter` | 300 | Seconds paused before the game resumes on its own; 0 = never |
| `ReadyReminderInterval` | 30 | Seconds between reminders of who still has to ready up |
| `PauseOnDisconnect` | `true` | Pause when a team player disconnects |

Whether the server has a password is kept in `SSM_PauseState.json` next to it.

## Disconnected players

On every server, ported from Dragon's NSL Mod.

- When a player on a team disconnects during a round, their player stays where it was as
  `[D/C] Name`, with its lifeform, upgrades, weapons, jetpack or Exo, health, personal resources
  and the command chair. It can be killed.
- **They reconnect while it is still there:** they go straight back into it. Spectator on
  connect leaves them alone.
- **Someone joins that team:** they take the body over, with everything in it. Then the original
  starts as a spectator as usual when they come back.
- **`sud_swap <player> <player>`** in the console puts a player into a disconnected player's body,
  or swaps two connected players' places. A player is a name, part of one, or a Steam ID.
  - One of the two must be a spectator or in the ready room: it never swaps two players who are
    both on a team (or two disconnected bodies).
  - The server console and Shine admins with `sud_swap` in their group's commands can use it on
    any team. A group that allows everything already has it.
  - Commanders can swap a player on their own team (or a disconnected body on it) with a
    spectator or someone in the ready room.
- The body, with its gear and resources, stays where it is; the person moves. Scoreboard stats
  and Hive skill go with the person.
- A disconnected player's body keeps its player slot, so the player cap holds: the only way to
  use that slot is to take the body over. Lockteams still blocks joining; `sud_swap` works on
  locked teams.
- Bodies nobody took are removed when the round resets.

### Server settings

`SSM_SavedPlayers.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `Enabled` | `true` | `false`: disconnecting players are not kept (`sud_swap` still swaps players) |

## Join pool

During a live 6v6 or 7v7 round, players waiting to get in no longer need an admin to pair them.

- **`!joinq`** (spectators and the ready room, live rounds only) puts a player in the join pool.
  The scoreboard shows them as `SUD Queue`. `!exitq` leaves it, `!listq` lists who is in it.
- When two players in the pool can join, one per team, and keep the difference between the team
  averages within 75 elo, everyone else sees who they are and the difference now and after, and
  the two are asked privately to type **`!readyq`** within 30 seconds. Their game window flashes on
  the taskbar.
- Team averages: fielders at their field skill for that team, commanders at their commander skill
  for that team. Marine and alien skill differ per player, so every pair is tried both ways round;
  the pair and way round that leaves the smallest difference wins. If the game is already further
  apart than 75, a pair that brings it closer is allowed.
- Once both typed `!readyq`, the pair is checked again against the teams as they are then and put
  in. They join like anyone else (respawn queue, no instant spawn). The lock is lifted for those
  two joins and put straight back, without a chat message.
- **Needs Lockteams, with the teams locked.** Without a lock people come and go freely and break
  the pairing, so `!joinq` is refused unless [Shine] Lockteams V2 is running and the teams are
  locked. If an admin unlocks the teams mid-round, the pool keeps everyone but pauses (they are told
  once, and a pair waiting on `!readyq` is cancelled) until the teams are locked again.
- **Not before 30 seconds into the round.** `!joinq` works from the start, but the first pair is only picked 30 seconds in, from everyone who asked by then, so it is not a race to type `!joinq` first. Players who join the pool earlier are told how long is left.
- Whoever does not type `!readyq` in time leaves the pool; whoever did stays and can be paired again.
- The command is `!readyq`, not `!ready`, so it never mixes with Shine's tournament mode ready-up
  (v1.3c: on the live 8v8, the pool's `!ready` did not get through).
- Uneven teams (usually someone who crashed, whose body Disconnected players keeps) and 8v8 are
  left alone, and so is a team holding a disconnected body.
- The pool empties when the round ends. Players in it are not kicked by Shine's AFK kick while they
  wait; the 30-second `!readyq` deadline catches anyone who walked away.
- It is on by default. **`sud_joinpool off`** / **`on`** in the console switches it for the rest of
  the round; the next round starts on again. The server console and every Shine admin (anyone in
  a Shine user group) can use it, with no config change.

### Server settings

`SSM_JoinPool.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `Enabled` | `true` | `false`: the join pool is off |
| `EnabledOnThunderdome` | `false` | `true` also runs it on Thunderdome games; an admin's `sud_joinpool on` turns it on there for one round |
| `MaxDifference` | `75` | largest team-average difference a pair may leave |
| `ReadySeconds` | `30` | time the pair has to type `!readyq` |
| `OfferDelaySeconds` | `30` | no pair is offered before this many seconds into the round, so the best pair of everyone who asked is picked, not the first two |
| `TeamSizes` | `[6, 7]` | team sizes (per team, both equal) the pool runs at |
