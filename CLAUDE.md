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
source/lua/entry/SSM.entry         entry: Server script only, for now
source/lua/SSM/Server.lua          loads each feature's server file
source/lua/SSM/<Feature>/...       one folder per feature
test/matchesinarow.lua             logic test, runs outside the game
output/                            Launch Pad build output, gitignored
```

Build before publishing (no compile step): `rm -rf output && mkdir -p output && cp -r source/. output/`.
Launch Pad rewrites `mod.settings` on publish, and creates `preview.jpg` and `publish_id` on the
first publish.

New features get their own folder under `lua/SSM/` and a line in `SSM/Server.lua`. A feature that
needs client code or network messages adds `Client` / `Shared` (and `FileHooks` if needed) back to
the entry with matching loaders; network messages belong in a Shared script so server and client
register them in the same order.

## Feature: Matches In A Row

Counts rounds in a row and minutes played over them, and shows the top 5 of each through
`sh_freqplayers` (console) and `!freqplayers` (chat, caller only). Built for a server with no
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
- Rounds shorter than `MinimumRoundSeconds` (180) are void: nobody changes.
- Minutes are the player's own seconds on a team, summed over the rounds in the count.
- **Counts only change at round end**, because that is when the server decides who spectates.
- **Counts last one play session**: kept across map changes and restarts, dropped after
  `ForgetAfterMinutes` (60) with nobody playing a round. The author confirmed 60 minutes; rounds
  of 70+ minutes do happen, which is why activity is re-saved during rounds.
- **The commands are open to everyone**, for transparency. Top 5 by rounds (ties by minutes, then
  name) and top 5 by minutes (ties by rounds, then name), connected players only.

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
- Commands go through Shine when it is loaded (`Shine:RegisterCommand`, `NoPerm = true`),
  registered on the first `UpdateServer` rather than at file load, because load order between
  mods is not guaranteed - the same opportunistic pattern Hive Spawn Selector uses for
  CustomSpawns. Not a Shine plugin. `Shine:IsCommandFromChat()` picks chat
  (`NotifyDualColour`, caller only) or console (`ServerAdminPrint`; `Shared.Message` from the
  server console). Without Shine there are no commands.

## Testing

- `luac -p` every file (Lua 5.4 at `C:\Users\maost\AppData\Local\Programs\Lua\bin\`; NS2 runs
  LuaJIT/5.1, so this proves parsing only).
- `lua test/matchesinarow.lua` from the repo root runs the real server file against stubbed
  globals: counting rules, void and reset rounds, saving and loading, expiry, the long-round
  restart, top-5 limits and the commands.
- Real behavior has to be checked on a server (Launch Pad listen server with Shine loaded). No
  test-only console commands.

## Whitelisting

**Not whitelisted yet**; the author plans to apply soon. A non-whitelisted mod on the live server
makes it unranked and switches off consistency checking, which lets some players' client mods
desync and drop them. Until then, test locally.

## Versioning

Start at v1.0; 0.01 steps for small changes, 0.1 for features. Tag `vX.Y` (annotated,
`"vX.Y - Workshop release"`) only after the author says the Workshop publish is live.
