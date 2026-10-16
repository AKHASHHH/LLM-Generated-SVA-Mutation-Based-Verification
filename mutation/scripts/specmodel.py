# Executable model of APBTMR-SPEC v1.0 (written by Claude Opus, the spec author). Produces EXPECTED values.
# It reproduced all 23 spec example tables; an independently written row checker re-verified them.
CTRL,LOAD,COUNT,STATUS,CMD,ACTIVE,PSCNT=0x00,0x04,0x08,0x0C,0x10,0x14,0x18
NAMES={CTRL:"CTRL",LOAD:"LOAD",COUNT:"COUNT",STATUS:"STATUS",CMD:"CMD",ACTIVE:"ACTIVE",PSCNT:"PSCNT"}
MAPPED={CTRL,LOAD,COUNT,STATUS,CMD,ACTIVE,PSCNT}; RO={COUNT,ACTIVE,PSCNT}
def reset(): return dict(EN=0,MODE=0,IE=0,PSC=0,SHD=0,ACT=0,CNT=0,PCNT=0,PEND=0,OVF=0)
IDLE=dict(rst=1,psel=0,pen=0,pwr=0,addr=0,wdata=0,lbl="idle")
def dec(a): return a & 0xFC
def comb(s,i):
    acc=i['psel'] and i['pen']; a=dec(i['addr'])
    err = acc and ((a not in MAPPED) or (i['pwr'] and a in RO))
    rd = 0
    if acc and not i['pwr'] and a in MAPPED:
        rd={CTRL:(s['PSC']<<8)|(s['IE']<<2)|(s['MODE']<<1)|s['EN'],LOAD:s['SHD'],COUNT:s['CNT'],
            STATUS:(s['OVF']<<1)|s['PEND'],CMD:0,ACTIVE:s['ACT'],PSCNT:s['PCNT']}[a]
    return rd,int(bool(err)),s['PEND']&s['IE']
def events(s):
    run=s['EN']==1; tick=run and s['PCNT']>=s['PSC']; exp=tick and s['CNT']==0
    return run,tick,exp
def nxt(s,i):
    if not i['rst']: return reset()
    acc=i['psel'] and i['pen']; a=dec(i['addr']); d=i['wdata']
    wr = acc and i['pwr'] and a in MAPPED and a not in RO
    wC,wL,wS,wM = wr and a==CTRL, wr and a==LOAD, wr and a==STATUS, wr and a==CMD
    run,tick,exp=events(s)
    start = wC and (d&1)==1 and s['EN']==0
    restart = wM and (d&1)==1
    n=dict(s)
    if wC: n.update(EN=d&1,MODE=(d>>1)&1,IE=(d>>2)&1,PSC=(d>>8)&0xFF)
    if exp and s['MODE']==1: n['EN']=0            # one-shot completion beats SW write of EN
    if wL: n['SHD']=d&0xFFFF
    if start or restart:
        n['ACT']=s['SHD']; n['CNT']=s['SHD']; n['PCNT']=0
    else:
        if exp and s['MODE']==0: n['ACT']=s['SHD']; n['CNT']=s['SHD']
        elif exp and s['MODE']==1: n['CNT']=0
        elif tick: n['CNT']=s['CNT']-1
        if run: n['PCNT']=0 if tick else s['PCNT']+1
    if exp: n['PEND']=1
    elif wS and (d&1): n['PEND']=0
    if exp and s['PEND']: n['OVF']=1
    elif wS and (d>>1)&1: n['OVF']=0
    return n
# stimulus helpers
def W(a,d,tag=None):
    t=tag or f"W {NAMES.get(dec(a),hex(a))}"
    return [dict(IDLE,psel=1,pen=0,pwr=1,addr=a,wdata=d,lbl=f"setup {t}"),
            dict(IDLE,psel=1,pen=1,pwr=1,addr=a,wdata=d,lbl=f"**ACCESS {t}=0x{d:X}**")]
def R(a,tag=None):
    t=tag or f"R {NAMES.get(dec(a),'0x%02X'%a)}"
    return [dict(IDLE,psel=1,pen=0,pwr=0,addr=a,lbl=f"setup {t}"),
            dict(IDLE,psel=1,pen=1,pwr=0,addr=a,lbl=f"**ACCESS {t}**")]
def I(n): return [dict(IDLE) for _ in range(n)]
def RST(n): return [dict(IDLE,rst=0,lbl="PRESETn=0") for _ in range(n)]
def run(seq):
    s=reset(); rows=[]
    for i in seq:
        st = reset() if not i['rst'] else s
        rd,err,irq=comb(st,i); _,tick,exp=events(st) if i['rst'] else (0,0,0)
        rows.append((i,dict(st),rd,err,irq,tick,exp)); s=nxt(st,i)
    return rows,s
def table(rows,start=0,reset_col=False):
    h="| cyc | "+("PRESETn | " if reset_col else "")+"APB activity in this cycle | EN | MODE | IE | PSC | SHADOW | ACTIVE | COUNT | PCNT | PEND | OVF | irq | PRDATA | PSLVERR | tick / expire |"
    out=[h,"|"+"---|"*(h.count("|")-1)]
    for k,(i,s,rd,err,irq,tick,exp) in enumerate(rows[start:]):
        ev="tick+**EXPIRE**" if exp else ("tick" if tick else "")
        out.append(f"| {k} | "+(f"{i['rst']} | " if reset_col else "")+f"{i['lbl']} | {s['EN']} | {s['MODE']} | {s['IE']} | {s['PSC']} | {s['SHD']} | {s['ACT']} | {s['CNT']} | {s['PCNT']} | {s['PEND']} | {s['OVF']} | {irq} | 0x{rd:X} | {err} | {ev} |")
    return "\n".join(out)
