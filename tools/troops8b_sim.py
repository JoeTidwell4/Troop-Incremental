# Phase 8b simulator: multi-run Ascend sim with Mage/Cavalry/Siege, area traits and boss moves.
# Python mirror of the formulas + config (numbers copied by hand). Not part of the game.
# Run: python tools/troops8b_sim.py   Env: NEW=0 (old 3 troops), MOVES=0, TRAITS=0, S (scale new troop dps),
# SC / SD (Siege cost / base dps before S). Defaults = shipped TroopConfig values.
import math, os
NEW = os.environ.get('NEW','1')=='1'; MOVES = os.environ.get('MOVES','1')=='1'; TRAITS = os.environ.get('TRAITS','1')=='1'
S=float(os.environ.get('S','0.1'))  # scale new troop dps
# name, cost, growth, dps, hp, unlock(bestStage), vsBoss, vsNormal
T=[("Swordsman",10,1.07,1,12,0,1,1),("Archer",100,1.08,10,25,0,1,1),("Knight",1500,1.09,110,2600,0,1,1)]
if NEW: T+=[("Mage",20000,1.10,900*S,60,30,2,1),("Cavalry",1.5e6,1.11,40000*S,30000,60,1,1.5),("Siege",float(os.environ.get("SC","1e8")),1.12,float(os.environ.get("SD","5e6"))*S,50,100,3,1)]
N=len(T)
TRAIT={2:"Archer",3:"Knight",4:"Swordsman",5:"Archer",6:"Knight"}  # area -> penalised troop (area 1 none)
MOVESET={1:(),2:("shield",),3:("enrage",),4:("summon",),5:("enrage","shield"),6:("enrage","shield","summon")}
MIL=[25,50,100,200,300,400,500]
HPB,HPG=8,1.17; GB,GG=1.8,1.15
def mm(n):
    k=sum(1 for t in MIL if n>=t)
    if n>=600: k+=(n-500)//100
    return 2**k
def geff(L): return (1+0.1*L)*2**(L//10)
def ehp(s): return HPB*HPG**(s-1)
def gold(s): return GB*GG**(s-1)
def honor(s): return 0 if s<50 else math.floor(10*1.08**(s-50))
UP={'dmg':(3,1.5,0.25),'gold':(3,1.5,0.20),'hp':(3,1.5,0.25),'tap':(2,1.5,0.5),'start':(5,1.8,0)}
def eff(k,L): return (1+UP[k][2])**L
def area(s): return (s-1)//10%6+1
def run(up,best,limit=60,cps=7):
    c=[0]*N; GL=[[0,0] for _ in range(N)]
    g=10*8**up['start']; s=1; hs=1; kills=0; t=0.0; dt=0.2; hp=ehp(1)
    dm,gm,hm,tm=eff('dmg',up['dmg']),eff('gold',up['gold']),eff('hp',up['hp']),eff('tap',up['tap'])
    auto=True; boss=None; farm=0; need='dps'; cd={'r':0,'b':0,'p':0}; act={'r':0,'p':0}; last_new=0; reach={}
    def mult(i,isboss):
        m=T[i][6] if isboss else T[i][7]
        if TRAITS and TRAIT.get(area(s))==T[i][0]: m*=0.7
        return m
    def tdps(i,n,L=None,isboss=False): return n*T[i][3]*mm(n)*geff(GL[i][0] if L is None else L)*mult(i,isboss)
    def thp(i,n,L=None): return n*T[i][4]*mm(n)*geff(GL[i][1] if L is None else L)
    while t<limit*60:
        bb=max(best,hs)
        while True:
            best_=None
            nb = boss is not None or need!='dps' or (s%10==9)
            totd=max(1,sum(tdps(j,c[j],isboss=nb) for j in range(N))); toth=max(1,sum(thp(j,c[j]) for j in range(N)))
            for i in range(N):
                if T[i][5]>bb: continue
                cc=T[i][1]*T[i][2]**c[i]
                if cc<=g:
                    gain=(thp(i,c[i]+1)-thp(i,c[i]))/toth if need=='hp' else (tdps(i,c[i]+1,isboss=nb)-tdps(i,c[i],isboss=nb))/totd
                    if best_ is None or gain/cc>best_[0]: best_=(gain/cc,('t',i),cc)
                for sl in (0,1):
                    if (sl==1)!=(need=='hp') or c[i]==0: continue
                    cc=T[i][1]*5*1.9**GL[i][sl]
                    if cc<=g:
                        gain=(tdps(i,c[i],GL[i][0]+1,nb)-tdps(i,c[i],isboss=nb))/totd if sl==0 else (thp(i,c[i],GL[i][1]+1)-thp(i,c[i]))/toth
                        if best_ is None or gain/cc>best_[0]: best_=(gain/cc,('g',i,sl),cc)
            if not best_: break
            g-=best_[2]
            if best_[1][0]=='t': c[best_[1][1]]+=1
            else: GL[best_[1][1]][best_[1][2]]+=1
        isb = boss is not None
        base=sum(tdps(i,c[i],isboss=isb) for i in range(N))*dm
        rally=2 if t<act['r'] else 1; plunder=2 if t<act['p'] else 1
        dps=base*rally; tap=(1+dps*0.08)*tm*cps
        shielded = isb and MOVES and 'shield' in boss['moves'] and (t-boss['start'])%10>=7
        dmg=(0 if shielded else dps*dt)+tap*dt
        if bb>=5 and t>=cd['r']: cd['r']=t+60; act['r']=t+10
        if bb>=15 and t>=cd['b']: cd['b']=t+45; dmg+=dps*20
        if bb>=25 and t>=cd['p']: cd['p']=t+120; act['p']=t+15
        if boss:
            enr = MOVES and 'enrage' in boss['moves'] and hp < boss['max']*0.3
            boss['army']-=boss['bdps']*(2 if enr else 1)*dt
            if boss['army']<=0 or t>=boss['end']:
                need='hp' if boss['army']<=0 else 'dps'
                s-=1; kills=0; hp=ehp(s); boss=None; auto=False; farm=t; t+=dt; continue
        if dmg<hp: hp-=dmg
        else:
            if boss:
                g+=gold(s)*10*gm*plunder; boss=None; need='dps'; s+=1; kills=0; hp=ehp(s)
            else:
                dmg-=hp; k=1+min(int(dmg//ehp(s)),10-kills-1); kills+=k; g+=k*gold(s)*gm*plunder
                if kills>=10:
                    kills=0
                    if not auto and t-farm>=60: auto=True
                    if auto:
                        s+=1
                        if s%10==0:
                            mv=MOVESET[area(s)] if MOVES else ()
                            extra=ehp(s)*12*0.15 if 'summon' in mv else 0
                            boss={'end':t+30,'army':sum(thp(i,c[i]) for i in range(N))*hm,'bdps':ehp(s)*0.12,'moves':mv,'start':t,'max':ehp(s)*12}
                            hp=ehp(s)*12+extra
                        else: hp=ehp(s)
                    else: hp=ehp(s)
                else: hp=ehp(s)-min(dmg,ehp(s)-1e-9)
            if s>hs: hs=s; last_new=t; reach[hs]=t
        t+=dt
        if hs>=50 and t-last_new>180: break
    return hs,t,c
up={k:0 for k in UP}; h=0; best=0; total=0
for r in range(1,7):
    hs,t,c=run(up,best); best=max(best,hs); gain=honor(hs); total+=t
    print(f"run {r}: best {hs:>3} in {t/60:5.1f}m  +{gain} honor  troops {[int(x) for x in c]}")
    h+=gain
    while True:
        opts=[(UP[k][0]*UP[k][1]**up[k],k) for k in UP]; cost,k=min(opts)
        if cost>h: break
        h-=cost; up[k]+=1
print("total", round(total/60,1),"min")
