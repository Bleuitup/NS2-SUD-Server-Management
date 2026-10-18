# NS2 SUD Server Management

Server administration quality of life for the NS2 Sudamerica server. No gameplay changes.

## Matches in a row

The scoreboard shows, in light gray in front of each name, how many rounds in a row that player
has played and how many minutes they played over those rounds:

```
[3r 95m] Bleu
```

Built for a server with no queue, where players hand their slot to a waiting spectator after a few
games. The tag only informs; nothing is enforced.

- The tag shows in the pregame and after a round ends, and is hidden while a round is played.
- A round counts when the player was on Marines or Aliens at any moment of its first 2 minutes.
- Joining later than that is subbing in, and counts as sitting the round out: back to 0.
- Sitting a round out (spectator, ready room, not connected) puts the count back to 0.
- Rounds shorter than 3 minutes are void. Counts only change when a round ends.
- Counts survive map changes and restarts. After 60 minutes with nobody playing a round they are
  forgotten, so each play session starts fresh.

### Commands (need Shine)

`sh_freqplayers` in the console, or `!freqplayers` in chat, lists the 5 connected players with the
most rounds in a row and the 5 with the most minutes. Open to everyone. The chat version is only
shown to whoever typed it.

### Server settings

`SSM_MatchesInARow.json` in the server's config folder, created on first run:

| Setting | Default | Meaning |
| --- | --- | --- |
| `GracePeriodSeconds` | 120 | Being on a team this early in a round counts as playing it |
| `MinimumRoundSeconds` | 180 | Shorter rounds change nothing |
| `ForgetAfterMinutes` | 60 | Counts are dropped after this long with nobody playing a round |

The counts themselves are kept in `SSM_MatchesInARowData.json` next to it.

## Compatibility

Works with the vanilla scoreboard and with Devnull's Enhanced ScoreBoard. It does not replace any
game file. Shine is optional and only needed for the commands.
