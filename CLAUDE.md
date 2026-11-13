# Troop-Incremental

Incremental/idle Roblox game. The player is a commander; troops auto-fight waves on numbered stages, kills drop Gold, Gold buys troops and gear. Synced into Studio with Rojo.

## Current phase

**Phase 1: done (owner confirmed in Studio).**
**Phase 2 is split in two:**
- **2a: done (owner confirmed in Studio).** Bosses that hit back, troop HP, areas, abilities (Rally/Barrage/Plunder).
- **2b: done (owner confirmed in Studio).** Gear Weapon/Armor levels + rarity + gear packs, avatar as commander on a per-player battlefield plot, Shop tabs.

**Phase 3: done (owner confirmed in Studio).** Ascend + Honor shop + offline earnings.
**Phase 4: done (owner confirmed in Studio).** Factions + faction war.
**Phase 5: done (owner confirmed in Studio).** Clans (5a) + clan raid boss (5b), plus the first Phase 6 polish, audio system, and Robux store (all confirmed working).
**Waiting on the owner:** audio asset IDs for `AudioConfig`; Golden Sword pass + gold product IDs. Live pass IDs: DoubleGold 2088398382, AutoClicker 2089262362 (owner chose a real, fair auto clicker for this pass). AutoAbilities and GoldenSword passes exist in code with id 0 (hidden).
**Phase 7: done (owner confirmed in Studio).** Themed world, real unit/enemy models, effects, UI layout + style pass. Owner wants the game fleshed out a lot before going public.
**Phase 8a (code written, NOT yet tested in Studio):** daily login calendar, daily quests, achievements. Owner approved all picks (missing a day resets to day 1).
**Phase 8b (approved plan, not started; do after 8a is confirmed):** Mage (stage 30, x2 vs bosses, fragile), Cavalry (stage 60, big vs normal enemies), Siege (stage 100, x3 vs bosses, almost no HP); area traits (each area -30% damage to one troop type); boss moves (enrage below 30% HP, shield phase where only clicks hurt, summoned minions).
**After that (proposed):** Phase 8 content (daily rewards/quests, achievements, new troop types, area modifiers, boss mechanics), analytics funnel, balance pass with real data.
Phase 3 decisions (owner approved): gear rarity DOES reset on Ascend; highestBossDefeated + packs.rewardedBossStage reset too, so free boss packs are re-earned every run. Unopened free packs and the pity counter are kept.

Decisions made:
- No Wally. ProfileStore is vendored at `src/server/Packages/ProfileStore.luau` (unmodified, Apache 2.0, license in `third_party/ProfileStore/`, upstream commit 45c9847). It's the one file without `--!strict`; DataService wraps it with local types.
- UI is plain Instance-building code (`src/client/UI/UIKit.luau` helpers). No Fusion/React.
- Troop milestone multipliers: on (25/50/100/200/300/400/500, then every 100, x2 each).
- First Ascend target: 20-30 minutes of play (not 45-60).
- Avatar as commander (2b): `PlotService` assigns each player a plot index (Player attribute `PlotIndex`; `Shared/Plots.luau` turns it into a world position, plots 400 studs apart along X from y=200). The avatar is anchored at `WorldConfig.COMMANDER_OFFSET` on an invisible server-side floor part (`workspace.CommanderFloors`; without it the humanoid sits in Freefall because the visible ground is client-only), movement modes set to Scriptable (no keyboard/thumbstick). Client builds the battlefield locally at its plot; fixed scriptable camera. `CommanderController` welds a local-only sword that slashes on click (always works), and lifts the arm via whichever shoulder joint moves the upper arm: Motor6D (tween C0) or the newer AnimationConstraint (tween Attachment0.CFrame). R15 rotates around X, R6 around Z. Prints the detected rig/joint once to Output. Later (Phase 4/5) a social hub.
- Armor problem: enemies never attacked, so armor meant nothing. Fix (owner approved): **bosses hit back**. Troops have HP; during a boss the boss damages army HP each second. Lose if time runs out or army HP hits 0. Armor (2b) raises HP. Knights = tank, Archers = fragile DPS.
- Boss fail: back one stage, auto-advance OFF, player farms until pressing Fight Boss (only valid when next stage is a boss) or re-enabling auto-advance.
- Areas: every boss beaten moves you to the next area (10 stages each). 6 themes in AreaConfig, then repeat with roman numerals. Cosmetic only for now; area modifiers (e.g. armored enemies vs Archers) are a Phase 6 idea.
- Gear packs (2b, approved design): Gold only, never Robux (Roblox requires odds disclosure for paid random items; some countries restrict). No inventory: each troop x slot has rarity + level; a pack rolls troop+slot+rarity, upgrades rarity if better, else refunds 50% of the price. Odds 60/25/10/4/1 shown in UI, Epic+ pity every 20 packs (was 30), price = 25 kills' worth of gold at your best stage this run (was 40), free pack on each boss's first kill.
- Owner tuning request (after Phase 5): gold +20% (`StageConfig.GOLD_BASE` 1.5 -> 1.8; sims show the same boss walls and ~20 min first Ascend, just faster buying), packs cheaper and pity sooner (above). All rolls server-side. Open question for Phase 3: does rarity reset on Ascend (leaning yes).

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
- Choosing a faction on first join hurts onboarding. Implemented: picker opens once per session after best stage passes 10 (first boss), with "Decide later". `faction = ""` means none (ProfileStore templates can't hold nil).
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

### Phase 3: Ascend, Honor, offline
- Two stage records: `highestStage` = this run (Honor, pack price, offline stage; resets on Ascend) and `bestStage` = all-time (ability unlocks; never resets; migrated from highestStage for old saves).
- Ascend (`AscendService`): allowed at `AscendConfig.MIN_STAGE` (50). Honor = floor(10 * 1.08^(highestStage - 50)), stored as BigNum. Resets gold (to `Formulas.startingGold(honorUpgrades)`), stage, troops, gear levels + rarity, boss/free-pack tracking; then `StageService.restart`. Client confirms in `AscendConfirmUI`.
- Honor shop (`HonorService`, `HonorConfig`): Drills/WarChest/Fortitude/Might multiply damage/gold/armyHp/tap per level (x1.25/x1.2/x1.25/x1.5) via a ModifierService source (`tap` field added to Modifiers; CombatService.getTapDamage applies it). HeadStart = x8 starting gold per level. Rations = +1h offline cap, +5% offline efficiency (max 16). Costs base * growth^level, BigNum Honor.
- Offline (`OfflineService`, `OfflineConfig`): `data.lastSeen` (os.time) written every 60s and on leave. On load: seconds = min(away, cap), gold = goldPerKill(stage) * min(DPS/enemyHp, 10 enemies * 5 ticks per sec) * seconds * efficiency * gold modifier at `Formulas.offlineStage(highestStage)` (highest normal stage cleared). Defaults 25%, 8h, min 60s. No stage progress offline. Notice is sent once the client fires ClientReady (`SyncService.ClientReady` / `isReady`), shown by `OfflineEarningsUI`.
- `tools/ascend_sim.py`: first Ascend ~18 min (sim player is optimal; real players slower, in the 20-30 target), runs then go 60 -> 70 -> 80 -> 90 -> 100 best stage, each faster. Additive effects were too flat, hence multiplicative.

### Phase 4: factions + faction war (owner approved these rule changes vs the original spec)
- Factions (`FactionConfig`): Iron Legion (Swordsman), Silverwood Rangers (Archer), Order of the Dawn (Knight); x1.5 damage AND HP for that troop type via `Formulas.factionTroopMultipliers`, passed into `Formulas.troopDps/troopHp/armyDps/armyHp` (per-type, so not ModifierService). First pick free; then 7-day cooldown; switching locked in the last 24h of a war. `FactionService` (ChooseFaction remote).
- War points (`WarService`): only kills on stages >= highestStage - 5; 1 per kill, 20 per boss; 3000/day cap per player (cap carries over a switch). Member is "active" at 200 points/week. Score = total points / active members; tie -> total. Winners who were ACTIVE in the winning faction get x1.2 gold the whole next week (ModifierService source). Switching resets your weekly record for the new faction; points already earned stay with the old one.
- Player save: `faction`, `factionChangedAt`, `war` (this week's WarRecord), `lastWar` (previous week, used for the winner bonus).
- Weeks: Monday 00:00 UTC (`WEEK_ANCHOR` = 345600), `Formulas.warWeek/warWeekStart/warDay`. **Studio test mode**: 5-minute wars, 60s switch lock, 20s finalize delay, 20-point active threshold, faster sync intervals (all `if isStudio` in FactionConfig).
- Cross-server (`WarStore` = all I/O, pcall-wrapped; `WarService` = rules):
  - Live totals: MemoryStore HashMap "FactionWar", key `w{week}:{faction}:{shard}` = `{p, a}`, 4 shards per faction (server picks one), atomic `UpdateAsync` increments, 14-day expiry. Each server buffers points and flushes every 60s (retries on failure, flushes on BindToClose). Polls/sums every 60s and broadcasts `WarSync` (WarState) to its players, adding its own unflushed buffer for display.
  - Leader lock: MemoryStore "FactionWarMeta" key "leader" `{job, untilTime}` via UpdateAsync. Leader backs up totals to DataStore "FactionWar" `backup_{week}` every 5 min and restores them into shard 1 only if every shard key is missing.
  - Result: after week end + 10 min, any server computes the winner and writes DataStore `result_{week}` via UpdateAsync set-if-absent, then re-reads it, so all servers agree.
  - Leaderboard: OrderedDataStore `WarTop_{week}_{faction}`, key = userId, value = weekly points (integers). Written every 3 min for changed players and on leave; top 10 read every 2 min, names via GetNameFromUserIdAsync (cached).
  - SyncService gained `ClientReady` signal, `isReady`, and `addSnapshotFields(provider)` so FactionService can add snapshot fields without a require loop.
  - Known limits: an ambiguous MemoryStore failure could double-count one flush; standings lag ~1-2 min; true multi-server behavior can only be tested on a published game.
- Client: `FactionController` (ChooseFaction + WarSync state, local countdown), `FactionUI` (WAR button under ability bar; picker view + war view).

### Phase 5: clans + raid (owner approved these changes vs the original spec)
- Donations are gold converted to **Supplies** at `Formulas.goldPerSupply(highestStage)` (one kill's worth of gold), capped at 500/day/member, so perk prices work at every progression level and pre-Ascend gold dumps can't flood the bank. Raid damage is likewise normalized: `Formulas.raidUnits` = damage / enemyHp(highestStage) * Warbanners perk, capped at 60/attack.
- Clan names/tags go through `TextService:FilterStringAsync` + `GetNonChatStringForBroadcastAsync`; rejected if the filter changes them (Roblox requirement for player-written text).
- Storage (`ClanStore` = all I/O, pcall-wrapped): DataStore "Clans" `clan_{id}` = ClanRecord (truth for membership; every change via `ClanStore.update` = UpdateAsync with checks inside the transform, `version` bumped), "ClanNames" `name_{lower}` (set-if-absent for unique names), "ClanRaid" `raid_{id}_{week}` (raid progress + contributors), OrderedDataStore "OpenClans" (open + not full, value = member count), MessagingService topic "ClanUpdate" (clan id; best-effort nudge, polling is the guarantee). `get`/`getRaid` return `(value, ok)` so a store error is never mistaken for "deleted".
- `ClanService`: membership/roles (Leader > Officer > Member; leader leaving promotes highest role then earliest joiner; last member leaving deletes the clan and frees the name), one `ClanRequest` remote with an action registry (`registerAction(name, validator, handler)`), per-player busy lock, cache of clans with members online (poll 60s + MessagingService refresh), player's `clanId` validated against the record on load/poll (join writes the save first so crashes self-heal). Kicked players are cleared when their server next sees the record.
- `ClanBankService`: donations deduct gold from the save immediately, Supplies buffered per clan and flushed every 30s (batch removed before the write, re-queued on failure, flushed on BindToClose); perk buy merges this server's buffer into the same UpdateAsync. Perks (Muster/Treasury/Bulwark = damage/gold/HP x1.1 per level, Warbanners = raid x1.1) via ModifierService. `CLAN_REQUIRES_SAME_FACTION` (default false) enforced on create/join and FactionService blocks switching while in a clan.
- `RaidService` + StageService "Raid" encounter: 3 attacks/day, 30s, boss doesn't hit back, no gold/kills, damage totalled; HP bar sized so emptying it = unit cap (ends early). Attack counted at start. Result saved with UpdateAsync into the clan's raid record (failed saves retried on poll). Rewards: after the raid week ends, next login reads the clan total and grants 2 Honor per tier + 1 free pack per 2 tiers; `data.raid.claimedWeek` in the session-locked save prevents double claims. Leaving or Ascending mid-raid still records the damage. Studio test mode: 10-minute raid weeks, 2-minute raid days.
- Client: `ClanController` (ClanRequest, ClanSync, RaidSync), `ClanUI` (CLAN button under WAR; create/browse/search when not in a clan; header + tabs `ClanMembersTab`, `ClanBankTab`, `ClanRaidTab` when in one; closes itself when a raid attack starts). HUD + Battlefield have a Raid mode; NoticeUI shows RaidResult / RaidRewards.

### Phase 6 polish done so far (owner confirmed in Studio)
- `LeaderboardService` + `LeaderboardConfig`: Roblox player list `leaderstats` (Best = bestStage, Honor = lifetime Honor formatted), global OrderedDataStores "TopBestStage" and "TopHonor" (key = userId; each player writes only their own key; saved every 5 min if changed and on leave; top 10 read every 2 min, sent via `LeaderboardSync`). Client `LeaderboardUI` = TOP button left of WAR.
- `DamageNumbersController`: floating click damage and "+gold" on kills above the enemy (max 12 at once), using `BattlefieldController.getEnemyPosition()`.
- Starter tips: `HudUI` `tipFor(snapshot)` replaces the old single click hint (click, buy a Swordsman, boss advice, Fight Boss, Rally, Gear tab, Barrage, free packs). Off after the first Ascend or best stage 25, except the free-pack reminder.
- Still to do in Phase 6: balancing pass with real play data, area modifiers (e.g. armored enemies vs Archers) to make troop roles matter more, sound, mobile layout pass (right-side button column gets tall on small screens), faction leaderboard already exists (WarService).

### Audio + monetization (owner confirmed in Studio; still needs real IDs)
- Audio: `AudioConfig` lists every sound/music slot with an empty `id` (silent until the owner picks assets; owner will send IDs in chat and we paste them in). `AudioController` plays SFX by watching snapshot diffs (kills, buys, gear, ability readyAt, encounter changes, ascensions), notices (boss win/fail, purchase), taps, pack reveal, and every UIKit button (via `UIKit.hooks.onButtonClick`). Music tracks Main/Boss/Raid crossfade by encounter. `SoundToggleUI` cycles All / Music off / Off (session only).
- Monetization: `MonetizationConfig` with ids = 0 (hidden) until the owner creates items on create.roblox.com and sends IDs. Passes: DoubleGold (x2 gold via ModifierService), AutoClicker (server adds 5 taps/sec through `TapService.addTaps`, which shares the same per-player 15/s click budget as manual clicks; client fires `InputController.Tapped` locally for visuals only), AutoAbilities (server fires ready abilities every 1s via `AbilityService.tryUse`), toggleable passes use `data.passToggles[key] = false` when switched off (SetPassToggle remote; older `autoAbilities` flag migrated), GoldenSword (cosmetic; server sets Player attribute `Pass_<key>`, CommanderController restyles the sword). Products: GoldSmall/GoldLarge = 30 min / 4 h of army gold at 100% (Formulas.offlineGold at offlineStage), min 100.
- `MonetizationService`: passes checked with UserOwnsGamePassAsync on load + PromptGamePassPurchaseFinished. ProcessReceipt: wait for profile, grant once per PurchaseId (`data.purchases`, last 50), then `DataService.saveAndWait` until `LastSavedData.purchases` contains the id; only then PurchaseGranted, else NotProcessedYet. Design rules in the config: nothing random for Robux, auto clicker only at human pace inside the shared click cap, no faction-war pay-to-win. Client `MonetizationController` + `StoreUI` (STORE button left side; live prices via GetProductInfo).

### Phase 7: look and feel
- `src/client/Visuals/` (cosmetic only, all parts built in code, no uploaded assets): `Parts` (block/ball/upright cylinder/cylinderZ/wedge/ridge helpers, all anchored + non-colliding), `Environment` (per-area 1000x1000 ground just below the 70x36 arena, border stones, ~110 seeded props kept out of the arena and the camera lane, 14 distant mountains or dunes, ambient ParticleEmitter, Atmosphere haze + ClockTime + tint), `TroopModels` (Swordsman/Archer/Knight from parts; parts tagged `GearSlot` take rarity color, Neon from Epic), `EnemyModels` (Goblin, Scorpion, Yeti, Bogling, Golem, Wraith, raid Colossus; boss = scale 2 + crown; built at origin then `ScaleTo` + `PivotTo`), `Effects` (sparks/coins/dust via built-in rbxasset particle textures, `shatter` clones parts as fading physics debris, `arrow` with Trail).
- `AreaConfig` themes now carry `scenery`, `enemyKind`, arena/ground/mountain colors, `hazeColor/hazeDensity`, `particles` (enemyShape removed).
- `BattlefieldController` orchestrates: rebuilds the environment on area change, the enemy model when kind/color/scale changes, troop models when visible counts change, recolors gear when rarities change; per-frame melee lunge, archers shooting arrows, enemy pop-in (ScaleTo) + bob (wraiths float), boss slam (lunge + red Highlight on troops + camera shake + dust), Rally Highlight + aura particles, Highlight flash on hits, shatter on kills (max 4/s). Camera CFrame set every frame (shake).
- UI: `UI/Layout` holds all fixed button positions. Left column: gold panel, Ascend-ready button, row 1 Sound | Store, row 2 War | Clan | Top. Ability bar is a horizontal row centered above the shop (the Roblox player list owns the top-right). `UIKit.create` auto-adds a UIScale to every ScreenGui (scales down to 0.6 for phones, design size 1000x620). Panels/buttons get gradient + stroke; buttons squish on press; `UIKit.openModal` pops windows in; `UIKit.bump`; title font FredokaOne. HUD flies gold coins (separate unscaled ScreenGui) from the enemy to the gold counter on kills.

### Phase 8a: daily login, quests, achievements
- `ActivityService.record(player, activity, amount)` is the one hook for "player did X": keeps `data.lifetime[activity]` counters and fires `Recorded`. Called from AbilityService ("Ability"), TroopService ("TroopBuy"), GearService ("GearUpgrade"), PackService ("PackOpen"), WarService ("WarPoints"), RaidService ("RaidAttack"), ClanBankService ("Donate"); "Kill"/"BossWin" come from StageService signals.
- `DailyService` (+ `DailyConfig`): UTC days (`DAY_SECONDS`, 3 min in Studio). Login: `data.daily = {lastClaimDay, streak}`; claiming the day after the last claim advances (7 rewards, loops), any gap restarts at 1. Quests: `data.quests = {day, list, rerollsUsed, bonusClaimed}`, 3 per day from the pool filtered by `requires` (abilities/gear/faction/clan), 3 difficulties per quest, 1 reroll/day, all-claimed bonus = 1 free pack. `DailyService.grant(player, data, RewardDef)` handles goldMinutes (`Formulas.incomeGold`), packs, heroChests, honor. One `ProgressRequest` remote with an action registry (`registerAction`), view pushed on `ProgressSync` (throttled 1s, also on day change).
- `AchievementService` (+ `AchievementConfig`): goals checked on `DataService.Changed` (max 1/s); reached -> `data.achievements[id] = "unlocked"` (stays claimable after Ascend), claim -> "claimed" + Honor. Adds `achievements` to the ProgressSync view and a "ClaimAchievement" action.
- Hero Chests: `data.packs.hero`; OpenPack now takes a mode ("Gold" | "Free" | "Hero"); Hero rolls Epic or better.
- Client: `ProgressController` (view + requests + `hasClaimable`), `QuestsUI` (QUESTS button = left column row 3 with red dot; tabs Daily / Quests / Achievements; auto-opens once per session when the login reward is ready). PackTab has a third button for Hero Chests.

### Data flow
- Server: `RemoteService` (creates remotes, enforces rate limit + validator on every handler) -> `TapService` / `TroopService` / `AbilityService` change state -> `StageService` runs the 5 Hz fight loop for all players (pulls damage from `CombatService.takeDamage`, resolves kills/gold/stage, boss timer + boss damage to army, fail/retreat) -> `DataService.Changed` -> `SyncService` sends a `Snapshot` to that player at most every 0.25s. Boss results go out on the `Notice` remote.
- Gear (2b): `data.gear[troopId].weapon/armor = { level, rarity }`. Slot multiplier = levelEffect * rarity multiplier (Formulas.gearMultiplier); weapon multiplies that troop type's DPS, armor its HP, inside `Formulas.troopDps/troopHp`. Per-type, so it lives in Formulas, not ModifierService (which is for global multipliers). `GearService` handles x1/Max level upgrades.
- Packs (2b): `PackService` rolls server-side with `Random.new()`. Pity: `data.packs.sinceEpic`. Free packs: `StageService` tracks `highestBossDefeated` (also derived on load from highestStage) and fires `BossDefeated`; PackService grants `(highestBossDefeated - packs.rewardedBossStage) // BOSS_EVERY` packs, so it can never double-grant and back-fills older saves.
- `CombatService` = army numbers only (cached base DPS/HP, queued click/ability damage). `ModifierService` = the single place all multipliers are combined (`damage`, `gold`, `armyHp`); systems register a source function. Abilities use it now; Honor, faction, clan, and gear bonuses must plug in here too.
- Server-only per-player state (not saved): encounter (enemy HP, boss timer, army damage taken) in StageService, ability timers in AbilityService. Ability timestamps use `workspace:GetServerTimeNow()` so the client can count down locally.
- Client: `StateController` holds the latest snapshot and forwards notices; `InputController` batches clicks; `ShopController` (BuyTroop / UpgradeGear / OpenPack / BuyHonorUpgrade / Ascend); `AbilityController` (buttons + keys 1/2/3); `BattleController` (Fight Boss, auto-advance); `CommanderController` (avatar sword + swing); `BattlefieldController` + `HudUI` + `ShopUI` (tabs: `TroopTab`, `GearTab`, `PackTab`, `HonorTab`, shared types in `ShopTypes`; `ShopUI.openTab(title)`) + `AbilityBarUI` + `NoticeUI` + `PackRevealUI` + `AscendConfirmUI` + `OfflineEarningsUI` render from the snapshot.
- `Shared/Formulas.luau` is the single source of game math, used by the server for outcomes and by the client only for display previews.
- Troop costs are rounded to whole gold (`BigNum.round`) to avoid float error making exact prices unaffordable.
- Balance is checked with `tools/balance_sim.py` (Python mirror of the formulas; numbers copied by hand). Phase 2a result (boss HP x12, boss DPS 0.12 x enemy HP): active beats boss 10 at ~1.4 min, 50 at ~19 min, walls at ~59; idle reaches ~49 at 30 min. Active ~2.5x idle. Most boss fails are army HP, which 2b Armor addresses. With gear levels (base 5x troop cost, growth 1.9; packs not simulated): active reaches ~stage 68 at 30 min (vs 59 without), boss fails 11 -> 7.

## Conventions
- **Before every push, parse every Luau file**: `cargo build --release --manifest-path tools/luaucheck/Cargo.toml` once, then `tools/luaucheck/target/release/luaucheck $(find src -name '*.luau')` must print `files with errors: 0`. (Uses the full_moon Luau parser. Added after a Python edit turned a `\n` into a real newline inside a backtick string, which broke the whole client. When editing files with Python heredocs, write Luau `\n` as `\\n`.) The Rojo build alone does NOT catch syntax errors.
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
