#!/usr/bin/env python3
"""ANALYSIS ONLY. Reproduces the M07/M09 root-cause tables of docs/RCA_M07_M09.md from the frozen vectors,
spec model, mutant edits and checker transcriptions. Writes nothing. Usage (from mutation/):
    python3 blackbox/analysis/rca_m07_m09.py"""
import os, sys
sys.dont_write_bytecode=True; sys.path.insert(0,os.path.dirname(os.path.abspath(__file__)))
from bb_emulator import *
ROOTV=os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..'))
TESTS={int(l.split()[0]):l.split()[1] for l in open(os.path.join(ROOTV,'vectors','tests.idx')) if not l.startswith('#')}
ref=stream(None)
print("1. Emulator validation against the audited VCS results")
for m in ['M01','M02','M03','M04','M05','M06','M07','M08','M09','M10']:
    st,act,f=run(m); pd=sum(1 for x,y in zip(ref,st) if x[2]!=y[2])
    print(f"   {m}: port-diverging cycles {pd:4d} | GPT {'DETECT' if any(k[0]=='gpt' for k in f) else 'miss'} | Claude {'DETECT' if any(k[0]=='claude' for k in f) else 'miss'}")
_,_,f=run(None); print("   reference failures:", len(f))
for mut,rel in (('M07',['R_INT_6','R_INT_6_KNOWN','R_APB_6_PSCNT','R_APB_6_COUNT','R_TMR_1','R_TMR_2_PSCNT','R_TMR_2_COUNT','R_TMR_3','R_INT_6_READ','R_INT_6_IE','R_INT_1','R_INT_2_FALL']),
                ('M09',['R_INT_6','R_INT_6_KNOWN','R_INT_2','R_PRI_2','R_APB_6_CTRL','R_INT_2','R_INT_5_PEND','R_INT_6_READ','R_INT_6_IE','R_INT_1','R_INT_2_FALL'])):
    st=stream(mut); pdiv={x[0] for x,y in zip(ref,st) if x[2]!=y[2]}; adiv={x[0] for x,y in zip(ref,st) if x[2]!=y[2] or x[3]!=y[3]}
    att=defaultdict(int); ap=defaultdict(int); aa=defaultdict(int); fl=defaultdict(int)
    def rec(chk,name,c,ante,cons):
        if ante: att[(chk,name)]+=1; ap[(chk,name)]+=c in pdiv; aa[(chk,name)]+=c in adiv; fl[(chk,name)]+=not cons
    gpt(st,rec); claude(st,rec)
    print(f"\n2. {mut}: port-diverging {len(pdiv)} (first {min(pdiv)}), any divergence {len(adiv)} (first {min(adiv)})")
    print("   checker assertion        attempts  in-port-div  in-any-div  failures")
    for chk in ('gpt','claude'):
        for n in dict.fromkeys(rel):
            if (chk,n) in att: print(f"   {chk:7s} {n:16s} {att[(chk,n)]:8d} {ap[(chk,n)]:12d} {aa[(chk,n)]:11d} {fl[(chk,n)]:9d}")
