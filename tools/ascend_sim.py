# Multi-run Ascend simulator (Python mirror of the formulas + config; numbers copied by hand).
# Not part of the game. Run: python tools/ascend_sim.py
# An active player (7 clicks/sec, abilities on cooldown, greedy troop + gear buyer) plays a run,
# Ascends after being stuck 3 minutes past AscendConfig.MIN_STAGE, spends Honor on the cheapest
# Honor upgrade repeatedly, and goes again. Env overrides: MIN, HB, HG (Honor formula), EFF=add|mult.
import math, sys, os
TROOPS=[("Swordsman",10,1.07,1.0,12.0),("Archer",100,1.08,10.0,25.0),("Knight",1500,1.09,110.0,2600.0)]
MIL=[25,50,100,200,300,400,500]
ENEMIES=10; HPB,HPG=8,1.17; GB,GG=1.8,1.15; TAPF,TAPR=1.0,0.08
BOSS_HP=12; BOSS_GOLD=10; BOSS_T=30; BOSS_DPS=0.12
GEARB,GEARG=5,1.9
MIN_STAGE=int(os.environ.get('MIN','50')); HON_B=float(os.environ.get('HB','10')); HON_G=float(os.environ.get('HG','1.08'))
MODE=os.environ.get('EFF','mult')  # 'add' or 'mult'
UP={ # id: base, growth, effect per level
 'dmg':(3,1.5,0.25),'gold':(3,1.5,0.20),'hp':(3,1.5,0.25),'tap':(2,1.5,0.5),'start':(5,1.8,0)}
def eff(k,L):
    e=UP[k][2]
    return (1+e)**L if MODE=='mult' else 1+e*L
def mm(n):
    k=sum(1 for t in MIL if n>=t)
    if n>=600: k+=(n-500)//100
    return 2**k
def geff(L): return (1+0.1*L)*2**(L//10)
def ehp(s): return HPB*HPG**(s-1)
def gold(s): return GB*GG**(s-1)
def honor(s): return 0 if s<MIN_STAGE else math.floor(HON_B*HON_G**(s-MIN_STAGE))
def run(up, limit_min, cps=7):
    c=[0,0,0]; GL=[[0,0],[0,0],[0,0]]
    g=10*8**up['start']; s=1; hs=1; kills=0; t=0.0; dt=0.2; hp=ehp(1)
    dm,gm,hm,tm=eff('dmg',up['dmg']),eff('gold',up['gold']),eff('hp',up['hp']),eff('tap',up['tap'])
    auto=True; boss=None; farm=0; need='dps'; cd={'r':0,'b':0,'p':0}; act={'r':0,'p':0}
    tdps=lambda i,n,L=None: n*TROOPS[i][3]*mm(n)*geff(GL[i][0] if L is None else L)
    thp=lambda i,n,L=None: n*TROOPS[i][4]*mm(n)*geff(GL[i][1] if L is None else L)
    reach={}; last_new=0
    while t<limit_min*60:
        while True:
            best=None
            tot_d=max(1,sum(tdps(j,c[j]) for j in range(3))); tot_h=max(1,sum(thp(j,c[j]) for j in range(3)))
            for i in range(3):
                cc=TROOPS[i][1]*TROOPS[i][2]**c[i]
                if cc<=g:
                    gain=(thp(i,c[i]+1)-thp(i,c[i]))/tot_h if need=='hp' else (tdps(i,c[i]+1)-tdps(i,c[i]))/tot_d
                    if best is None or gain/cc>best[0]: best=(gain/cc,('t',i),cc)
                for sl in (0,1):
                    if (sl==1)!=(need=='hp') or c[i]==0: continue
                    cc=TROOPS[i][1]*GEARB*GEARG**GL[i][sl]
                    if cc<=g:
                        gain=(tdps(i,c[i],GL[i][0]+1)-tdps(i,c[i]))/tot_d if sl==0 else (thp(i,c[i],GL[i][1]+1)-thp(i,c[i]))/tot_h
                        if best is None or gain/cc>best[0]: best=(gain/cc,('g',i,sl),cc)
            if not best: break
            g-=best[2]
            if best[1][0]=='t': c[best[1][1]]+=1
            else: GL[best[1][1]][best[1][2]]+=1
        base=sum(tdps(i,c[i]) for i in range(3))*dm
        rally=2 if t<act['r'] else 1; plunder=2 if t<act['p'] else 1
        dps=base*rally
        dmg=dps*dt+(TAPF+dps*TAPR)*tm*cps*dt
        if hs>=5 and t>=cd['r']: cd['r']=t+60; act['r']=t+10
        if hs>=15 and t>=cd['b']: cd['b']=t+45; dmg+=dps*20
        if hs>=25 and t>=cd['p']: cd['p']=t+120; act['p']=t+15
        if boss:
            boss['army']-=boss['bdps']*dt
            if boss['army']<=0 or t>=boss['end']:
                need='hp' if boss['army']<=0 else 'dps'
                s-=1; kills=0; hp=ehp(s); boss=None; auto=False; farm=t; t+=dt; continue
        if dmg<hp: hp-=dmg
        else:
            if boss:
                g+=gold(s)*BOSS_GOLD*gm*plunder; boss=None; need='dps'; s+=1; kills=0; hp=ehp(s)
            else:
                dmg-=hp; k=1+min(int(dmg//ehp(s)),ENEMIES-kills-1); kills+=k; g+=k*gold(s)*gm*plunder
                if kills>=ENEMIES:
                    kills=0
                    if not auto and t-farm>=60: auto=True
                    if auto:
                        s+=1
                        if s%10==0:
                            boss={'end':t+BOSS_T,'army':sum(thp(i,c[i]) for i in range(3))*hm,'bdps':ehp(s)*BOSS_DPS}; hp=ehp(s)*BOSS_HP
                        else: hp=ehp(s)
                    else: hp=ehp(s)
                else: hp=ehp(s)-min(dmg,ehp(s)-1e-9)
            if s>hs:
                hs=s; last_new=t
                reach[hs]=t
        t+=dt
        # player ascends when stuck 3 minutes past the min stage
        if hs>=MIN_STAGE and t-last_new>180: break
    return hs, t, reach
def buy(up, h):
    while True:
        opts=[(UP[k][0]*UP[k][1]**up[k],k) for k in ('dmg','gold','hp','tap','start')]
        cost,k=min(opts)
        if cost>h: return h
        h-=cost; up[k]+=1
up={k:0 for k in UP}; h=0; total=0
for r in range(1,6):
    hs,t,reach=run(up,60)
    gain=honor(hs); total+=t
    print(f"run {r}: stage {MIN_STAGE} at {reach.get(MIN_STAGE,float('nan'))/60:5.1f}m, best {hs} at ascend {t/60:5.1f}m -> +{gain} honor  | upgrades {up}")
    h=buy(up,h+gain)
print("total minutes", round(total/60,1))
