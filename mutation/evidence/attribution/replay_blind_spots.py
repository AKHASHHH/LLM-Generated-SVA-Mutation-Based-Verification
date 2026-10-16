#!/usr/bin/env python3
"""Independent check of the 20 adjudicated failures, using only the frozen spec model and vectors.
1. Every vector-row transition is reproduced by the spec model except rows with rst=0 (async reset
   applied before the scoreboard sample): those are the unobserved half cycles.
2. For M10: lists every reset row where PEND&IE changes at the preceding rising edge. Reference irq
   follows PEND&IE at once; M10's registered irq keeps the old value until the reset 5 ns later.
3. For M08: replays the last row held for the 2 tail cycles, with the M08 edit (restart gated by EN).
Usage (from mutation/): python3 evidence/attribution/replay_blind_spots.py
"""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts"))
import specmodel as M
rows = [l.split() for l in open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "vectors", "all.vec")) if l.strip()]
K = ['EN', 'MODE', 'IE', 'PSC', 'SHD', 'ACT', 'CNT', 'PCNT', 'PEND', 'OVF']
st = lambda r: dict(zip(K, [int(x, 16) for x in r[11:21]]))
inp = lambda r: (lambda v: dict(rst=v[0], psel=v[1], pen=v[2], pwr=v[3], addr=v[4], wdata=v[5]))([int(x, 16) for x in r[1:7]])
bad = [c for c in range(1, len(rows)) if M.nxt(st(rows[c-1]), inp(rows[c-1])) != st(rows[c])]
print(f"1. transitions not matching the spec model: {len(bad)}; all into rst=0 rows: {all(rows[c][1] == '0' for c in bad)}")
print("2. reset rows where PEND&IE changes at the rising edge just before the reset (M10 exposure):")
for c in bad:
    s, i = st(rows[c-1]), inp(rows[c-1]); n = M.nxt(s, i)
    if (s['PEND'] & s['IE']) != (n['PEND'] & n['IE']):
        print(f"   cycle {c}: edge {10*c+5} ns, reset {10*(c+1)} ns: reference irq={n['PEND'] & n['IE']}, M10 irq={s['PEND'] & s['IE']}")
def nxt_m08(s, i):
    if i['rst'] and i['psel'] and i['pen'] and i['pwr'] and M.dec(i['addr']) == M.CMD and (i['wdata'] & 1) and s['EN'] == 0:
        i = dict(i, wdata=i['wdata'] & ~1)
    return M.nxt(s, i)
print("3. M08, last row held after the vectors end:", inp(rows[-1]))
ref = mut = st(rows[-1])
for k in (len(rows), len(rows) + 1):
    ref, mut = M.nxt(ref, inp(rows[-1])), nxt_m08(mut, inp(rows[-1]))
    print(f"   cycle {k}: reference ACT={ref['ACT']:#x} CNT={ref['CNT']:#x} PCNT={ref['PCNT']:#x} | M08 ACT={mut['ACT']:#x} CNT={mut['CNT']:#x} PCNT={mut['PCNT']:#x}")
