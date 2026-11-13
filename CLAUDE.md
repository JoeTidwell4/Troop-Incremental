# Troop-Incremental

Incremental/idle Roblox game. The player is a commander; troops auto-fight waves on numbered stages, kills drop Gold, Gold buys troops and gear. Synced into Studio with Rojo.

## Current phase

**Phase 0: project setup (done).** Rojo scaffold, toolchain pin, empty entry points.
**Next: Phase 1** (data layer + core loop + basic UI). Plan proposed, waiting on owner's answers:
- Wally for packages, or a vendored copy of ProfileStore?
- UI: plain Instance-building code (default) or Fusion/React-lua?
- Troop milestone multipliers (every 25/50/100 of a type) to stop single-troop dominance: proposed.
- First-Ascend target: proposed 20-30 min (owner originally said 45-60).

Do not start a phase until the owner confirms the previous one works in Studio. Start each phase with a short plan (files + why) and wait for OK. End each phase with exact Studio test steps and expected results. Keep this file updated.

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

## Conventions
- `--!strict` at the top of every script. Type everything; shared types in `src/shared/Types.luau`.
- File extension `.luau`. `init.server.luau` / `init.client.luau` / `init.luau` for folder-scripts.
- No em dashes in docs/comments (owner preference).
- Toolchain pinned in `rokit.toml` (Rojo 7.7.1).

## Running
```
rokit install       # once, installs pinned Rojo
rojo serve          # then Connect from the Rojo plugin in Studio
rojo build -o build.rbxlx   # optional: build a place file without Studio
```
