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
source/lua/entry/SSM.entry         entry: Server script only, for now
source/lua/SSM/Server.lua          loads Messages.lua, then each feature's server file
source/lua/SSM/Messages.lua        the mod's chat voice ([NS2 SUD], magenta) and console print
source/lua/SSM/<Feature>/...       one folder per feature
test/matchesinarow.lua             logic test, runs outside the game
output/                            Launch Pad build output, gitignored
```

Build before publishing (no compile step): `rm -rf output && mkdir -p output && cp -r source/. output/`.
Launch Pad rewrites `mod.settings` on publish. Workshop id `3822092803` (`publish_id`, first published
2026-10-18). On that first publish Launch Pad refused the hand-written file; the author deleted it,
published, and the description was restored from git afterwards. Keep `image = "preview.jpg"` in it.

New features get their own folder under `lua/SSM/` and a line in `SSM/Server.lua`. A feature that
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
- **Every chat message from the mod uses the `[NS2 SUD]` tag in magenta** (`SSM.Notify` in
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
  `Shared.Message` from the server console). `!streakr` / `!streakm` (and with `/`) are caught with
  `Shine.Hook.Add("PlayerSay", ...)` - not a Shine plugin - which answers through `SSM.Notify` and
  returns `""` so the typed message is dropped. The hook is added on the first `UpdateServer`,
  because load order between mods is not guaranteed - the same opportunistic pattern Hive Spawn
  Selector uses for CustomSpawns. Chat lines are separate messages because a single chat message
  cannot hold line breaks.

## Planned (author's ideas, not built yet)

- Reminder messages so players learn the commands.
- A `!help`-style command listing the mod's commands, printed to the console once there are many.

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
