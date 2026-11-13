# Balance simulator v2 (after Phase 11). Python mirror of the game's formulas and configs.
# Not part of the game. Numbers are copied by hand from src/shared/Config; keep them in sync.
#
# Run:   python tools/balance_v2.py            (current game, "active" player, 6 hours)
#        python tools/balance_v2.py 8 idle     (8 hours, no clicks / abilities / weak points)
#        python tools/balance_v2.py old        (numbers from before the balance pass)
#
# Balance pass results (active / idle): first Ascend ~29 min at stage 80; ~190 / ~150 by
# 6-8 h; troop damage stays mixed (no type above ~65%); boss survival 17-67 s depending on
# how tanky the army is. Old numbers: Siege did 95-100% of the damage, armies always died
# at the 16.7 s cap, and active ran away to stage 940 in 6 h through Commander's Might.
#
# The simulated player: buys whatever adds the most value per gold (damage and some HP),
# opens a pack about once a minute, uses abilities on cooldown, clicks 7/s, hits weak
# points, retries failed bosses after getting stronger, and Ascends when stuck for a while
# past stage 50, spending Honor on the cheapest upgrade each time.
import math, random, sys

def config(old=False):
    c = dict(
        troops=[  # id, baseCost, costGrowth, dps, hp, unlock, bossMult, normalMult
            ("Swordsman", 10, 1.07, 1, 12, 0, 1, 1),
            ("Archer", 100, 1.08, 10, 25, 0, 1, 1),
            ("Knight", 1500, 1.09, 110, 2600, 0, 1, 1),
            ("Mage", 2e4, 1.10, 90, 60, 30, 2, 1),
            ("Cavalry", 1.5e6, 1.11, 4000, 30000, 60, 1, 1.5),
            ("Siege", 1e8, 1.12, 5e5, 50, 100, 3, 1),
        ],
        milestones=[25, 50, 100, 200, 300, 400, 500], ms_every=100, ms_mult=2,
        hp_base=8, hp_growth=1.17, gold_base=1.8, gold_growth=1.15, enemies=10,
        boss_hp=12, boss_gold=10, boss_dps=0.12, boss_time=30, intro=2, cap=0.12,
        drain_min=0.015, drain_max=0.06, enrage_at=0.3, enrage_mult=2,
        gear_base=5, gear_growth=1.9, gear_eff=0.10, gear_tier=10, gear_tier_mult=2,
        honor_min=50, honor_base=10, honor_growth=1.08,
        tap_frac=0.08,
        boss_mode="clamp",  # "clamp" = current game: drain clamped to [min, max] of army max HP / s
        might=("mult", 1.5, 999),  # ("mult", x per level, max level) or ("add", +x per level, max level)
        might_cost=(2, 1.5),
        # Legacy (LegacyConfig). `python tools/balance_v2.py legacy [hours] [idle]`.
        # Shipped: first Legacy ~stage 200 (~27 Crowns) for an active player, back past the
        # old best in ~1h45m, then +40-50 stages per Legacy. scale 1 / x1.5 took ~4 h.
        legacy=dict(min_stage=150, unit=1e5, exp=0.5, scale=3,
                    armory=1.6, guard=1.6, treasury=1.6, glory=1.25,
                    cost=dict(Armory=(1, 1.6), Guard=(1, 1.6), Treasury=(1, 1.6), Glory=(2, 1.7))),
    )
    if not old:
        c.update(NEW)
    return c

# The balance pass (now in the game). config() starts from the old numbers above.
NEW = dict(
    might=("add", 0.1, 10),
    troops=[
        ("Swordsman", 10, 1.07, 1, 12, 0, 1, 1),
        ("Archer", 100, 1.08, 10, 25, 0, 1, 1),
        ("Knight", 1500, 1.09, 110, 2600, 0, 1, 1),
        ("Mage", 2e4, 1.10, 300, 200, 30, 2, 1),
        ("Cavalry", 1.5e6, 1.11, 4000, 30000, 60, 1, 1.5),
        ("Siege", 1e8, 1.12, 11000, 4000, 100, 2, 1),
    ],
)

RARITY = [1, 1.5, 2.5, 4, 7]
BASIC = [60, 25, 10, 4, 1]; ELITE = [0, 50, 35, 12, 3]; ROYAL = [0, 0, 60, 32, 8]
AREA_TRAITS = [None, "Archer", "Knight", "Swordsman", "Archer", "Knight", "Siege", "Mage", "Cavalry", "Archer"]
AREA_MOVES = [(), ("Shield",), ("Enrage",), ("Summon",), ("Enrage", "Shield"), ("Enrage", "Shield", "Summon"),
              ("Summon", "Shield"), ("Shield", "Enrage"), ("Summon", "Enrage"), ("Enrage", "Shield", "Summon")]
HONOR_UP = {  # base, growth, effect
    "Drills": (3, 1.5), "WarChest": (3, 1.5), "Fortitude": (3, 1.5), "Might": (2, 1.5), "HeadStart": (5, 1.8)}
ABILITY_UP = {"RallyPower": (4, 1.7), "RallyTime": (4, 1.7), "BarragePower": (5, 1.7), "BarrageCd": (5, 1.7),
              "PlunderPower": (6, 1.7), "PlunderTime": (6, 1.7)}
# Social + wardrobe bonuses a decent player has (clan perks/level, commander gear), from stage 40.
SOCIAL = dict(damage=1.25, hp=1.2, gold=1.2, tap=1.2)
FACTION = "Knight"


class Run:
    def __init__(s, c, honor_up, ability_up, best, active=True, seed=1, crowns=None):
        s.c = c; s.H = honor_up; s.A = ability_up; s.best = best; s.active = active
        s.C = crowns or {}
        s.rng = random.Random(seed)
        s.ids = [t[0] for t in c["troops"]]
        s.T = {t[0]: t for t in c["troops"]}
        s.count = {i: 0 for i in s.ids}
        s.gear = {i: [0, 0] for i in s.ids}       # weapon, armor levels
        s.rar = {i: [1, 1] for i in s.ids}        # rarity index 1..5
        s.gold = 10 * 8 ** honor_up.get("HeadStart", 0)
        s.stage = 1; s.highest = 1; s.kills = 0; s.partial = 0.0
        s.t = 0.0; s.since_epic = 0; s.free_packs = 0; s.boss_beaten = set()
        s.last_progress = 0.0; s.log = {}; s.boss_log = {}; s.weaken = {}
        s.retry_at = 0.0; s.farming = False

    # ---------------- formulas
    def ms(s, n):
        c = s.c; r = sum(1 for m in c["milestones"] if n >= m)
        last = c["milestones"][-1]
        if n >= last + c["ms_every"]:
            r += (n - last) // c["ms_every"]
        return c["ms_mult"] ** r
    def gear_eff(s, L):
        c = s.c; return (1 + c["gear_eff"] * L) * c["gear_tier_mult"] ** (L // c["gear_tier"])
    def unlocked(s, i):
        return s.best >= s.T[i][5]
    def mods(s):
        H = s.H; social = s.stage >= 40 or s.best >= 40
        d = 1.25 ** H.get("Drills", 0) * (SOCIAL["damage"] if social else 1)
        hp = 1.25 ** H.get("Fortitude", 0) * (SOCIAL["hp"] if social else 1)
        g = 1.2 ** H.get("WarChest", 0) * (SOCIAL["gold"] if social else 1)
        kind, x, cap = s.c["might"]; L = min(H.get("Might", 0), cap)
        tap = (x ** L if kind == "mult" else 1 + x * L) * (SOCIAL["tap"] if social else 1)
        C = s.C; lg = s.c["legacy"]
        d *= lg["armory"] ** C.get("Armory", 0)
        hp *= lg["guard"] ** C.get("Guard", 0)
        g *= lg["treasury"] ** C.get("Treasury", 0)
        return d, hp, g, tap
    def troop_dps(s, i, n=None, wl=None, wr=None, boss=False, stage=None):
        n = s.count[i] if n is None else n
        if n <= 0: return 0.0
        t = s.T[i]; wl = s.gear[i][0] if wl is None else wl; wr = s.rar[i][0] if wr is None else wr
        m = t[6] if boss else t[7]
        if FACTION == i: m *= 1.5
        area = ((stage or s.stage) - 1) // 10 % 10
        if AREA_TRAITS[area] == i: m *= 0.7
        return n * t[3] * s.gear_eff(wl) * RARITY[wr - 1] * m * s.ms(n)
    def troop_hp(s, i, n=None, al=None, ar=None):
        n = s.count[i] if n is None else n
        if n <= 0: return 0.0
        t = s.T[i]; al = s.gear[i][1] if al is None else al; ar = s.rar[i][1] if ar is None else ar
        m = 1.5 if FACTION == i else 1
        return n * t[4] * s.gear_eff(al) * RARITY[ar - 1] * m * s.ms(n)
    def army_dps(s, boss=False, stage=None):
        return sum(s.troop_dps(i, boss=boss, stage=stage) for i in s.ids) * s.mods()[0]
    def army_hp(s):
        return sum(s.troop_hp(i) for i in s.ids) * s.mods()[1]
    def enemy_hp(s, st): return s.c["hp_base"] * s.c["hp_growth"] ** (st - 1)
    def gpk(s, st): return s.c["gold_base"] * s.c["gold_growth"] ** (st - 1)
    def troop_cost(s, i, owned, k):
        t = s.T[i]; g = t[2]
        return t[1] * g ** owned * (g ** k - 1) / (g - 1)
    def gear_cost(s, i, L): return s.T[i][1] * s.c["gear_base"] * s.c["gear_growth"] ** L
    def ab(s, key, base, per):
        return base + per * s.A.get(key, 0)

    # ---------------- shopping
    def value(s):
        # Mostly damage (normal + boss), some HP.
        nd = sum(s.troop_dps(i, stage=s.highest) for i in s.ids) + 1e-9
        bd = sum(s.troop_dps(i, boss=True, stage=s.highest) for i in s.ids) + 1e-9
        hp = sum(s.troop_hp(i) for i in s.ids) + 1e-9
        return 0.5 * math.log(nd) + 0.5 * math.log(bd) + 0.3 * math.log(hp)
    def shop(s):
        for _ in range(40):
            base = s.value(); best = None
            for i in s.ids:
                if not s.unlocked(i): continue
                n = s.count[i]
                nxt = next((m for m in s.c["milestones"] if m > n), None)
                if nxt is None:
                    last = s.c["milestones"][-1]; e = s.c["ms_every"]
                    nxt = last + ((n - last) // e + 1) * e
                for k in sorted({1, nxt - n}):
                    cost = s.troop_cost(i, n, k)
                    s.count[i] += k; v = s.value(); s.count[i] -= k
                    cand = ((v - base) / cost, cost, ("troop", i, k))
                    if best is None or cand[0] > best[0]: best = cand
                if n > 0:
                    for slot in (0, 1):
                        cost = s.gear_cost(i, s.gear[i][slot])
                        s.gear[i][slot] += 1; v = s.value(); s.gear[i][slot] -= 1
                        cand = ((v - base) / cost, cost, ("gear", i, slot))
                        if cand[0] > best[0]: best = cand
            if best is None or best[1] > s.gold: return
            s.gold -= best[1]
            kind, i, x = best[2]
            if kind == "troop": s.count[i] += x
            else: s.gear[i][x] += 1

    def open_pack(s, odds):
        roll = s.rng.random() * 100; acc = 0; r = 1
        for idx, w in enumerate(odds):
            acc += w
            if roll < acc: r = idx + 1; break
        s.since_epic += 1
        if s.since_epic >= 20 and r < 4: r = 4
        if r >= 4: s.since_epic = 0
        ids = [i for i in s.ids if s.unlocked(i)]
        i = s.rng.choice(ids); slot = s.rng.randrange(2)
        if r > s.rar[i][slot]: s.rar[i][slot] = r

    # ---------------- fighting
    def fight_boss(s, st):
        c = s.c
        weak = 1 - s.weaken.get(st, 0)
        hp_max = s.enemy_hp(st) * c["boss_hp"] * weak; hp = hp_max
        moves = AREA_MOVES[(st - 1) // 10 % 10]
        minions = 0.0; summoned = False
        dmg_taken = 0.0; dt = 0.2; t = 0.0; T = c["boss_time"]
        dps = s.army_dps(boss=True, stage=st)
        d, hpm, g, tapm = s.mods()
        rally_mult = s.ab("RallyPower", 2, 0.15); rally_len = s.ab("RallyTime", 10, 0.5)
        barrage = s.ab("BarragePower", 20, 1.5)
        army_max = s.army_hp()
        queued_burst = 0.0
        # Abilities ready at the start (a good player saves them for bosses).
        if s.active:
            if s.best >= 15: queued_burst = barrage * dps * (rally_mult if s.best >= 5 else 1)
        next_wp = 4.0; streak = 0
        while t < T + c["intro"]:
            t += dt
            if t < c["intro"]: continue
            ft = t - c["intro"]
            rally = s.active and s.best >= 5 and ft < rally_len
            m = rally_mult if rally else 1
            shield = "Shield" in moves and (ft % 10) >= 7
            troop = 0 if shield else dps * m * dt
            q = 0.0
            if s.active:
                q += 7 * dt * (1 + c["tap_frac"] * dps * m) * tapm
                if queued_burst > 0: q += queued_burst; queued_burst = 0
                if ft >= next_wp:
                    q += 3 * dps * m * (1 + min(0.3, 0.1 * streak)); streak += 1; next_wp += 8
            damage = min(troop + q, hp_max * c["cap"] * dt)
            if minions > 0:
                use = min(minions, damage); minions -= use; damage -= use
            hp -= damage
            if "Summon" in moves and not summoned and hp < hp_max * 0.6:
                summoned = True; minions = hp_max * 0.15
            if hp <= 0:
                return True, ft, None
            if c["boss_mode"] == "clamp":
                raw = s.enemy_hp(st) * c["boss_dps"]
                rate = min(c["drain_max"], max(c["drain_min"], raw / max(army_max, 1e-9)))
                frac = rate * dt * (c["enrage_mult"] if ("Enrage" in moves and hp < hp_max * c["enrage_at"]) else 1)
                dmg_taken += frac
            else:
                raw = s.enemy_hp(st) * c["boss_dps"] * dt
                if "Enrage" in moves and hp < hp_max * c["enrage_at"]: raw *= c["enrage_mult"]
                rate = raw / dt / max(army_max, 1e-9)
                lo, hi = c["drain_min"], c["drain_max"]
                dmg_taken += min(hi, max(lo, rate)) * dt
            if dmg_taken >= 1:
                return False, ft, "Army"
        return False, T, "Time"

    def boss_numbers(s, st):
        # For the report: seconds to kill (troops + clicks only), seconds the army survives.
        c = s.c; dps = s.army_dps(boss=True, stage=st)
        hp = s.enemy_hp(st) * c["boss_hp"]
        kill = max(hp / max(dps, 1e-9), 1 / c["cap"])
        raw = s.enemy_hp(st) * c["boss_dps"]
        rate = min(c["drain_max"], max(c["drain_min"], raw / max(s.army_hp(), 1e-9)))
        return kill, 1 / rate

    def play(s, minutes, stop_after_stuck=3.0):
        dt = 0.2; c = s.c; next_shop = 0; next_pack = 30; plunder_until = -1; next_plunder = 0
        while s.t < minutes * 60:
            st = s.stage
            if st % 10 == 0:
                if s.farming and s.t < s.retry_at:
                    s.stage = st - 1; continue
                win, dur, why = s.fight_boss(st)
                s.t += dur + c["intro"]
                key = st
                if key not in s.boss_log:
                    k, surv = s.boss_numbers(st)
                    share = s.share(st)
                    s.boss_log[key] = dict(t=s.t / 60, first=win, why=why, kill=k, surv=surv, share=share, tries=1)
                else:
                    s.boss_log[key]["tries"] += 1
                if win:
                    s.weaken.pop(st, None)
                    s.gold += s.gpk(st) * c["boss_gold"] * s.mods()[2]
                    if st not in s.boss_beaten: s.boss_beaten.add(st); s.free_packs += 1
                    s.stage = st + 1; s.kills = 0; s.farming = False
                else:
                    s.weaken[st] = min(0.5, s.weaken.get(st, 0) + 0.1)
                    s.stage = st - 1; s.farming = True; s.retry_at = s.t + 45
                continue
            # normal stage tick
            s.t += dt
            d, hpm, g, tapm = s.mods()
            dps = s.army_dps(stage=st)
            if s.active:
                dps += 7 * (1 + c["tap_frac"] * dps) * tapm
            hp = s.enemy_hp(st)
            total = dps * dt + s.partial
            kills = min(c["enemies"] - s.kills, int(total // hp))
            s.partial = total - kills * hp if kills < c["enemies"] - s.kills else 0
            gm = g * (s.ab("PlunderPower", 2, 0.1) if s.active and s.t < plunder_until else 1)
            if s.active and s.best >= 25 and s.t >= next_plunder:
                plunder_until = s.t + s.ab("PlunderTime", 15, 0.7); next_plunder = s.t + 120
            s.gold += kills * s.gpk(st) * gm
            s.kills += kills
            if s.kills >= c["enemies"]:
                s.kills = 0; s.partial = 0
                if not s.farming:
                    s.stage = st + 1
            if s.stage > s.highest:
                s.highest = s.stage; s.last_progress = s.t
                s.best = max(s.best, s.highest)
                for mark in range(10, 1001, 10):
                    if s.highest >= mark and mark not in s.log: s.log[mark] = s.t / 60
            if s.t >= next_shop:
                next_shop = s.t + 1; s.shop()
                if s.farming and s.t >= s.retry_at: s.stage = (st // 10 + 1) * 10 if st % 10 == 9 else st
            if s.t >= next_pack:
                next_pack = s.t + 60
                while s.free_packs > 0: s.free_packs -= 1; s.open_pack(BASIC)
                tier = ROYAL if s.best >= 40 else ELITE if s.best >= 20 else BASIC
                kills = 180 if tier is ROYAL else 70 if tier is ELITE else 25
                price = s.gpk(s.highest) * kills
                if price <= 0.3 * s.gold: s.gold -= price; s.open_pack(tier)
            if s.highest >= c["honor_min"] and s.t - s.last_progress > stop_after_stuck * 60:
                return "stuck"
        return "time"

    def share(s, st):
        tot = sum(s.troop_dps(i, boss=True, stage=st) for i in s.ids) or 1
        return {i[:3]: round(s.troop_dps(i, boss=True, stage=st) / tot * 100) for i in s.ids if s.count[i] > 0}


def honor_for(c, st):
    return 0 if st < c["honor_min"] else math.floor(c["honor_base"] * c["honor_growth"] ** (st - c["honor_min"]))


def spend_honor(H, A, honor, best, c):
    while True:
        options = []
        for k, (b, g) in HONOR_UP.items():
            if k == "Might":
                b, g = c["might_cost"]
                if H.get(k, 0) >= c["might"][2]: continue
            options.append((b * g ** H.get(k, 0), "H", k))
        for k, (b, g) in ABILITY_UP.items():
            if A.get(k, 0) < 10: options.append((b * g ** A.get(k, 0), "A", k))
        cost, kind, k = min(options)
        if cost > honor: return honor
        honor -= cost
        (H if kind == "H" else A)[k] = (H if kind == "H" else A).get(k, 0) + 1


def campaign(c, hours=6, active=True, verbose=True):
    H, A = {}, {}; honor = 0; best = 1; total = 0.0; run_no = 0; rows = []
    while total < hours * 60:
        run_no += 1
        r = Run(c, H, A, best, active=active, seed=run_no)
        left = hours * 60 - total
        r.play(min(left, 240))
        total += r.t / 60
        best = max(best, r.highest)
        gain = honor_for(c, r.highest)
        rows.append((run_no, round(total), r.highest, gain, r))
        honor = spend_honor(H, A, honor + gain, best, c)
    if verbose:
        report(c, rows)
    return rows


def crowns_for(c, honor_this_legacy):
    lg = c["legacy"]
    return int(lg["scale"] * (honor_this_legacy / lg["unit"]) ** lg["exp"])


def spend_crowns(c, C, crowns):
    cost = c["legacy"]["cost"]
    while True:
        k = min(cost, key=lambda k: cost[k][0] * cost[k][1] ** C.get(k, 0))
        price = cost[k][0] * cost[k][1] ** C.get(k, 0)
        if price > crowns: return crowns
        crowns -= price; C[k] = C.get(k, 0) + 1


def legacy_campaign(c, hours=30, active=True, stall_runs=4):
    # Plays Ascend runs; Legacies once past the unlock stage and 'stall_runs' runs in a row
    # brought no new best for this Legacy. Prints one line per Legacy.
    C = {}; bank = 0; total = 0.0; legacies = 0; all_best = 1
    lg = c["legacy"]
    while total < hours * 60:
        H, A = {}, {}; honor = 0; best_this = 1; earned = 0; stall = 0; start = total
        regained_at = None; old_best = all_best
        while total < hours * 60:
            r = Run(c, H, A, max(all_best, best_this), active=active, seed=int(total) + 1, crowns=C)
            r.play(min(hours * 60 - total, 240))
            total += r.t / 60
            gain = int(honor_for(c, r.highest) * lg["glory"] ** C.get("Glory", 0))
            earned += gain
            if r.highest > best_this:
                best_this = r.highest; stall = 0
            else:
                stall += 1
            if regained_at is None and legacies > 0 and best_this >= old_best:
                regained_at = total - start
            honor = spend_honor(H, A, honor + gain, max(all_best, best_this), c)
            if best_this >= lg["min_stage"] and stall >= stall_runs:
                break
        all_best = max(all_best, best_this)
        crowns = crowns_for(c, earned)
        legacies += 1
        bank = spend_crowns(c, C, bank + crowns)
        back = f"regained old best {old_best} after {regained_at:.0f} min" if regained_at is not None else ("first Legacy" if legacies == 1 else f"did NOT regain {old_best}")
        print(f"legacy {legacies:2d} at {total:5.0f} min: best this Legacy {best_this:4d}, honor {earned:.2e}, +{crowns} Crowns, upgrades {C}  ({back})")


def report(c, rows):
    for run_no, total, highest, gain, r in rows:
        print(f"run {run_no:2d}: ended at {total:4d} min, reached stage {highest:4d}, +{gain:,} Honor")
    print()
    print("boss  run  1st  why    kill_s  survive_s  tries  damage share (vs bosses)")
    for run_no, total, highest, gain, r in rows:
        for st in sorted(r.boss_log):
            if st % 20 and st < highest - 10:
                continue
            b = r.boss_log[st]
            print(f"{st:4d} {run_no:4d}  {'win ' if b['first'] else 'FAIL'} {str(b['why'] or ''):6s} {b['kill']:7.1f} {b['surv']:9.1f} {b['tries']:6d}  {b['share']}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "legacy" in args:
        c = config(old="old" in args)
        legacy_campaign(c, hours=float(next((a for a in args if a.replace('.', '').isdigit()), 30)), active="idle" not in args)
        sys.exit()
    c = config(old="old" in args)
    campaign(c, hours=float(next((a for a in args if a.replace('.', '').isdigit()), 6)), active="idle" not in args)
