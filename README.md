# NS2 SUD Server Admin

Server administration quality of life for the NS2 Sudamerica server. No gameplay changes.
Server side only: none of its code runs on players' machines.

## Matches in a row

Built for a server with no queue, where players hand their slot to a waiting spectator after a few
games. The server counts how many rounds in a row each player has played and how many minutes they
played over them. Anyone can check the top of both lists:

- `!streaks` in chat (the answer is only shown to whoever typed it)
- `sud_streaks` in the console

```
Most rounds in a row: Bleu 4r, Pepe 4r, Juan 3r, Ana 3r, Leo 2r
Most minutes in a row: Pepe 140m, Bleu 128m, Ana 101m, Juan 95m, Leo 60m
```

Only connected players are listed. Ties on rounds are broken by minutes, and the other way round.
The commands need Shine; without it the counting still runs but there is no way to see it.
Nothing is enforced.

- A round counts when the player was on Marines or Aliens at any moment of its first 2 minutes.
- Joining later than that is subbing in, and counts as sitting the round out: back to 0.
- Sitting a round out (spectator, ready room, not connected) puts the count back to 0.
- Rounds shorter than 3 minutes are void. Counts only change when a round ends.
- Counts survive map changes and restarts. After 60 minutes with nobody playing a round they are
  forgotten, so each play session starts fresh.

### Server settings

`SSM_MatchesInARow.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `GracePeriodSeconds` | 120 | Being on a team this early in a round counts as playing it |
| `MinimumRoundSeconds` | 180 | Shorter rounds change nothing |
| `ForgetAfterMinutes` | 60 | Counts are dropped after this long with nobody playing a round |

The counts themselves are kept in `SSM_MatchesInARowData.json` next to it.
