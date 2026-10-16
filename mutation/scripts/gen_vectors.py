#!/usr/bin/env python3
"""Generate the deterministic vector set for the Project 4 v2 testbench.

Every vector line is one clock cycle:
  tid rst psel penable pwrite paddr pwdata | exp_prdata exp_pslverr exp_pready exp_irq |
  exp_en exp_mode exp_ie exp_psc exp_shadow exp_active exp_count exp_pcnt exp_pend exp_ovf
All fields are hexadecimal, space separated (the '|' separators are not written).
Expected values come from scripts/specmodel.py (the executable spec model), NOT from the reference RTL.

Outputs (in ../vectors/):
  all.vec        all tests concatenated (each test starts with a reset cycle)
  tests.idx      tid, name, number of cycles, description
Usage: python3 gen_vectors.py
"""
import os, random, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from specmodel import *          # noqa: F401,F403
import spec_examples

C = lambda en=0, mode=0, ie=0, psc=0: (psc << 8) | (ie << 2) | (mode << 1) | en

def align(pre, op, want_exp=True, post=4, kmax=600):
    """insert k idle cycles so that op's ACCESS cycle is (or is not) an expiration cycle"""
    for k in range(kmax):
        seq = pre + I(k) + op
        rows, _ = run(seq)
        if bool(rows[len(seq) - 1][6]) == want_exp:
            return pre + I(k) + op + I(post)
    raise RuntimeError("alignment failed")

def find(pre, op, pred, post=4, kmax=600):
    """insert k idle cycles so that the state/event of op's ACCESS cycle satisfies pred(state, tick, expire)"""
    for k in range(kmax):
        seq = pre + I(k) + op
        rows, _ = run(seq)
        r = rows[len(seq) - 1]
        if pred(r[1], r[5], r[6]):
            return pre + I(k) + op + I(post)
    raise RuntimeError("search failed")

def acc(a, d=0, w=1, lbl="b2b"):
    return dict(IDLE, psel=1, pen=1, pwr=w, addr=a, wdata=d, lbl=lbl)

TESTS = []   # (name, description, seq)
for k, (title, seq) in enumerate(spec_examples.EX, 1):
    TESTS.append((f"EX{k:02d}", f"Spec example {k}: {title}", seq))

def D(name, desc, seq):
    TESTS.append((name, desc, seq))

# ---------------------------------------------------------------- directed tests
p = W(LOAD, 3) + W(CTRL, C(en=1, ie=1))
D("D01_W1C_AT_EXP_PEND0", "STATUS W1C coincident with first expiration (PEND=0): PEND=1, OVF=0 (R-PRI-4, R-INT-3)",
  align(p, W(STATUS, 1)))

p = W(LOAD, 4) + W(CTRL, C(en=1, ie=1)) + I(12)                    # two expirations -> PEND=1, OVF=1
p = find(p, W(STATUS, 1), lambda st, t, e: not e and st['CNT'] == 4, post=0)   # clear PEND just after a reload
p = find(p, W(STATUS, 2), lambda st, t, e: e and st['PEND'] == 0, post=2)     # OVF clear at expiration, PEND=0 -> clears
p = find(p, W(STATUS, 2), lambda st, t, e: e and st['PEND'] == 1, post=3)     # PEND=1 -> OVF set wins
D("D02_OVF_CLR_AT_EXP", "OVF W1C at expiration with PEND=0 (clears) and with PEND=1 (set wins) (R-PRI-5, R-INT-3/4)", p)

D("D03_CONT_EXP_CLEARS", "LOAD=0, PSC=0 periodic: expiration every cycle, repeated STATUS=0x3 never clears (R-PRI-4/5)",
  W(LOAD, 0) + W(CTRL, C(en=1, ie=1)) + I(2) + W(STATUS, 3) + W(STATUS, 3) + W(STATUS, 3) + I(2))

D("D04_ONESHOT_MODE0_AT_COMPLETION", "One-shot completion coincident with CTRL write EN=1,MODE=0: EN=0, COUNT stays 0 (R-PRI-2, R-TMR-12)",
  align(W(LOAD, 2) + W(CTRL, C(en=1, mode=1)), W(CTRL, C(en=1, mode=0, ie=1)), True, 5))

D("D05_TICK_WITH_EN0", "Non-expiring tick coincident with CTRL EN=0: decrement still happens (R-TMR-8)",
  align(W(LOAD, 5) + W(CTRL, C(en=1)), W(CTRL, C(en=0)), False, 4))

D("D06_RESTART_WHILE_STOPPED", "CMD.RESTART with EN=0 reloads but stays stopped; later start reloads newer SHADOW (R-TMR-9, R-TMR-7)",
  W(LOAD, 4) + W(CMD, 1) + I(3) + W(LOAD, 6) + W(CTRL, C(en=1)) + I(5))

D("D07_RESTART_AT_PERIODIC_EXP", "RESTART coincident with periodic expiration after SHADOW rewrite (R-TMR-9, R-PRI-3)",
  align(W(LOAD, 2) + W(CTRL, C(en=1, ie=1)) + W(LOAD, 7), W(CMD, 1), True, 5))

p = W(LOAD, 0) + W(CTRL, C(en=1, mode=1, ie=0)) + I(2) + W(CTRL, C(mode=1, ie=1)) + I(2)
p += W(LOAD, 1) + W(CTRL, C(en=1, ie=1))
D("D08_IE_TOGGLE", "Expiration with IE=0 then IE=1 (sticky PEND); IE=0 written at an expiration (R-INT-6/7, R-TMR-12)",
  align(p, W(CTRL, C(en=1, ie=0)), True, 4))

D("D09_BACK_TO_BACK_ACCESS", "Consecutive access cycles without setup: W LOAD, R LOAD, W CMD (R-APB-1)  [non-standard APB]",
  W(LOAD, 4) + W(CTRL, C(en=1, psc=3)) + I(2) + [acc(LOAD, 9), acc(LOAD, 0, 0), acc(CMD, 1)] + I(4))

D("D10_ERRORED_ACCESS_AT_EXP", "Write to RO COUNT coincident with expiration; unmapped write and read (R-APB-8/9)",
  align(W(LOAD, 2) + W(CTRL, C(en=1)), W(COUNT, 0x55), True, 1) + W(0x40, 1) + R(0x40) + I(2))

D("D11_LOAD0_PSC3", "LOAD=0 with PSC=3: one-shot completes on first tick; periodic expires every 4 cycles (R-TMR-4/5)",
  W(LOAD, 0) + W(CTRL, C(en=1, mode=1, psc=3)) + I(8) + W(CTRL, C(en=1, psc=3)) + I(10))

rst_wr = [dict(IDLE, rst=0, psel=1, pen=1, pwr=1, addr=LOAD, wdata=0x77, lbl="reset during W LOAD access")]
D("D12_RESET_DURING_ACCESS", "Async reset asserted during a write access cycle with irq=1; write lost (R-RST-1/2/3)",
  W(LOAD, 3) + W(CTRL, C(en=1, ie=1)) + I(5) + [dict(IDLE, psel=1, pwr=1, addr=LOAD, wdata=0x77, lbl="setup")] +
  rst_wr + RST(1) + I(2) + R(LOAD) + R(STATUS))

D("D13_PSC_255", "PSC=255: tick every 256 enabled cycles, PSCNT readback near 255 (R-TMR-1)",
  W(LOAD, 1) + W(CTRL, C(en=1, psc=255)) + I(250) + R(PSCNT) + I(260) + R(PSCNT) + I(10))

D("D14_RESERVED_AND_ALIASES", "Reserved CTRL bits read 0; CMD read is 0 without error; PADDR[1:0] aliases (R-APB-4/5/6)",
  W(CTRL, 0xFFFFFFF8) + R(CTRL) + R(0x13) + W(0x05, 0x1234) + R(0x06) + R(0x0E) + W(0x11, 0) + I(2))

noise = [dict(IDLE, psel=0, pen=1, pwr=1, addr=CTRL, wdata=0, lbl="PENABLE without PSEL"),
         dict(IDLE, psel=1, pen=0, pwr=1, addr=CMD, wdata=1, lbl="setup only, CMD"),
         dict(IDLE, psel=0, pen=0, pwr=1, addr=LOAD, wdata=0xFFFF, lbl="idle with write data"),
         dict(IDLE, psel=0, pen=1, pwr=0, addr=COUNT, wdata=0, lbl="PENABLE without PSEL read")]
D("D15_BUS_NOISE", "Non-access bus activity has no effect; PRDATA=0, PSLVERR=0 (R-APB-2/7/8)",
  W(LOAD, 5) + W(CTRL, C(en=1, psc=1)) + noise + noise + I(2))

D("D16_SHADOW_FFFF", "SHADOW=0xFFFF: COUNT runs down from 65535 (R-TMR-3 boundary)",
  W(LOAD, 0xFFFF) + W(CTRL, C(en=1)) + I(3) + R(COUNT) + R(ACTIVE) + I(2))

D("D17_PSC_RAISE_MIDINTERVAL", "Raising PSC mid-interval (PCNT=2 of PSC=3 -> PSC=6) extends the interval; PCNT not cleared (R-TMR-12/13)",
  find(W(LOAD, 2) + W(CTRL, C(en=1, psc=3)), W(CTRL, C(en=1, psc=6)), lambda st, t, e: st['PCNT'] == 2, post=16))

D("D18_START_KEEPS_FLAGS", "Stop then start: PEND/OVF preserved across a start (R-TMR-7)",
  W(LOAD, 0) + W(CTRL, C(en=1, ie=1)) + I(3) + W(CTRL, C(en=0, ie=1)) + W(CTRL, C(en=1, ie=1)) + I(1) + R(STATUS) + I(1))

# ---------------------------------------------------------------- seeded random smoke (small)
rng = random.Random(20261015)
ADDRS = [0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18]
def rnd_word(a):
    if a == CTRL:
        return rng.choice([0, 1, 3, 5, 7]) | (rng.choice([0, 0, 0, 1, 2, 3, 255]) << 8)
    if a == LOAD:
        return rng.choice([0, 1, 2, 3, 4, 5, rng.getrandbits(16)])
    return rng.choice([0, 1, 2, 3])
for n in range(40):
    seq = []
    for _ in range(rng.randint(60, 120)):
        r = rng.random()
        if r < 0.30:
            seq += I(rng.randint(1, 4))
        elif r < 0.93:
            a = rng.choice(ADDRS) if rng.random() < 0.93 else rng.choice([0x1C, 0x40, 0xFC])
            seq += (W(a, rnd_word(a)) if rng.random() < 0.65 else R(a))
        else:
            a = rng.choice(ADDRS)
            seq.append(acc(a, rnd_word(a), rng.getrandbits(1), "raw back-to-back"))
    TESTS.append((f"RND{n:02d}", "Seeded random smoke (seed 20261015), legal APB plus occasional back-to-back access", seq))

# ---------------------------------------------------------------- write files
def main():
    out = os.path.join(HERE, "..", "vectors")
    os.makedirs(out, exist_ok=True)
    total = 0
    with open(os.path.join(out, "all.vec"), "w") as fv, open(os.path.join(out, "tests.idx"), "w") as fi:
        fi.write("# tid name cycles description\n")
        for tid, (name, desc, seq) in enumerate(TESTS):
            full = RST(1) + seq                      # every test starts from a reset cycle
            rows, _ = run(full)
            for (i, s, rd, err, irq, tick, exp) in rows:
                fv.write(f"{tid:x} {i['rst']:x} {i['psel']:x} {i['pen']:x} {i['pwr']:x} {i['addr']:x} {i['wdata']:x} "
                         f"{rd:x} {err:x} 1 {irq:x} {s['EN']:x} {s['MODE']:x} {s['IE']:x} {s['PSC']:x} {s['SHD']:x} "
                         f"{s['ACT']:x} {s['CNT']:x} {s['PCNT']:x} {s['PEND']:x} {s['OVF']:x}\n")
            fi.write(f"{tid} {name} {len(rows)} {desc}\n")
            total += len(rows)
    print(f"tests={len(TESTS)} cycles={total} -> vectors/all.vec, vectors/tests.idx")

if __name__ == "__main__":
    main()
