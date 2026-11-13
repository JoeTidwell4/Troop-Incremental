# Troop-Incremental

Incremental/idle Roblox game. The player is a commander; troops auto-fight waves on numbered stages, kills drop Gold, Gold buys troops and gear. Synced into Studio with Rojo.

## Current phase

**Phase 1: data layer + core loop + basic UI. Code written, waiting for the owner to test in Studio.**
Do not start Phase 2 until the owner confirms Phase 1 works.

Decisions made:
- No Wally. ProfileStore is vendored at `src/server/Packages/ProfileStore.luau` (unmodified, Apache 2.0, license in `third_party/ProfileStore/`, upstream commit 45c9847). It's the one file without `--!strict`; DataService wraps it with local types.
- UI is plain Instance-building code (`src/client/UI/UIKit.luau` helpers). No Fusion/React.
- Troop milestone multipliers: on (25/50/100/200/300/400/500, then every 100, x2 each).
- First Ascend target: 20-30 minutes of play (not 45-60).
- No player avatar: `Players.CharacterAutoLoads = false`, fixed scriptable camera on a client-built battlefield at y=200.

## Working with the owner
The owner is new to Roblox development, GitHub, and the command line. Explain steps one at a time, give exact clicks/commands, say what they should see, and assume nothing is installed. They're on Windows (PowerShell). Project lives at `Documents\Troop-Incremental`. They get updates with `git pull` and sync with `rojo serve` + the Rojo plugin's Connect button. In their Studio version, the Output window is under the top menu bar's **Window** menu.

## Phases
1. Data layer + core loop (troops, enemies, stages, gold) + basic UI
2. Gear upgrades + abilities + boss stages
3. Ascend/prestige + Honor shop + offline earnings
4. Factions + faction war
5. Clans + clan raid boss
6. Polish: leaderboards, UI feedback, balancing pass

## Game design
- **Core loop:** troops auto-fight; kills drop Gold; Gold trains troops and upgrades gear; stronger army clears higher stages for more Gold per kill.
- **Active play:** tap/click commander damage + 2-3 cooldown abilities (e.g. Rally: +X% troop damage for 10s). Active should be ~2-3x idle, not 10x. Idle must still feel like progress.
- **Troops:** 3 types to start (Swordsman, Archer, Knight), each with its own cost curve and role. Count and stats both matter.
- **Gear:** per troop type (weapon + armor slot), not per troop. Cost scales exponentially, effect scales slower.
- **Stages:** enemy HP and gold reward scale exponentially. Every 10th stage is a timed boss; failing drops you back one stage.
- **Ascend (prestige):** resets Gold, troops, gear, stage. Grants Honor from highest stage. Honor buys permanent multipliers.
- **Offline earnings:** fight at highest cleared stage at reduced efficiency, capped at a configurable number of hours.
- **Factions:** 3, each with a passive bonus tied to one troop type; switchable with a long cooldown. Weekly faction war, winner gets a week-long bonus. Per-faction global leaderboard.
- **Clans:** player-created, max 20 members. Clan bank from donations, spent on clan-wide perks. Weekly async clan raid boss with shared HP (each member's damage is written and summed). Rewards scale with progress.
- **`CLAN_REQUIRES_SAME_FACTION`** config flag, default `false`. True = clans locked to one faction.

### Design concerns raised (keep in mind)
- Enemies don't fight back, so troop "roles" collapse to cost/DPS ratios. Mitigate with milestone multipliers (Phase 1) and enemy traits like armored/swift on some stages and bosses (Phase 2).
- Choosing a faction on first join hurts onboarding. Prefer prompting at ~stage 15 / after first boss. Keep `faction = nil` in the data template.
- Faction war by raw kill count snowballs to the biggest faction and favors low-stage kills and alts. Use stage-weighted, per-active-member scoring with per-player daily caps; lock switching near payout.
- Leaderboards: OrderedDataStore needs integers, so store a scaled log10 of BigNum values.

## Architecture
```
src/shared  -> ReplicatedStorage.Shared          config, types, pure utils (BigNum, formulas, formatting)
src/server  -> ServerScriptService.Server        init.server.luau bootstraps services
src/client  -> StarterPlayer.StarterPlayerScripts.Client   init.client.luau bootstraps controllers + UI
```
- One responsibility per module. Server = `Services/`, client = `Controllers/` + `UI/`.
- **Server-authoritative.** The client never decides currency, purchases, damage, or rewards. Every remote validates types, rate-limits per player, and checks ownership on the server.
- **Tap damage:** client batches taps (~every 0.25s); server clamps with a token bucket (default 15 taps per second, burst 20). Excess is dropped.
- **Combat:** no physical troop simulation. Server computes army DPS in a single loop over all players (~5 Hz) and resolves kills mathematically. The client renders a capped number of cosmetic units.
- **Data:** ProfileStore with session locking. No raw `SetAsync` for player data. `Reconcile()` against the template.
- **Big numbers:** mantissa/exponent BigNum module, immutable, serialized as `{m, e}`. Used for all currency, HP, damage. Display format: 1.2K, 3.4M, ..., then 5.6e15.
- **Tunables** (costs, growth rates, multipliers, stage scaling, faction bonuses, clan size, offline cap) live in config ModuleScripts under `src/shared/Config/`. Never hardcode in logic.
- **Cross-server (Phases 4-5):** before implementing, write up the storage/sync plan (DataStore for persistent, MemoryStoreService/MessagingService for live totals), race-condition handling for clan bank and raid HP (e.g. UpdateAsync / atomic MemoryStore ops), and the limits.

### Phase 1 data flow
- Server: `RemoteService` (creates remotes, enforces rate limit + validator on every handler) -> `TapService` / `TroopService` mutate `DataService.get(player)` data -> `CombatService` ticks all players at 5 Hz -> `DataService.Changed` -> `SyncService` sends a `Snapshot` to that player at most every 0.25s.
- Client: `StateController` holds the latest snapshot; `InputController` batches clicks; `TroopController` invokes BuyTroop; `BattlefieldController` + `HudUI` + `TroopShopUI` render from the snapshot.
- `Shared/Formulas.luau` is the single source of game math, used by the server for outcomes and by the client only for display previews.
- Troop costs are rounded to whole gold (`BigNum.round`) to avoid float error making exact prices unaffordable.
- Balance was checked with `tools/balance_sim.py` (Python mirror of the formulas). Phase 1 result: idle ~stage 26 at 10 min / 52 at 30 min; clicking ~7/s ~stage 41 / 64; autoclicker cap ~49 / 69.

## Conventions
- `--!strict` at the top of every script. Type everything; shared types in `src/shared/Types.luau`.
- File extension `.luau`. `init.server.luau` / `init.client.luau` / `init.luau` for folder-scripts.
- No em dashes in docs/comments (owner preference).
- Toolchain pinned in `rokit.toml` (Rojo 7.7.1).
- Server modules require shared code via `ReplicatedStorage:WaitForChild("Shared")`; shared modules use `script.Parent`.
- Services expose `start()`; `src/server/init.server.luau` starts them in dependency order (RemoteService first, DataService last).
- Client never decides outcomes. New remotes go in `Shared/Remotes.luau` and are registered through `RemoteService.onEvent` / `onInvoke` with a RateLimiter and validator.

## Running
```
rokit install       # once, installs pinned Rojo
rojo serve          # then Connect from the Rojo plugin in Studio
rojo build -o build.rbxlx   # optional: build a place file without Studio
```
