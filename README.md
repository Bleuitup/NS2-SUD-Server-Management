# NS2 SUD Server Admin

Server administration quality of life for the NS2 Sudamerica server. No gameplay changes.
Server side only: none of its code runs on players' machines.

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
