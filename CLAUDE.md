# Troop-Incremental

Incremental/idle Roblox game. The player is a commander; troops auto-fight waves on numbered stages, kills drop Gold, Gold buys troops and gear. Synced into Studio with Rojo.

## Current phase

**Phase 1: done (owner confirmed in Studio).**
**Phase 2 is split in two:**
- **2a: done (owner confirmed in Studio).** Bosses that hit back, troop HP, areas, abilities (Rally/Barrage/Plunder).
- **2b: done (owner confirmed in Studio).** Gear Weapon/Armor levels + rarity + gear packs, avatar as commander on a per-player battlefield plot, Shop tabs.

**Phase 3 (plan proposed, waiting for OK):** Ascend + Honor shop + offline earnings. Open Phase 3 questions: does gear rarity reset on Ascend (leaning yes)? Does highestBossDefeated / free-pack tracking reset (if so, free packs are re-earned each run)?

Decisions made:
- No Wally. ProfileStore is vendored at `src/server/Packages/ProfileStore.luau` (unmodified, Apache 2.0, license in `third_party/ProfileStore/`, upstream commit 45c9847). It's the one file without `--!strict`; DataService wraps it with local types.
- UI is plain Instance-building code (`src/client/UI/UIKit.luau` helpers). No Fusion/React.
- Troop milestone multipliers: on (25/50/100/200/300/400/500, then every 100, x2 each).
- First Ascend target: 20-30 minutes of play (not 45-60).
- Avatar as commander (2b): `PlotService` assigns each player a plot index (Player attribute `PlotIndex`; `Shared/Plots.luau` turns it into a world position, plots 400 studs apart along X from y=200). The avatar is anchored at `WorldConfig.COMMANDER_OFFSET` on an invisible server-side floor part (`workspace.CommanderFloors`; without it the humanoid sits in Freefall because the visible ground is client-only), movement modes set to Scriptable (no keyboard/thumbstick). Client builds the battlefield locally at its plot; fixed scriptable camera. `CommanderController` welds a local-only sword that slashes on click (always works), and lifts the arm via whichever shoulder joint moves the upper arm: Motor6D (tween C0) or the newer AnimationConstraint (tween Attachment0.CFrame). R15 rotates around X, R6 around Z. Prints the detected rig/joint once to Output. Later (Phase 4/5) a social hub.
- Armor problem: enemies never attacked, so armor meant nothing. Fix (owner approved): **bosses hit back**. Troops have HP; during a boss the boss damages army HP each second. Lose if time runs out or army HP hits 0. Armor (2b) raises HP. Knights = tank, Archers = fragile DPS.
- Boss fail: back one stage, auto-advance OFF, player farms until pressing Fight Boss (only valid when next stage is a boss) or re-enabling auto-advance.
- Areas: every boss beaten moves you to the next area (10 stages each). 6 themes in AreaConfig, then repeat with roman numerals. Cosmetic only for now; area modifiers (e.g. armored enemies vs Archers) are a Phase 6 idea.
- Gear packs (2b, approved design): Gold only, never Robux (Roblox requires odds disclosure for paid random items; some countries restrict). No inventory: each troop x slot has rarity + level; a pack rolls troop+slot+rarity, upgrades rarity if better, else refunds 50% of the price. Odds 60/25/10/4/1 shown in UI, Epic+ pity every 30 packs, price scales with highest stage, free pack on each boss's first kill. All rolls server-side. Open question for Phase 3: does rarity reset on Ascend (leaning yes).

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

### Data flow
- Server: `RemoteService` (creates remotes, enforces rate limit + validator on every handler) -> `TapService` / `TroopService` / `AbilityService` change state -> `StageService` runs the 5 Hz fight loop for all players (pulls damage from `CombatService.takeDamage`, resolves kills/gold/stage, boss timer + boss damage to army, fail/retreat) -> `DataService.Changed` -> `SyncService` sends a `Snapshot` to that player at most every 0.25s. Boss results go out on the `Notice` remote.
- Gear (2b): `data.gear[troopId].weapon/armor = { level, rarity }`. Slot multiplier = levelEffect * rarity multiplier (Formulas.gearMultiplier); weapon multiplies that troop type's DPS, armor its HP, inside `Formulas.troopDps/troopHp`. Per-type, so it lives in Formulas, not ModifierService (which is for global multipliers). `GearService` handles x1/Max level upgrades.
- Packs (2b): `PackService` rolls server-side with `Random.new()`. Pity: `data.packs.sinceEpic`. Free packs: `StageService` tracks `highestBossDefeated` (also derived on load from highestStage) and fires `BossDefeated`; PackService grants `(highestBossDefeated - packs.rewardedBossStage) // BOSS_EVERY` packs, so it can never double-grant and back-fills older saves.
- `CombatService` = army numbers only (cached base DPS/HP, queued click/ability damage). `ModifierService` = the single place all multipliers are combined (`damage`, `gold`, `armyHp`); systems register a source function. Abilities use it now; Honor, faction, clan, and gear bonuses must plug in here too.
- Server-only per-player state (not saved): encounter (enemy HP, boss timer, army damage taken) in StageService, ability timers in AbilityService. Ability timestamps use `workspace:GetServerTimeNow()` so the client can count down locally.
- Client: `StateController` holds the latest snapshot and forwards notices; `InputController` batches clicks; `ShopController` (BuyTroop / UpgradeGear / OpenPack); `AbilityController` (buttons + keys 1/2/3); `BattleController` (Fight Boss, auto-advance); `CommanderController` (avatar sword + swing); `BattlefieldController` + `HudUI` + `ShopUI` (tabs: `TroopTab`, `GearTab`, `PackTab`, shared types in `ShopTypes`) + `AbilityBarUI` + `NoticeUI` + `PackRevealUI` render from the snapshot.
- `Shared/Formulas.luau` is the single source of game math, used by the server for outcomes and by the client only for display previews.
- Troop costs are rounded to whole gold (`BigNum.round`) to avoid float error making exact prices unaffordable.
- Balance is checked with `tools/balance_sim.py` (Python mirror of the formulas; numbers copied by hand). Phase 2a result (boss HP x12, boss DPS 0.12 x enemy HP): active beats boss 10 at ~1.4 min, 50 at ~19 min, walls at ~59; idle reaches ~49 at 30 min. Active ~2.5x idle. Most boss fails are army HP, which 2b Armor addresses. With gear levels (base 5x troop cost, growth 1.9; packs not simulated): active reaches ~stage 68 at 30 min (vs 59 without), boss fails 11 -> 7.

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
