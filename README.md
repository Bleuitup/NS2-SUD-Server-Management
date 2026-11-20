# NS2 SUD Server Admin

Server administration quality of life for the NS2 Sudamerica server. No gameplay changes.
Server side only: none of its code runs on players' machines.

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

- Always on, pregame included.
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
- Needs Shine for the chat message. Nothing is enforced.

### Server settings

`SSM_CommMatch.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `IgnoredPlayers` | `[]` | NS2 IDs left out of the lists, for players who never command but carry a default commander skill. If one takes a chair, the list still goes out |

For example `{ "IgnoredPlayers": [ 37745947, 12345678 ] }`. The NS2 ID is the number Shine and
the Hive use for a player (the one in Shine's `UserConfig.json`). Changes apply from the next map.
