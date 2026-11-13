# Balance simulator (Python mirror of src/shared/Formulas.luau + config).
# Not part of the game. Run: python tools/balance_sim.py [bossHpMult] [bossDpsFactor] [-v]
# Simulates an idle player and an active player (7 clicks/sec + abilities on cooldown)
# with a greedy buyer (troops + gear levels; packs not simulated), bosses that hit back,
# and boss fail -> farm 60s -> retry. Pass -nogear to compare without gear.
# IMPORTANT: the numbers below are copied from src/shared/Config/*.luau by hand.
# If you change the config, update them here too before trusting the output.
import math, sys
TROOPS = [  # name, baseCost, growth, baseDps, baseHp
    ("Swordsman", 10, 1.07, 1.0, 12.0),
    ("Archer", 100, 1.08, 10.0, 25.0),
    ("Knight", 1500, 1.09, 110.0, 2600.0),
]
MILESTONES = [25, 50, 100, 200, 300, 400, 500]; REPEAT = 100; MULT = 2
ENEMIES = 10; HP_BASE, HP_G = 8, 1.17; GOLD_BASE, GOLD_G = 1.8, 1.15
TAP_FLAT, TAP_FRAC = 1.0, 0.08; START_GOLD = 10
GEAR_BASE=float(__import__('os').environ.get('GB','5')); GEAR_G=float(__import__('os').environ.get('GG','1.9'))  # GearConfig BASE_COST_MULTIPLIER / COST_GROWTH
BOSS_EVERY=10; BOSS_HP_MULT=float(sys.argv[1]) if len(sys.argv)>1 and sys.argv[1][0].isdigit() else 12; BOSS_GOLD_MULT=10; BOSS_TIME=30
BOSS_DPS_FACTOR=float(sys.argv[2]) if len(sys.argv)>2 and sys.argv[2][0].isdigit() else 0.12
# abilities: rally x2 10s/60s unlock5, barrage 20s dps /45s unlock15, plunder x2 gold 15s/120s unlock25
def mm(n):
    k = sum(1 for t in MILESTONES if n >= t)
    if n >= MILESTONES[-1] + REPEAT: k += (n - MILESTONES[-1]) // REPEAT
    return MULT ** k
GL=[[0,0],[0,0],[0,0]]
def geff(L): return (1+0.1*L)*2**(L//10)
def gcost(i,slot,L): return TROOPS[i][1]*GEAR_BASE*GEAR_G**L
def tdps(i,n,L=None): return n*TROOPS[i][3]*mm(n)*geff(GL[i][0] if L is None else L)
def thp(i,n,L=None): return n*TROOPS[i][4]*mm(n)*geff(GL[i][1] if L is None else L)
def cost(i,n): return TROOPS[i][1]*TROOPS[i][2]**n
def ehp(s): return HP_BASE*HP_G**(s-1)
def gold(s): return GOLD_BASE*GOLD_G**(s-1)
def isboss(s): return s % BOSS_EVERY == 0
def run(cps, minutes, label, active):
    global GL; GL=[[0,0],[0,0],[0,0]]
    c=[0,0,0]; g=START_GOLD; s=1; hs=1; kills=0; hp=ehp(1); t=0.0; dt=0.2
    auto=True; boss=None; farm_since=0; need='dps'; fails=0; wins=0
    cd={'r':0,'b':0,'p':0}; act={'r':0,'p':0}
    marks={}; log=[]
    while t < minutes*60:
        while True:  # buy
            best=None
            for i in range(3):
                cc=cost(i,c[i])
                if cc<=g:
                    if need=='hp': gain=(thp(i,c[i]+1)-thp(i,c[i]))/max(1,sum(thp(j,c[j]) for j in range(3)))
                    else: gain=(tdps(i,c[i]+1)-tdps(i,c[i]))/max(1,sum(tdps(j,c[j]) for j in range(3)))
                    e=gain/cc
                    if best is None or e>best[0]: best=(e,i,cc)
            if '-nogear' not in sys.argv:
              for i in range(3):
                for slot in (0,1):
                    if (slot==1) != (need=='hp'): continue
                    cc=gcost(i,slot,GL[i][slot])
                    if cc<=g and c[i]>0:
                        if slot==0: gain=(tdps(i,c[i],GL[i][0]+1)-tdps(i,c[i]))/max(1,sum(tdps(j,c[j]) for j in range(3)))
                        else: gain=(thp(i,c[i],GL[i][1]+1)-thp(i,c[i]))/max(1,sum(thp(j,c[j]) for j in range(3)))
                        e=gain/cc
                        if best is None or e>best[0]: best=(e,('g',i,slot),cc)
            if not best: break
            g-=best[2]
            if isinstance(best[1],tuple): GL[best[1][1]][best[1][2]]+=1
            else: c[best[1]]+=1
        base=sum(tdps(i,c[i]) for i in range(3))
        dm=2 if (active and t<act['r']) else 1
        gm=2 if (active and t<act['p']) else 1
        dps=base*dm
        dmg=dps*dt+(TAP_FLAT+dps*TAP_FRAC)*cps*dt
        if active:
            if hs>=5 and t>=cd['r']: cd['r']=t+60; act['r']=t+10
            if hs>=15 and t>=cd['b']: cd['b']=t+45; dmg+=dps*20
            if hs>=25 and t>=cd['p']: cd['p']=t+120; act['p']=t+15
        if boss:
            boss['army']-=boss['bdps']*dt
            if boss['army']<=0 or t>=boss['end']:
                need='hp' if boss['army']<=0 else 'dps'; fails+=1
                log.append(f"{t/60:5.1f}m FAIL stage {s} ({'army' if need=='hp' else 'time'})")
                s-=1; kills=0; hp=ehp(s); boss=None; auto=False; farm_since=t; continue
        if dmg<hp: hp-=dmg
        else:
            if boss:
                g+=gold(s)*BOSS_GOLD_MULT*gm; wins+=1; boss=None; need='dps'
                log.append(f"{t/60:5.1f}m WIN  stage {s}")
                s+=1; hs=max(hs,s); kills=0; hp=ehp(s)
            else:
                dmg-=hp; k=1+min(int(dmg//ehp(s)), ENEMIES-kills-1); dmg-=(k-1)*ehp(s)
                kills+=k; g+=k*gold(s)*gm
                if kills>=ENEMIES:
                    kills=0
                    if not auto and t-farm_since>=60: auto=True  # player retries after farming a minute
                    if auto:
                        s+=1; hs=max(hs,s)
                        if isboss(s):
                            army=sum(thp(i,c[i]) for i in range(3))
                            boss={'end':t+BOSS_TIME,'army':army,'bdps':ehp(s)*BOSS_DPS_FACTOR}
                            hp=ehp(s)*BOSS_HP_MULT
                        else: hp=ehp(s)
                    else: hp=ehp(s)
                else: hp=ehp(s)-min(dmg,ehp(s)-1e-9)
        t+=dt
        m=int(t//60)
        if m not in marks and t%60<dt: marks[m]=(s,c[:],base)
    print(f"{label}: wins {wins} fails {fails}")
    for m in [2,5,10,15,20,25,30]:
        if m in marks: print(f"  {m:>2}m stage {marks[m][0]:>3} troops {marks[m][1]} dps {marks[m][2]:.3g}")
    print("   gear", GL)
    if '-v' in sys.argv: print("\n".join(log[:40]))
run(0,31,"IDLE",False)
run(7,31,"ACTIVE 7cps + abilities",True)

