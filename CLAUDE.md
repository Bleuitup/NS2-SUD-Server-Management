# CLAUDE.md

Guidance for AI assistants and contributors working in this repository.

## What this is

**NS2 SUD Server Management (SSM)** is a standalone Natural Selection 2 mod for administrative
quality of life on the NS2 Sudamerica server. **No gameplay changes, ever.** It is deliberately
not a Shine extension: the author finds standalone mods easier to debug.

`README.md` is the server-admin facing doc; this file is for development. The Workshop description
lives in `mod.settings` and is written for players, not coders.

## Layout

NS2 Launch Pad layout, matching the author's other mods:

```
mod.settings                       Workshop metadata and description (never put a backslash in it)
source/lua/entry/SSM.entry         FileHooks + Shared/Server/Client entry scripts
source/lua/SSM/{FileHooks,Shared,Server,Client}.lua   load each feature's files
source/lua/SSM/<Feature>/...       one folder per feature
test/matchesinarow.lua             logic test, runs outside the game
output/                            Launch Pad build output, gitignored
```

Build before publishing (no compile step): `rm -rf output && mkdir -p output && cp -r source/. output/`.
Launch Pad rewrites `mod.settings` on publish, and creates `preview.jpg` and `publish_id` on the
first publish.

New features get their own folder under `lua/SSM/` and one line in each loader they need.
Network messages are registered from `SSM/Shared.lua` only, so server and client register the
same messages in the same order.

## Feature: Matches In A Row

Shows `[3r, 95m] Name` on the scoreboard: rounds in a row and minutes played over them. Built for
a server with no queue (16 players + 5 spectators) where players hand their slot to a spectator
after 3-4 games. The tag only informs; never make it enforce anything.

### Rules (agreed with the author, do not change without asking)

- A round counts for a player who was on Marines or Aliens at any moment of its first
  `GracePeriodSeconds` (120). Leaving and coming back later does not undo that, so hopping to the
  spectators mid-round cannot wipe a count.
- Anyone who first joins after the grace period is a **sub, and gets 0**: the round counts as one
  sat out. The author wants subbing in rewarded.
- Sitting a round out (spectator, ready room, absent) resets to 0.
- Rounds shorter than `MinimumRoundSeconds` (180) are void: nobody changes.
- Minutes are the player's own seconds on a team, summed over the rounds in the count.
- **Counts and minutes only change at round end**, because that is when the server decides who
  spectates. The author explicitly does not want live-updating minutes.
- The tag is plain text in the name's own color. It is part of the name string (see below), so
  coloring it separately would mean redoing the scoreboard's name layout.

### Server (`Server.lua`)

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
  and loaded at startup. `ForgetAfterMinutes` (60) is checked on load **and** at round start: the
  server can sit idle on one map for hours.
- Sends `SSM_MatchesInARowClear` then one `SSM_MatchesInARow` per player with a count, to
  everyone at round end and to each client on `ClientConnect`.

### Client (`Client.lua`, `GUIScoreboard.lua`)

- **The tag is put into the name inside a copy of the score records the scoreboard reads.** Each
  `self.teams[i].GetScores` is wrapped after `GUIScoreboard:Initialize`. The scoreboard then lays
  out and shortens the tagged name like any long name, so vanilla's and Devnull's truncation both
  keep working. Adding text to the name item afterwards would overflow into the icons, because
  both scoreboards shorten names from the item's text during `UpdateTeam`. The cached records
  are never modified.
- **`lua/GUIScoreboard.lua` is reached with a post file hook, never replace.** Devnull's Enhanced
  ScoreBoard (on the live server) replaces that file; a post hook runs after whichever version
  loaded. Only methods both versions have are wrapped (`Initialize`, `UpdateTeam`).
- Two places compare names, and both get the real name back through a tagged-to-real map:
  `ScoreboardUI_IsPlayerLocal` (local row highlight, wrapped in `Client.lua`) and Enhanced
  ScoreBoard's commander name in the team header (`TeamInfo.teamComm`, fixed after
  `UpdateTeam`). The map is never cleared, because Enhanced ScoreBoard keeps the last commander's
  name across rounds.
- Lifeform Picker also draws on the scoreboard; it reads `ClientIndex`, not names, so tagging does
  not affect it.

## Testing

- `luac -p` every file (Lua 5.4 at `C:\Users\maost\AppData\Local\Programs\Lua\bin\`; NS2 runs
  LuaJIT/5.1, so this proves parsing only).
- `lua test/matchesinarow.lua` from the repo root runs the real files against stubbed globals:
  counting rules, saving and loading, expiry, tagging, highlight and commander header.
- Everything visual has to be checked in game through Launch Pad. No test-only console commands.

## Whitelisting

**Not whitelisted.** A non-whitelisted mod on the live server makes it unranked and switches off
consistency checking, which lets some players' client mods desync and drop them. Until UWE
whitelists it, test locally.

## Versioning

Start at v1.0; 0.01 steps for small changes, 0.1 for features. Tag `vX.Y` (annotated,
`"vX.Y - Workshop release"`) only after the author says the Workshop publish is live.
