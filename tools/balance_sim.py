# Balance simulator (Python mirror of src/shared/Formulas.luau + config).
# Not part of the game. Run: python tools/balance_sim.py
# IMPORTANT: the numbers below are copied from src/shared/Config/*.luau by hand.
# If you change the config, update them here too before trusting the output.
TROOPS = [  # name, baseCost, growth, baseDps
    ("Swordsman", 10, 1.07, 1.0),
    ("Archer", 100, 1.08, 10.0),
    ("Knight", 1500, 1.09, 110.0),
]
MILESTONES = [25, 50, 100, 200, 300, 400, 500]; REPEAT = 100; MULT = 2
ENEMIES = 10
HP_BASE, HP_G = 8, 1.17
GOLD_BASE, GOLD_G = 1.5, 1.15
TAP_FLAT, TAP_FRAC = 1.0, 0.08
START_GOLD = 10

def milestone_mult(n):
    k = sum(1 for t in MILESTONES if n >= t)
    if n >= MILESTONES[-1] + REPEAT:
        k += (n - MILESTONES[-1]) // REPEAT
    return MULT ** k
def tdps(i, n): return n * TROOPS[i][3] * milestone_mult(n)
def cost(i, n): return TROOPS[i][1] * TROOPS[i][2] ** n
def hp(s): return HP_BASE * HP_G ** (s - 1)
def gold(s): return GOLD_BASE * GOLD_G ** (s - 1)

def run(cps, minutes, label):
    counts = [0, 0, 0]; g = START_GOLD; s = 1; kills = 0; ehp = hp(1); t = 0.0; dt = 0.2
    marks = {}
    while t < minutes * 60:
        # greedy buy
        while True:
            best = None
            for i in range(3):
                c = cost(i, counts[i])
                if c <= g:
                    gain = tdps(i, counts[i] + 1) - tdps(i, counts[i])
                    eff = gain / c
                    if best is None or eff > best[0]: best = (eff, i, c)
            if not best: break
            g -= best[2]; counts[best[1]] += 1
        army = sum(tdps(i, counts[i]) for i in range(3))
        tap = TAP_FLAT + army * TAP_FRAC
        d = army * dt + tap * cps * dt
        # resolve
        if d < ehp: ehp -= d
        else:
            d -= ehp; k = 1
            extra = min(int(d // hp(s)), ENEMIES - kills - 1); k += extra; d -= extra * hp(s)
            kills += k; g += k * gold(s)
            if kills >= ENEMIES: s += 1; kills = 0; ehp = hp(s)
            else: ehp = hp(s) - min(d, hp(s) - 1e-9)
        t += dt
        m = int(t // 60)
        if m not in marks and t % 60 < dt: marks[m] = (s, counts[:], army)
    print(label)
    for m in [1, 2, 5, 10, 15, 20, 25, 30]:
        if m in marks: print(f"  {m:>2}m stage {marks[m][0]:>3} troops {marks[m][1]} dps {marks[m][2]:.3g}")
run(0, 31, "IDLE (0 cps)")
run(7, 31, "ACTIVE (7 cps)")
run(15, 31, "AUTOCLICKER CAP (15 cps)")
