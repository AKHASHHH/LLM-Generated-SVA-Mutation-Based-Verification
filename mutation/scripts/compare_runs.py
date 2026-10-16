#!/usr/bin/env python3
"""Report the differences between the first run and the corrected (CLK_START_1NS) run.
Reads only the summary.json files written by make_matrix.py; changes nothing.
Usage: python3 compare_runs.py FIRST_DIR CORRECTED_DIR OUT.md
"""
import json, os, sys

a_dir, b_dir, out = sys.argv[1:4]
A = json.load(open(os.path.join(a_dir, "summary.json")))
B = json.load(open(os.path.join(b_dir, "summary.json")))
L = ["# First run vs corrected run (CLK_START_1NS)", "",
     f"First run: `{A['res']}/` (re-analysed read-only). Corrected run: `{B['res']}/`.",
     "Same TB vectors, reference, mutants and original SVA files. Only the clock start-up differs, plus the",
     "TB's added reference-vs-spec counter, which does not affect stimulus or DUT.", ""]

L += ["## 1. Baseline (SVA on the reference)", "", "| SVA set | Run | Failures at t=0 | Failures at t>0 |", "|---|---|---|---|"]
for s in ("gpt", "claude"):
    for tag, J in (("first", A), ("corrected", B)):
        f = J["fp"].get(s, {})
        late = f.get("late", [])
        L.append(f"| sva_{s}_1 | {tag} | {len(f.get('t0', []))} {('(' + ', '.join(f['t0']) + ')') if f.get('t0') else ''} | "
                 f"{len(late)} {('(' + ', '.join(sorted({x[0] for x in late})) + ')') if late else ''} |")

L += ["", "## 2. Activation (no SVA)", "", "| Mutant | Diverging cycles first / corrected | First divergence cycle first / corrected | Same |",
      "|---|---|---|---|"]
for k in sorted(set(A["activation"]) | set(B["activation"])):
    x, y = A["activation"].get(k), B["activation"].get(k)
    same = x is not None and y is not None and x == y
    L.append(f"| {k} | {x and x['diverge']} / {y and y['diverge']} | {x and x['first_cyc']} / {y and y['first_cyc']} | {'yes' if same else 'NO'} |")

L += ["", "## 3. Detection cells", "",
      "| Mutant | SVA | Outcome first / corrected | First new failure first / corrected | Fail cycle first / corrected | Latency (cycles) first / corrected | Verdict first / corrected | Changed |",
      "|---|---|---|---|---|---|---|---|"]
nchg = 0
for k in sorted(set(A["cells"]) | set(B["cells"])):
    x, y = A["cells"].get(k, {}), B["cells"].get(k, {})
    fields = ("outcome", "first_new_failure", "fail_cycle", "latency_cycles", "verdict")
    chg = any(str(x.get(f)) != str(y.get(f)) for f in fields)
    nchg += chg
    m, s = k.split("|")
    L.append(f"| {m} | sva_{s}_1 | " + " | ".join(f"{x.get(f, '-')} / {y.get(f, '-')}" for f in fields) + f" | {'YES' if chg else ''} |")
L += ["", f"Changed cells: {nchg}. Expected changes: none in outcome or first label (time-0 failures were already",
      "subtracted in the first run), and verdict notes may change only because the corrected run has per-cycle .div files.",
      "Any other change must be explained before reporting.", "",
      f"Corrected-run audit: **{'PASS' if B.get('audit', {}).get('pass') else 'FAIL'}**"]
open(out, "w").write("\n".join(L) + "\n")
print("\n".join(L))
