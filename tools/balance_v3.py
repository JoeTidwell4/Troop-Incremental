"""Phase 13 aware balance check. Builds on balance_v2.py (same fight/economy model) and
adds the systems players collect over time, each grown from what actually feeds it:

  skills     Commander XP from boss wins (x2 first clear, every run) + Ascends -> points,
             spent Warlord -> Quartermaster -> Tactician (SkillConfig)
  generals   scrolls: 3 at stage 20, 1 per 40 stages per Ascend, ~1 per Ascend from
             achievements/quests; real odds; best 3 fielded; level ~ min(stars x 10, time)
  relics     35% per boss win from best stage 30, real odds + pity; best per slot equipped;
             players reroll toward damage lines (DAMAGE_LINE_SHARE); levels from Dust
  tower      best floor ~ (highest boss beaten - 58) / 2 -> +2% damage/gold per 10 floors
  gear       commander items unlocked by best stage / Ascends (no chests)
  extras     crits (+24% clicks), golden enemies (+19% gold), clan/faction (CLAN)

Usage: python tools/balance_v3.py [hours] [idle] [off]    (off = Phase 13 systems off)
       python tools/balance_v3.py sweep                    (several horizons, on vs off)
Everything is approximate on purpose: it's for spotting runaway or stalls, not for
exact stage numbers.
"""
import math, random, sys, os
sys.path.insert(0, os.path.dirname(__file__))
import balance_v2 as B

CLAN = dict(damage=1.15, hp=1.1, gold=1.1, tap=1.0)   # clan level ~5 + faction troop bonus is in v2
DAMAGE_LINE_SHARE = 0.45   # share of relic lines that end up as damage/boss damage after rerolls
GEN = {  # id: rarity, passive stat, value (traits folded into a small damage bonus)
    "Aldric": ("Rare", "damage", .05), "Lyra": ("Rare", "gold", .05), "Brannoc": ("Rare", "hp", .06),
    "Pip": ("Rare", "gold", .06), "Morwen": ("Epic", "damage", .08), "Garrick": ("Epic", "damage", .08),
    "Thessa": ("Epic", "tap", .12), "Rook": ("Epic", "damage", .08), "Isolde": ("Legendary", "hp", .12),
    "Varkas": ("Legendary", "damage", .12), "Seren": ("Legendary", "gold", .12), "Marshal": ("Mythic", "damage", .18)}
GEN_ODDS = [("Rare", 62), ("Epic", 28), ("Legendary", 9), ("Mythic", 1)]
TRAIT_DAMAGE = {"Rare": .08, "Epic": .12, "Legendary": .12, "Mythic": .25}   # rough troop-trait value as army damage
RELIC = [("Common", 55, 1, .8), ("Rare", 28, 2, 1.0), ("Epic", 12, 3, 1.25), ("Legendary", 4.5, 4, 1.6), ("Mythic", .5, 4, 2.25)]
RELIC_DUST = {"Common": 5, "Rare": 15, "Epic": 40, "Legendary": 120, "Mythic": 400}
SKILL_ORDER = (  # (stat, value) per point, in the order a damage-minded player buys
    [("damage", .05)] * 5 + [("hp", .06)] * 5 + [("damage", .35)] * 2 + [("boss", .08)] * 3 +
    [("time", 2)] * 3 + [("laststand", .3)] * 3 +            # Last Stand ~ +30% average vs bosses
    [("gold", .06)] * 5 + [("golden", .05)] * 3 + [("gold", .25)] * 2 + [("none", 0)] * 3 + [("honor", .05)] * 3 + [("gold", .4)] * 3 +
    [("tap", .08)] * 5 + [("crit", .04)] * 3 + [("tap", .3)] * 2 + [("none", 0)] * 3 + [("boss", .05)] * 3 + [("none", 0)] * 3)


def level_for(xp):
    level = 1
    while level < 100:
        need = math.floor(80 * 1.1 ** (level - 1))
        if xp < need: break
        xp -= need; level += 1
    return level


class State:
    def __init__(s, seed=3):
        s.rng = random.Random(seed)
        s.xp = 0.0; s.scrolls = 0; s.welcomed = False; s.gens = {}; s.hours = 0.0
        s.relics = {}; s.relic_count = 0; s.dust = 0; s.pity_l = 0; s.pity_m = 0
        s.tower = 0; s.ascends = 0

    # ---- feeding
    def after_run(s, run, best, hours):
        s.hours = hours
        wins = len(run.boss_beaten)
        for st in run.boss_beaten:
            s.xp += (10 + st // 5) * 2
        s.xp += 0.5 * run.highest
        s.ascends += 1
        if best >= 20 and not s.welcomed:
            s.welcomed = True; s.scrolls += 3
        if best >= 20:
            s.scrolls += run.highest // 40 + 1
        s.recruit()
        if best >= 30:
            for _ in range(sum(1 for st in run.boss_beaten if st >= 10)):
                if s.rng.random() < 0.35: s.drop_relic()
        top = max(run.boss_beaten) if run.boss_beaten else 0
        if best >= 75:
            s.tower = max(s.tower, (top - 58) // 2)

    def recruit(s):
        while s.scrolls > 0:
            s.scrolls -= 1
            roll = s.rng.random() * 100; acc = 0; rar = "Rare"
            for r, w in GEN_ODDS:
                acc += w
                if roll < acc: rar = r; break
            pool = [g for g, v in GEN.items() if v[0] == rar]
            g = s.rng.choice(pool)
            st = s.gens.setdefault(g, [0, 0])   # stars, copies
            st[1] += 1
            st[0] = 1 + sum(1 for c in (1, 3, 6, 11) if st[1] > c)

    def drop_relic(s):
        s.pity_l += 1; s.pity_m += 1
        roll = s.rng.random() * 100; acc = 0; pick = RELIC[0]
        for r in RELIC:
            acc += r[1]
            if roll < acc: pick = r; break
        if s.pity_m >= 100: pick = RELIC[4]
        elif s.pity_l >= 20 and RELIC.index(pick) < 3: pick = RELIC[3]
        if RELIC.index(pick) >= 3: s.pity_l = 0
        if pick[0] == "Mythic": s.pity_m = 0
        slot = s.rng.randrange(6)
        value = pick[2] * pick[3]   # lines x avg roll
        old = s.relics.get(slot)
        if old is None or value > old:
            if old is not None: s.dust += 15
            s.relics[slot] = value
        else:
            s.dust += RELIC_DUST[pick[0]]
        s.relic_count += 1

    # ---- effects
    def mults(s, best):
        d = hp = g = tap = boss = 1.0; btime = 0.0; honor = 1.0
        # skills
        pts = level_for(s.xp) - 1
        add = {}
        for stat, v in SKILL_ORDER[:pts]:
            add[stat] = add.get(stat, 0) + v
        d *= 1 + add.get("damage", 0); hp *= 1 + add.get("hp", 0); g *= 1 + add.get("gold", 0) + add.get("golden", 0) * 0.19
        tap *= 1 + add.get("tap", 0) + add.get("crit", 0) * 3; boss *= 1 + add.get("boss", 0) + add.get("laststand", 0)
        btime += add.get("time", 0); honor *= 1 + add.get("honor", 0)
        # generals: best 3 by value, level grows with time
        if s.gens:
            lv = min(10, 5 + s.hours * 2)
            vals = []
            for gid, (stars, _c) in s.gens.items():
                rar, stat, v = GEN[gid]
                level = min(stars * 10, lv)
                power = (1 + .05 * (level - 1)) * (1 + .25 * (stars - 1))
                vals.append((v * power + TRAIT_DAMAGE[rar] * (1 + .25 * (stars - 1)), stat, v * power, rar, stars))
            vals.sort(reverse=True)
            for total, stat, pv, rar, stars in vals[:3]:
                trait = TRAIT_DAMAGE[rar] * (1 + .25 * (stars - 1))
                if stat == "damage": d *= 1 + pv
                elif stat == "hp": hp *= 1 + pv
                elif stat == "gold": g *= 1 + pv
                else: tap *= 1 + pv
                d *= 1 + trait / 3     # troop traits help only one troop type
        # relics: sum of equipped values, damage share, levels from dust
        if s.relics:
            level = min(10, math.log(1 + s.dust / 40, 1.35))
            total = sum(s.relics.values()) * (1 + .1 * level)
            d *= 1 + total * DAMAGE_LINE_SHARE * 0.045
            hp *= 1 + total * 0.2 * 0.05
            g *= 1 + total * 0.2 * 0.04
            if s.relic_count >= 60: d *= 1.15; boss *= 1.3     # Inferno 2 + 4
            if s.relic_count >= 150: d *= 1.5                  # Inferno 6
        # tower
        tb = 1 + .02 * (s.tower // 10); d *= tb; g *= tb
        # commander gear
        tap *= 1.5 if best >= 120 else 1.3 if best >= 31 else 1.15 if best >= 25 else 1.05
        hp *= 1.35 if best >= 200 else 1.2 if best >= 100 else 1.1 if best >= 50 else 1.05 if best >= 10 else 1
        g *= 1.35 if best >= 150 else 1.2 if s.ascends >= 10 else 1.1 if s.ascends >= 1 else 1
        d *= 1.1 if best >= 75 else 1.05 if best >= 15 else 1
        # crits + golden enemies, clan
        tap *= 1.24; g *= 1.19
        if best >= 40:
            d *= CLAN["damage"]; hp *= CLAN["hp"]; g *= CLAN["gold"]
        return dict(damage=d, hp=hp, gold=g, tap=tap, boss=boss, bossTime=btime, honor=honor)


def campaign(hours=6, active=True, phase13=True, verbose=False, c=None):
    c = c or B.config()
    H, A = {}, {}; honor = 0; best = 1; total = 0.0; rows = []
    s = State()
    saved = dict(B.SOCIAL)
    while total < hours * 60:
        m = s.mults(best) if phase13 else None
        if m:
            B.SOCIAL.clear(); B.SOCIAL.update(damage=m["damage"] * m["boss"] ** 0.5, hp=m["hp"], gold=m["gold"], tap=m["tap"])
            c["boss_time"] = 30 + m["bossTime"]
        r = B.Run(c, H, A, best, active=active, seed=len(rows) + 1)
        r.play(min(hours * 60 - total, 240))
        total += r.t / 60
        best = max(best, r.highest)
        gain = B.honor_for(c, r.highest) * (m["honor"] if m else 1)
        honor = B.spend_honor(H, A, honor + gain, best, c)
        if phase13:
            s.after_run(r, best, total / 60)
        rows.append((round(total), r.highest, best, s.relic_count, level_for(s.xp), len(s.gens), s.tower))
    B.SOCIAL.clear(); B.SOCIAL.update(saved)
    if verbose:
        for t, hi, b, rc, lv, ng, tw in rows:
            print(f"{t:5d} min  run reached {hi:4d}  best {b:4d}  relics {rc:3d}  cmdr lv {lv:3d}  generals {ng:2d}  tower {tw:3d}")
        if phase13:
            print("final multipliers:", {k: round(v, 2) for k, v in s.mults(best).items()})
    return rows


def best_at(rows, minutes):
    b = 1
    for t, hi, best, *_ in rows:
        if t <= minutes: b = best
    return b


if __name__ == "__main__":
    args = sys.argv[1:]
    if "sweep" in args:
        for active in (True, False):
            on = campaign(12, active, True); off = campaign(12, active, False)
            label = "active" if active else "idle  "
            print(label, " ".join(f"{h}h: {best_at(off, h*60)}->{best_at(on, h*60)}" for h in (0.5, 1, 2, 3, 6, 9, 12)))
        sys.exit()
    hours = float(next((a for a in args if a.replace('.', '').isdigit()), 6))
    campaign(hours, "idle" not in args, "off" not in args, verbose=True)
