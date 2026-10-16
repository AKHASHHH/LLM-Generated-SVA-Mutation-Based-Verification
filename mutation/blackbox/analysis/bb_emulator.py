"""ANALYSIS ONLY (Experiment 2 root-cause study). Not part of the measured experiment and not a checker.
Python transcription of: the frozen spec model with each mutant's one-line edit (mutants/mutants.diff), and
the two frozen black-box checkers (blackbox/gen/sva_bb_*_1.sv), sampled as at each rising PCLK edge
(inputs of row c, outputs of cycle c, checker registers before their update).
Validated against real VCS: reproduces every mutant's audited port-divergence count, zero baseline failures,
and the detection sets GPT {M10}, Claude {M08, M10}. VCS logs remain the authority."""
import os, sys
ROOT=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..'))
sys.path.insert(0,os.path.join(ROOT,'scripts')); sys.dont_write_bytecode=True
import specmodel as M
from collections import defaultdict
rows=[l.split() for l in open(os.path.join(ROOT,'vectors','all.vec')) if l.strip()]
inp=lambda r:(lambda v:dict(rst=v[0],psel=v[1],pen=v[2],pwr=v[3],addr=v[4],wdata=v[5]))([int(x,16) for x in r[1:7]])
# ---------- design models: spec model with each mutant's one-line edit ----------
def nxt(s,i,mut=None):
    if not i['rst']: return M.reset()
    acc=i['psel'] and i['pen']; a=M.dec(i['addr']); d=i['wdata']
    wr=acc and i['pwr'] and a in M.MAPPED and a not in M.RO
    wC,wL,wS,wM=wr and a==M.CTRL, wr and a==M.LOAD, wr and a==M.STATUS, wr and a==M.CMD
    run=s['EN']==1; tick=run and (s['PCNT']==s['PSC'] if mut=='M07' else s['PCNT']>=s['PSC']); exp=tick and s['CNT']==0
    start=wC and (d&1)==1 and (True if mut=='M05' else s['EN']==0)
    restart=wM and (d&1)==1 and (s['EN']==1 if mut=='M08' else True)
    n=dict(s)
    if wC: n.update(EN=d&1,MODE=(d>>1)&1,IE=(d>>2)&1,PSC=(d>>8)&0xFF)
    if exp and s['MODE']==1 and not (mut=='M04' and wC): n['EN']=0
    if wL: n['SHD']=d&0xFFFF
    newshd=n['SHD']
    if start or restart:
        n['ACT']=s['SHD']; n['CNT']=s['SHD']
        n['PCNT']=(0 if restart else s['PCNT']) if mut=='M06' else 0
    else:
        rl=newshd if mut=='M03' else s['SHD']
        if exp and s['MODE']==0: n['ACT']=rl; n['CNT']=rl
        elif exp and s['MODE']==1: n['CNT']=0
        elif tick: n['CNT']=s['CNT']-1
        if run: n['PCNT']=0 if tick else (s['PCNT']+1)&0xFF
    clr=wS and (d&1)
    if mut=='M01': n['PEND']=0 if clr else (1 if exp else s['PEND'])
    elif mut=='M09': n['PEND']=1 if (exp and s['IE']) else (0 if clr else s['PEND'])
    else: n['PEND']=1 if exp else (0 if clr else s['PEND'])
    ovfset=exp and s['PEND'] and not (mut=='M02' and clr)
    n['OVF']=1 if ovfset else (0 if (wS and (d>>1)&1) else s['OVF'])
    return n
def stream(mut=None):
    """per cycle: (row, inputs, outputs dict, state) as sampled at the rising edge ending that cycle"""
    s=M.reset(); irq_q=0; out=[]
    for c,row in enumerate(rows):
        i=inp(row)
        if not i['rst']: s=M.reset(); irq_q=0
        prd,err,irq=M.comb(s,i)
        if mut=='M10': irq=irq_q
        out.append((c,i,dict(PRDATA=prd,PSLVERR=err,PREADY=1,irq=irq),dict(s)))
        if mut=='M10': irq_q=(s['PEND']&s['IE']) if i['rst'] else 0
        s=nxt(s,i,mut)
    return out
# ---------- checker emulators (transcribed from the frozen SVA files) ----------
def dec(i,o):
    acc=bool(i['psel'] and i['pen']); rd=acc and not i['pwr']; wr=acc and bool(i['pwr']); w=(i['addr']>>2)&0x3F
    return acc,rd,wr,w
def gpt(st, record):
    sh=0; cfg=0; sk=1; sknown=1; obs=0
    for c,i,o,_ in st:
        P=i['rst']; acc,rd,wr,w=dec(i,o); prd=o['PRDATA']; mapped=w<=6; ro=w in (2,5,6)
        err_exp=acc and ((not mapped) or (i['pwr'] and ro))
        if not P: sh=0; cfg=0; sk=1; sknown=1; obs=0
        A=lambda name,ante,cons,dis=False: record('gpt',name,c,ante and not dis,cons)
        A('R_APB_3',True,o['PREADY']==1); A('R_APB_8',True,o['PSLVERR']==err_exp)
        A('R_APB_7',(not rd) or (not mapped),prd==0)
        A('R_APB_6_CTRL',rd and w==0,(prd>>16)==0 and ((prd>>3)&0x1F)==0)
        for nm,ww,mask in (('LOAD',1,0xFFFF0000),('COUNT',2,0xFFFF0000),('STATUS',3,0xFFFFFFFC),('ACTIVE',5,0xFFFF0000),('PSCNT',6,0xFFFFFF00)):
            A('R_APB_6_'+nm,rd and w==ww,(prd&mask)==0)
        A('R_APB_6_CMD',rd and w==4,prd==0)
        A('R_TMR_11',rd and w==1,prd==sh,not P)
        A('R_PRI_6',rd and w==0,(((prd>>8)&0xFF)<<2|((prd>>1)&3))==cfg,not P)
        A('R_PRI_2',rd and w==0 and sk,not (prd&1),not P)
        A('R_INT_2',rd and w==3 and sk and sknown,(prd&1)==(obs&1),not P)
        A('R_INT_4',rd and w==3 and sk and sknown,((prd>>1)&1)==((obs>>1)&1),not P)
        ie=(cfg>>1)&1
        A('R_INT_6',rd and w==3,o['irq']==((prd&1) and ie),not P)
        A('R_INT_6_KNOWN',sk and sknown,o['irq']==((obs&1) and ie),not P)
        A('R_RST_1_IRQ',not P,o['irq']==0); A('R_RST_4_READ',(not P) and rd and mapped,prd==0); A('R_RST_2',(not P) and rd and w==0,prd==0)
        if P:
            pe=not o['PSLVERR']; cw=wr and w==0 and pe; lw=wr and w==1 and pe; sw=wr and w==3 and pe; d=i['wdata']
            nsh=d&0xFFFF if lw else sh; ncfg=(((d>>8)&0xFF)<<2|((d>>1)&3)) if cw else cfg
            nsk=(not (d&1)) if cw else sk; nsknown=sknown; nobs=obs
            if cw and (d&1): nsknown=0
            elif cw and not (d&1) and not sk: nsknown=0
            elif sk:
                if sw and sknown: nobs=obs&~(d&3)
                if rd and w==3 and pe: nobs=prd&3; nsknown=1
            sh,cfg,sk,sknown,obs=nsh,ncfg,int(bool(nsk)),nsknown,nobs
def claude(st, record):
    R=dict(en=0,mode=0,ie=0,psc=0,sh=0,ps=0,os=0,pz=1,oz=1,cv=1,av=1,pv=1,cl=0,al=0,pl=0,hit=1)
    prev=None
    for c,i,o,_ in st:
        P=i['rst']; acc,rd,wr,w=dec(i,o); prd=o['PRDATA']; d=i['wdata']; irq=o['irq']; mapped=w<=6
        if not P: R=dict(en=0,mode=0,ie=0,psc=0,sh=0,ps=0,os=0,pz=1,oz=1,cv=1,av=1,pv=1,cl=0,al=0,pl=0,hit=1)
        exp_err=acc and ((not mapped) or (i['pwr'] and w in (2,5,6)))
        cw,lw,sw,mw=wr and w==0,wr and w==1,wr and w==3,wr and w==4
        rc,rs,ra,rp,rctl=rd and w==2,rd and w==3,rd and w==5,rd and w==6,rd and w==0
        start=cw and (d&1) and not R['en']; restart=mw and (d&1)
        dis_rst=bool(R['hit']) or not P
        A=lambda name,ante,cons,dis=False: record('claude',name,c,ante and not dis,cons)
        A('R_RST_4',not P,irq==0 and prd==0); A('R_APB_3',True,o['PREADY']==1); A('R_APB_8',True,o['PSLVERR']==exp_err)
        A('R_APB_7',not (rd and mapped),prd==0)
        A('R_APB_6_CTRL',rctl,(prd>>16)==0 and ((prd>>8)&0xFF)==R['psc'] and ((prd>>3)&0x1F)==0 and ((prd>>2)&1)==R['ie'] and ((prd>>1)&1)==R['mode'] and ((prd&1)==0 or R['en']))
        A('R_APB_6_LOAD',rd and w==1,prd==R['sh'])
        A('R_APB_6_COUNT',rc,(prd>>16)==0); A('R_APB_6_STATUS',rs,(prd>>2)==0); A('R_APB_6_CMD',rd and w==4,prd==0)
        A('R_APB_6_ACTIVE',ra,(prd>>16)==0); A('R_APB_6_PSCNT',rp,(prd>>8)==0)
        A('R_TMR_2_COUNT',rc and R['cv'],(prd&0xFFFF)==R['cl']); A('R_TMR_2_ACTIVE',ra and R['av'],(prd&0xFFFF)==R['al']); A('R_TMR_2_PSCNT',rp and R['pv'],(prd&0xFF)==R['pl'])
        if prev:
            pd=prev['dis']
            A('R_TMR_7_COUNT',prev['start'] and rc,(prd&0xFFFF)==prev['sh'],pd or dis_rst)
            A('R_TMR_7_ACTIVE',prev['start'] and ra,(prd&0xFFFF)==prev['sh'],pd or dis_rst)
            A('R_TMR_7_PSCNT',prev['start'] and rp,(prd&0xFF)==0,pd or dis_rst)
            A('R_TMR_7_EN',prev['start'] and rctl,(prd&1)==1,pd or dis_rst)
            A('R_TMR_9_COUNT',prev['restart'] and rc,(prd&0xFFFF)==prev['sh'],pd or dis_rst)
            A('R_TMR_9_ACTIVE',prev['restart'] and ra,(prd&0xFFFF)==prev['sh'],pd or dis_rst)
            A('R_TMR_9_PSCNT',prev['restart'] and rp,(prd&0xFF)==0,pd or dis_rst)
            pp=prev['prd']
            A('R_TMR_3',rc and prev['rc'] and (pp&0xFFFF)!=0,(prd&0xFFFF) in ((pp&0xFFFF),((pp&0xFFFF)-1)&0xFFFF),dis_rst)
            A('R_TMR_4',rc and prev['rc'] and (pp&0xFFFF)==0,(prd&0xFFFF) in (0,prev['sh']),dis_rst)
            A('R_TMR_11',ra and prev['ra'],(prd&0xFFFF) in ((pp&0xFFFF),prev['sh']),dis_rst)
            A('R_TMR_1',rp and prev['rp'],(prd&0xFF)==(pp&0xFF) or (prd&0xFF)==0 or ((prd&0xFF)==(pp&0xFF)+1 and (pp&0xFF)<prev['psc']),dis_rst)
            A('R_INT_2_FALL',prev['irq'] and not irq,prev['fallcause'],dis_rst)
        A('R_INT_2',rs and R['ps'],(prd&1)==1); A('R_INT_4',rs and R['os'],((prd>>1)&1)==1)
        A('R_INT_5_PEND',rs and R['pz'],(prd&1)==0); A('R_INT_5_OVF',rs and R['oz'],((prd>>1)&1)==0)
        A('R_INT_6_READ',rs,irq==((prd&1) & R['ie'])); A('R_INT_6_IE',bool(irq),R['ie']==1); A('R_INT_1',bool(irq),not R['pz'])
        prev=dict(start=start,restart=restart,sh=R['sh'],psc=R['psc'],prd=prd,rc=rc,ra=ra,rp=rp,irq=irq,dis=dis_rst,
                  fallcause=bool((sw and (d&1)) or (cw and not (d>>2)&1)))
        if P:
            N=dict(R); N['hit']=0
            if cw: N.update(en=d&1,mode=(d>>1)&1,ie=(d>>2)&1,psc=(d>>8)&0xFF)
            if lw: N['sh']=d&0xFFFF
            if rs: N['ps']=prd&1; N['os']=(prd>>1)&1
            elif sw:
                if d&1: N['ps']=0
                if (d>>1)&1: N['os']=0
            if cw and (d&1): N['pz']=0; N['oz']=0
            elif sw and not R['en']:
                if d&1: N['pz']=1
                if (d>>1)&1: N['oz']=1
            if (cw and (d&1)) or restart: N['cv']=N['av']=N['pv']=0
            elif rd and not R['en']:
                if rc: N['cv']=1; N['cl']=prd&0xFFFF
                if ra: N['av']=1; N['al']=prd&0xFFFF
                if rp: N['pv']=1; N['pl']=prd&0xFF
            R=N
def run(mut=None, ref=None):
    act=defaultdict(int); fails=defaultdict(list)
    def record(chk,name,c,ante,cons):
        if ante:
            act[(chk,name)]+=1
            if not cons: fails[(chk,name)].append(c)
    st=stream(mut); gpt(st,record); claude(st,record)
    return st,act,fails
