# Handoff: pause, disconnect handling, reconnect with gear (from B2TP)

Moved here from Blast to the Past on 2026-11-20. The author decided QoL features leave B2TP and live
in SSM. **Nothing here is wired into SSM yet**: `lua/` holds the code exactly as it was built for
B2TP v3.01 (never tested in game, never published). It sits outside `source/`, so it is never built
into `output/`. Integrate it with the usual plan-then-agree step.

Source of truth in the B2TP repo: branch `shelved/qol-pause-reconnect` (commits `1a3d676` pause,
`de0aa2d` reconnect), folder `Blast to The Past/output/lua/B2TP/Thunderdome/`. B2TP's own `main`,
its Main Launch Pad folder and the Workshop item are still v3.0 without any of this.

## What it does (as built and agreed for B2TP)

Ported from Dragon's NSL Mod (https://github.com/xToken/NSL: `lua/NSL/pause/*`,
`lua/NSL/statesave/server.lua`). The author asked for Dragon to be credited; B2TP's credit line was
"Pause and reconnect features ported from Dragon's NSL Mod." Messages are in English only.

**Pause**
- Any player on a team, during a started round: chat `pause` / `!pause`, console `gpause`.
  5 s countdown, then the game freezes (clock stopped, input, movement, buying, projectiles, AI,
  callbacks, commander actions blocked; chat, voice, scoreboard, minimap, menus keep working).
- Resume: someone on EACH team types `unpause` / `!unpause` / `resume` / `!resume` (toggle, 2 s per
  team between toggles); 5 s countdown. Auto-resume after 300 s (0 = never), reminders every 30 s.
- 4 pauses per team per round; counts and any active pause cleared at round reset.
- Commander logout and chair use blocked while paused or pausing.
- Server log lines for pause, resume, auto-resume. No admin or referee override (author's call).
- No coexistence handling with NSL (the author never runs both).

**Saved player states (reconnect with gear)**
- A team player who disconnects during a started round is handed to a placeholder virtual client,
  renamed `[D/C] Name`. Stays in place, can be killed. Same Steam id reconnecting in that round gets
  it back: lifeform, upgrades, weapons, jetpack/Exo, health, energy, position. Commanders too (NSL
  behavior, author's pick). Kept until round reset (NSL behavior, author's pick).
- Optional pause on disconnect (default on): 1 s countdown, uses one of the team's pauses, pauses
  even when the team has none left (NSL behavior).
- Not ported: NSL referee commands (list saved players, put a substitute in), NSL bot-controller and
  virtual-move hooks (build 345 gives a bot-less virtual client an empty move and never kicks it).
- Addition over NSL: the restored player takes over the reconnecting client's scoreboard entry.

**Settings** (`config://B2TP_Thunderdome.json` in B2TP; rename for SSM): `PauseEnabled` true,
`PausesPerTeam` 4, `PauseCountdown` 5, `ResumeCountdown` 5, `AutoResumeAfter` 300,
`ReadyReminderInterval` 30, `SavePlayerStates` true, `PauseOnDisconnect` true.

## Files

| File | VM | Role |
|---|---|---|
| `Shared.lua` | Shared (server, client, predict) | Player netvars `timeadjustment`/`timepaused`/`gamepaused` (added in every mode so layouts match), `B2TPPause_ReplaceMethod` (tolerant replace incl. derived classes), the Thunderdome gate `B2TP_GetPauseInstalled`, Shared.GetTime/GetPreviousTime replacement, input/move/gravity/buy blocks, token bucket and animation clock fixes |
| `Server.lua` | Server | Settings loader + chat/log helpers, loads the two below |
| `Pause_Server.lua` | Server | Pause state machine, entity freeze/resume, chat and console commands, round reset, `B2TPPause_TriggerDisconnectPause` |
| `PlayerStates_Server.lua` | Server | NSL statesave port: wraps NS2Gamerules OnClientDisconnect / OnClientConnect / ResetGame, RagdollMixin.OnTag, Player.GetDestructionAllowed |
| `Client.lua` | Client | Effects on the real clock, chat typing while paused, GUIManager real-time updates for chat/scoreboard/minimap, BaseGUIManager hook for menus |

B2TP's entry had `Shared = .../Shared.lua`, `Server = .../Server.lua`, `Client = .../Client.lua`.

## Open points for SSM (decide before integrating)

1. **Whitelist pitch.** SSM was whitelisted as server-only, "no client files, no network messages"
   (CLAUDE.md, Whitelisting). The pause needs `Shared.lua` + `Client.lua` and adds Player network
   fields. That ends the pitch, so raise it with Ghoul first. **Reconnect with gear is server-only**
   (`PlayerStates_Server.lua` uses nothing client-side) and fits SSM as is; only its
   pause-on-disconnect option depends on the pause.
2. **Spectator On Connect conflict.** SSM moves every newcomer (and any non-map-change reconnect, "a
   crash") to spectator in a post-wrap of `NS2Gamerules:OnClientConnect`. A player whose saved state
   is restored must be exempt, or the two wraps fight over the same client. Decide wrap order and the
   exemption.
3. **Thunderdome gate.** Everything was gated on `Shared.GetThunderdomeEnabled()` (author's B2TP
   rule: only the Discord Thunderdome server). SSM also runs on the pubs: keep the gate, make it a
   setting, or allow pubs too?
4. **SSM conventions.** Rename `B2TP_*` / `B2TPPause_*` / `B2TPTD_*` globals and log prefixes,
   move chat commands to `SSM.AddChatCommand` + `SSM.ListCommand` (!help), use the `[NS2 SUD]` chat
   tag from `Messages.lua`, private texts in `Strings.lua` (en/es/pt) instead of English-only, one
   folder per feature under `lua/SSM/` (probably `Pause/` and `SavedPlayers/`), offline tests in
   `test/` like the other features.
5. **Versioning.** New features step the number (v1.2?).

## Known risks and test checklist (unchanged from B2TP)

- Player-count checks see the placeholder as a team player (Thunderdome auto-concede); NS2+ stats may
  log the disconnected stretch oddly; the `[D/C]` player is not on the scoreboard while away.
- Chat typing while paused uses a wrap of `ChatUI_EnterChatMessage` / `ChatUI_GetStartedChatTime`
  (5 ms real-clock window) instead of NSL's GUIChat replacement: first thing to check if typing is odd.

Tests: pause via chat; frozen world; chat/scoreboard/menu while paused; one team ready then both;
cooldowns/building/jetpack/Exo after resume; 5th pause refused, counts reset next round;
auto-resume with a low setting. Disconnect as Fade, as jetpack + shotgun marine, as Exo, while dead,
as commander; body killed while away; round reset with a saved player waiting; log lines and script
errors at disconnect and reconnect; nothing active outside the gate.
