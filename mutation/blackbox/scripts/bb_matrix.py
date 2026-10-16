#!/usr/bin/env python3
"""Experiment 2 (black-box checkers): baseline gate and audited mutation matrix.

Reads only: blackbox/results/ (Experiment 2 logs), results_clkstart1ns/activation/ (audited port observability),
results_validation/clkstart1ns_adjudicated/summary.json (or results_clkstart1ns/summary.json) for white-box
comparison, and vectors/. Writes only blackbox/results/{baseline/gate.*, bb_matrix.md, bb_matrix.csv, bb_summary.json}.

Failures are parsed from lines naming the bound instance u_bb (the white-box parser keys on u_sva and would
see nothing). Every log must contain the BBHOOK line (checker bound and alive).

Classes per mutant x checker (never merged):
  NOT_OBSERVABLE  activated, 0 port-diverging cycles at the scoreboard's sampling points (audited activation run).
                  Not in the kill rate. Any new failure on such a mutant is SUSPECT (needs port-level evidence).
  DETECTED        observable; first new failure (label, time absent from the checker's baseline) attributable:
                  (a) its cycle >= first PORT divergence cycle (a sealed port-only checker sees exactly the baseline
                      inputs until the DUT's outputs first differ), (b) it lies in a port-diverging cycle or the
                      cycle after one, (c) the run's divergence equals the audited activation run.
  MISSED          observable, no new failure.
  SUSPECT         any rule violated.
Later new failures outside port divergence are counted and listed for review (a port-only checker may carry an
earlier observed wrong value in its history); they do not change the verdict, which rests on the first detection.
Latency in cycles: from the first port divergence, and from the first divergence of any kind.

Usage: python3 blackbox/scripts/bb_matrix.py [--gate-only]
"""
import csv, json, math, os, re, sys
sys.dont_write_bytecode = True      # never write __pycache__ outside blackbox/ when importing make_matrix
BB = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
ROOT = os.path.normpath(os.path.join(BB, ".."))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
_argv = sys.argv; sys.argv = [sys.argv[0]]          # make_matrix reads argv at import; keep it neutral
import make_matrix as MM
sys.argv = _argv
MM.EXPECT = "CLK_START_1NS"
R = os.path.join(BB, "results")
WB = os.path.join(ROOT, "results_clkstart1ns")
CHK = ("gpt", "claude")
UNIT = MM.UNIT
FAIL_RE = re.compile(r"failed|Error", re.I)
PATH_RE = re.compile(r"\bu_bb((?:\.[A-Za-z_][\w$]*)+)")
STARTUP_NS = 5.0      # first rising edge with CLK_START_1NS; failures at or before it get the time-0 check first

def parse(path):
    lg = {"exists": os.path.exists(path), "summary": None, "config": None, "hook": False, "fails": set(),
          "test_starts": [], "compile_fail": False}
    if not lg["exists"]:
        return lg
    for line in open(path, errors="replace"):
        if line.startswith("COMPILE_FAIL"):
            lg["compile_fail"] = True
        if "BBHOOK" in line:
            lg["hook"] = True; continue
        m = MM.SUM_RE.search(line)
        if m:
            lg["summary"] = dict(kv.split("=", 1) for kv in m.group(1).split() if "=" in kv); continue
        m = MM.CONF_RE.search(line)
        if m:
            lg["config"] = m.group(1); continue
        m = MM.TEST_RE.search(line)
        if m:
            lg["test_starts"].append((float(m.group(2)) * UNIT.get(m.group(3) or "ns", 1.0), int(m.group(1)))); continue
        if "u_bb" in line and FAIL_RE.search(line) and not line.startswith(("TB", "BB")):
            pm, tm = PATH_RE.search(line), MM.TIME_RE.search(line)
            if pm:
                t = round(float(tm.group(1)) * UNIT[tm.group(2)], 3) if tm else None
                lg["fails"].add((pm.group(1).split(".")[-1], t))
    timed = {l for (l, t) in lg["fails"] if t is not None}
    lg["fails"] = {(l, t) for (l, t) in lg["fails"] if t is not None or l not in timed}
    return lg

def integrity(lg, ref_dut):
    p = MM.integrity(lg, ref_dut)
    if lg["exists"] and lg["summary"] and not lg["hook"]:
        p.append("no BBHOOK line (checker not shown bound)")
    return p

def div_sets(path):
    """(all diverging cycles, port-diverging cycles) from a .div file: cyc tid port state"""
    if not os.path.exists(path):
        return None, None
    a, p = set(), set()
    for l in open(path):
        f = l.split()
        if len(f) >= 4:
            a.add(int(f[0]))
            if f[2] == "1":
                p.add(int(f[0]))
    return a, p

def tsv(path, ncol):
    out = {}
    if os.path.exists(path):
        for l in open(path):
            f = l.rstrip("\n").split("\t")
            if len(f) >= ncol:
                out[f[0]] = f
    return out

def load_adjudication():
    """docs/BB_BASELINE_ADJUDICATION.tsv: checker<TAB>label<TAB>classification<TAB>reason (explains a baseline label)"""
    adj = {}
    p = os.path.join(BB, "docs", "BB_BASELINE_ADJUDICATION.tsv")
    if os.path.exists(p):
        for l in open(p):
            if l.strip() and not l.startswith("#"):
                f = l.rstrip("\n").split("\t")
                if len(f) >= 4 and f[3].strip():
                    adj[(f[0], f[1])] = (f[2], f[3])
    return adj

def baseline_gate():
    iso = tsv(os.path.join(R, "isolation", "status.tsv"), 2)
    comp = tsv(os.path.join(R, "compile", "status.tsv"), 2)
    adj = load_adjudication()
    rows, base, any_fail = [], {}, False
    for s in CHK:
        iv = iso.get(s, [s, "NOT_RUN"])[1]; cv = comp.get(s, [s, "NOT_RUN"])[1]
        lg = parse(os.path.join(R, "baseline", f"sva_bb_{s}.ref.log")); base[s] = lg
        prob = integrity(lg, True) if cv == "COMPILE_OK" else []
        labels = sorted({l for l, _ in lg["fails"]})
        unexpl = [l for l in labels if (s, l) not in adj]
        early = sorted(l for l, t in lg["fails"] if t is not None and t <= STARTUP_NS)
        if cv != "COMPILE_OK":
            g = "NOT_RUN"
        elif prob or unexpl:
            g = "FAIL"; any_fail = True
        else:
            g = "PASS"
        sm = lg["summary"] or {}
        rows.append((s, iv, cv, g, sm.get("cycles", "-"), sm.get("spec_mismatch_cycles", "-"), sm.get("ref_spec_mismatch_cycles", "-"),
                     len(lg["fails"]), labels, unexpl, early, prob))
    L = ["# Experiment 2 baseline gate (black-box checkers on the reference, CLK_START_1NS)", "",
         f"Expected per run: cycles = {MM.NCYC}; spec mismatches 0; reference = spec on every cycle; BBHOOK present; "
         "zero checker failures, or every failing label explained in docs/BB_BASELINE_ADJUDICATION.tsv.", "",
         "| Checker | Isolation | In-TB compile | Gate | Cycles | Spec mismatch | Ref vs spec | Failures | Failing labels | Unexplained | At start-up (<= 5 ns) | Integrity problems |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in rows:
        L.append(f"| sva_bb_{r[0]}_1 | {r[1]} | {r[2]} | **{r[3]}** | {r[4]} | {r[5]} | {r[6]} | {r[7]} | {', '.join(r[8]) or '-'} | "
                 f"{', '.join(r[9]) or '-'} | {', '.join(r[10]) or '-'} | {'; '.join(r[11]) or '-'} |")
    L += ["", f"**BASELINE GATE: {'FAIL (mutation runs refused)' if any_fail else 'PASS'}**"]
    os.makedirs(os.path.join(R, "baseline"), exist_ok=True)
    open(os.path.join(R, "baseline", "gate.md"), "w").write("\n".join(L) + "\n")
    with open(os.path.join(R, "baseline", "gate.tsv"), "w") as f:
        for r in rows:
            f.write(f"{r[0]}\t{r[3]}\n")
    return any_fail, rows, base, L

def cyc(t, imm, l):
    return None if t is None else MM.cycle_of(t, concurrent=(imm is None or l not in imm))

def main():
    any_fail, grows, base, GL = baseline_gate()
    if "--gate-only" in sys.argv:
        print("\n".join(GL)); sys.exit(1 if any_fail else 0)
    comp = tsv(os.path.join(R, "compile", "status.tsv"), 4)
    gate = {r[0]: r[3] for r in grows}
    imm = {s: MM.immediate_labels(comp[s][3]) if s in comp else None for s in CHK}
    # white-box comparison source
    wbp = os.path.join(ROOT, "results_validation", "clkstart1ns_adjudicated", "summary.json")
    if not os.path.exists(wbp):
        wbp = os.path.join(WB, "summary.json")
    wb = json.load(open(wbp)) if os.path.exists(wbp) else {"cells": {}}
    muts = MM.mutants()
    L = ["# Experiment 2: black-box (port-only) checker results", "",
         "Checkers: blackbox/gen/sva_bb_gpt_1.sv, sva_bb_claude_1.sv (original first-pass files, hashes in docs/BB_FROZEN_SHA256.txt).",
         f"Same TB (unchanged), reference, 10 mutants and {MM.NCYC}-cycle vectors as Experiment 1; CLK_START_1NS. "
         f"White-box comparison: `{os.path.relpath(wbp, ROOT) if os.path.exists(wbp) else 'not found'}`.", ""]
    # ---- 0. integrity
    runs = [(f"baseline/sva_bb_{s}.ref", os.path.join(R, "baseline", f"sva_bb_{s}.ref.log"), True) for s in CHK if gate.get(s) != "NOT_RUN"]
    runs += [(f"detection/sva_bb_{s}/{m}_{n}", os.path.join(R, "detection", f"sva_bb_{s}", f"{m}_{n}.log"), False)
             for s in CHK if gate.get(s) == "PASS" for m, n, _ in muts]
    L += ["## 0. Run integrity (checked, not assumed)", "", "| Run | Start-up | BBHOOK | Cycles | Spec mismatch | Ref vs spec | Divergence | Result |",
          "|---|---|---|---|---|---|---|---|"]
    bad_runs = 0
    for nm, path, refdut in runs:
        lg = parse(path); pr = ["COMPILE_FAIL"] if lg["compile_fail"] else integrity(lg, refdut); sm = lg["summary"] or {}
        bad_runs += bool(pr)
        L.append(f"| {nm} | {lg['config'] or 'n/r'} | {'yes' if lg['hook'] else 'NO'} | {sm.get('cycles', '-')} | {sm.get('spec_mismatch_cycles', '-')} | "
                 f"{sm.get('ref_spec_mismatch_cycles', 'n/r')} | {sm.get('ref_diverge_cycles', '-')} | {'OK' if not pr else 'FAIL: ' + '; '.join(pr)} |")
    # ---- 1. baseline
    L += ["", "## 1. Isolation, compilation and baseline (checker false positives)", ""] + GL[4:]
    # ---- 2. observability (audited activation runs)
    L += ["", "## 2. Port observability per mutant (audited white-box activation runs, scoreboard sampling points)", "",
          "| Mutant | Diverging cycles | Port-diverging cycles | First divergence (any) | First port divergence | Class |", "|---|---|---|---|---|---|"]
    obs = {}
    for m, n, req in muts:
        key = f"{m}_{n}"; lp = os.path.join(WB, "activation", f"{key}.log")
        sm = MM.parse_log(lp)["summary"]; a, p = div_sets(lp[:-4] + ".div")
        if not sm or p is None:
            obs[key] = None; L.append(f"| {key} | - | - | - | - | RUN_ERROR (audited activation log or .div missing) |"); continue
        npc = int(sm["ref_diverge_port_cycles"])
        obs[key] = {"div": int(sm["ref_diverge_cycles"]), "port": npc, "first_any": int(sm["first_diverge_cyc"]),
                    "first_port": min(p) if p else None, "all": a, "portset": p, "sm": sm}
        cls = "NOT_ACTIVATED" if not int(sm["ref_diverge_cycles"]) else ("OBSERVABLE" if npc else "NOT_OBSERVABLE")
        obs[key]["cls"] = cls
        L.append(f"| {key} | {sm['ref_diverge_cycles']} | {npc} | {sm['first_diverge_cyc']} | {min(p) if p else '-'} | {cls} |")
    # ---- 3. detection
    rows = [["mutant", "class", "checker", "outcome", "first_new_failure", "fail_ns", "fail_cycle", "first_port_div", "first_any_div",
             "latency_port", "latency_any", "new_failures", "later_outside_port_div", "verdict"]]
    tally = {s: {"DETECTED": 0, "MISSED": 0, "SUSPECT": 0, "NOT_OBSERVABLE": 0, "NO_FAIL": 0} for s in CHK}
    cells, L5, review = {}, [], []
    for m, n, req in muts:
        key = f"{m}_{n}"; o = obs.get(key)
        for s in CHK:
            if gate.get(s) != "PASS":
                cells[(key, s)] = gate.get(s, "NOT_RUN") if gate.get(s) != "FAIL" else "BLOCKED (baseline)"; continue
            if o is None:
                cells[(key, s)] = "RUN_ERROR (activation)"; continue
            lp = os.path.join(R, "detection", f"sva_bb_{s}", f"{key}.log"); lg = parse(lp)
            if lg["compile_fail"] or not lg["summary"] or integrity(lg, False):
                cells[(key, s)] = "RUN_ERROR"; rows.append([key, o["cls"], s, "RUN_ERROR"] + [""] * 10); continue
            new = sorted(((t if t is not None else 1e18), l) for (l, t) in (lg["fails"] - base[s]["fails"]))
            a, p = div_sets(lp[:-4] + ".div")
            same = (lg["summary"].get("ref_diverge_cycles") == o["sm"]["ref_diverge_cycles"] and
                    lg["summary"].get("ref_diverge_port_cycles") == o["sm"]["ref_diverge_port_cycles"] and
                    lg["summary"].get("first_diverge_cyc") == o["sm"]["first_diverge_cyc"] and p == o["portset"])
            if o["cls"] == "NOT_OBSERVABLE":
                if not new:
                    cells[(key, s)] = "NOT_OBSERVABLE"; tally[s]["NOT_OBSERVABLE"] += 1
                    rows.append([key, o["cls"], s, "NOT_OBSERVABLE"] + [""] * 9 + ["NOT_OBSERVABLE"]); continue
                t0, l0 = new[0]; c0 = cyc(t0, imm[s], l0)
                v = f"SUSPECT: {len(new)} new failures on a mutant with no scoreboard-visible port difference" + \
                    (" (first in a scoreboard blind spot)" if MM.blind_spot(c0) else "") + "; needs port-level evidence"
                tally[s]["NOT_OBSERVABLE"] += 1; tally[s]["NO_FAIL"] += 1
                cells[(key, s)] = f"NOT_OBSERVABLE but {len(new)} new failures: SUSPECT ({l0}, cycle {c0})"
                L5.append(f"| {key} | sva_bb_{s}_1 | {l0} | {t0:g} ns | {c0} | - | {o['first_any']} | - | - | {len(new)} | - | {'yes' if same else 'NO'} | {v} |")
                rows.append([key, o["cls"], s, "SUSPECT", l0, t0, c0, "", o["first_any"], "", "", len(new), "", v]); continue
            if not new:
                cells[(key, s)] = "MISSED"; tally[s]["MISSED"] += 1
                rows.append([key, o["cls"], s, "MISSED", "", "", "", o["first_port"], o["first_any"], "", "", 0, "", "MISSED"]); continue
            t0, l0 = new[0]; c0 = cyc(t0, imm[s], l0); fp, fa = o["first_port"], o["first_any"]
            prob = []
            if c0 is None or c0 < fp:
                prob.append("first failure before the first port divergence" + (" (blind spot)" if MM.blind_spot(c0) else ""))
            if c0 is not None and p is not None and c0 not in p and (c0 - 1) not in p:
                prob.append("first failure outside port-diverging cycles (+1)" + (" (blind spot)" if MM.blind_spot(c0) else ""))
            if not same:
                prob.append("divergence differs from the audited activation run")
            later = [(t, l) for (t, l) in new[1:] if p is not None and cyc(t, imm[s], l) is not None
                     and cyc(t, imm[s], l) not in p and (cyc(t, imm[s], l) - 1) not in p]
            for (t, l) in later:
                review.append(f"| {key} | sva_bb_{s}_1 | {l} | {t:g} ns | {cyc(t, imm[s], l)} | {'yes' if MM.blind_spot(cyc(t, imm[s], l)) else 'no'} |")
            v = "VALID" if not prob else "SUSPECT: " + "; ".join(prob)
            tally[s]["DETECTED"] += 1
            if prob:
                tally[s]["SUSPECT"] += 1
            lat_p = (c0 - fp) if c0 is not None else None; lat_a = (c0 - fa) if c0 is not None else None
            cells[(key, s)] = f"DETECTED: {l0} (cycle {c0})" + ("" if not prob else " SUSPECT")
            L5.append(f"| {key} | sva_bb_{s}_1 | {l0} | {t0:g} ns | {c0} | {fp} | {fa} | {lat_p} | {lat_a} | {len(new)} | {len(later)} | {'yes' if same else 'NO'} | {v} |")
            rows.append([key, o["cls"], s, "DETECTED", l0, t0, c0, fp, fa, lat_p, lat_a, len(new), len(later), v])
    L += ["", "## 3. Per-mutant results: black-box vs white-box", "",
          "| Mutant | Port cycles | BB GPT | BB Claude | WB GPT | WB Claude |", "|---|---|---|---|---|---|"]
    for m, n, req in muts:
        key = f"{m}_{n}"; o = obs.get(key) or {}
        def wbc(s):
            c = wb["cells"].get(f"{key}|{s}", {})
            return f"{c.get('outcome', '-')}" + (f": {c.get('first_new_failure')} (cycle {c.get('fail_cycle')})" if c.get("outcome") == "DETECTED" else "")
        L.append(f"| {key} | {o.get('port', '-')} | {cells.get((key, 'gpt'), '-')} | {cells.get((key, 'claude'), '-')} | {wbc('gpt')} | {wbc('claude')} |")
    L += ["", "## 4. Kill rate over port-observable mutants", "",
          "| Checker | Detected | of which SUSPECT | Missed | Not observable | of which with new failures (SUSPECT) | Kill rate (observable) | White-box kill rate |", "|---|---|---|---|---|---|---|---|"]
    for s in CHK:
        d, mi, x, no = tally[s]["DETECTED"], tally[s]["MISSED"], tally[s]["SUSPECT"], tally[s]["NOT_OBSERVABLE"]
        wd = sum(1 for k, c in wb["cells"].items() if k.endswith(f"|{s}") and c.get("outcome") == "DETECTED")
        wn = sum(1 for k, c in wb["cells"].items() if k.endswith(f"|{s}") and c.get("outcome") in ("DETECTED", "MISSED"))
        L.append(f"| sva_bb_{s}_1 | {d} | {x} | {mi} | {no} | {tally[s]['NO_FAIL']} | {('%d/%d' % (d, d + mi)) if d + mi else '-'} | {('%d/%d' % (wd, wn)) if wn else '-'} |")
    L += ["", "## 5. Detection attribution", "",
          "Cycle c = [10c+5, 10c+15) ns = vector row c. Latency in cycles from the first port divergence and from the first divergence of any kind.", "",
          "| Mutant | Checker | First new failure | Time | Fail cycle | First port div | First any div | Latency (port) | Latency (any) | New failures | Later, outside port div (+1) | Divergence = audited | Verdict |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|---|"] + L5
    if review:
        L += ["", "Later failures outside port-diverging cycles (+1), listed for review (do not change the verdict):", "",
              "| Mutant | Checker | Label | Time | Cycle | Scoreboard blind spot |", "|---|---|---|---|---|---|"] + review
    nobs = [k for k, o in obs.items() if o and o["cls"] == "NOT_OBSERVABLE"]
    runerr = sum(1 for c in cells.values() if str(c).startswith("RUN_ERROR"))
    susp = sum(tally[s]["SUSPECT"] + tally[s]["NO_FAIL"] for s in CHK)
    missed = [f"{r[0]} x sva_bb_{r[2]}_1" for r in rows[1:] if r[3] == "MISSED"]
    checks = [("Isolation PASS for both checkers", all(r[1] == "PASS" for r in grows), ", ".join(f"{r[0]}: {r[1]}" for r in grows)),
              ("Both checkers compiled in the TB", all(r[2] == "COMPILE_OK" for r in grows), ", ".join(f"{r[0]}: {r[2]}" for r in grows)),
              ("Baseline gate passed (zero or explained failures)", not any_fail, ", ".join(f"{r[0]}: {r[3]} ({r[7]} failures)" for r in grows)),
              (f"Every run complete and consistent ({len(runs)} logs)", bad_runs == 0, f"{bad_runs} failing"),
              ("Audited activation data present for all 10 mutants", all(obs.get(f'{m}_{n}') for m, n, _ in muts), ""),
              ("No RUN_ERROR cells", runerr == 0, str(runerr)),
              ("No SUSPECT cells", susp == 0, f"{susp} SUSPECT")]
    ok = all(c[1] for c in checks)
    L += ["", "## 6. Audit gate", "", "| Check | Result | Detail |", "|---|---|---|"] + [f"| {c} | {'PASS' if r else 'FAIL'} | {d} |" for c, r, d in checks]
    L += ["", f"Not observable under the existing vectors (not counted as missed): {', '.join(nobs) or 'none'}.",
          f"MISSED cells requiring adjudication: {', '.join(missed) or 'none'}.", "", f"**AUDIT: {'PASS' if ok else 'FAIL'}**"]
    open(os.path.join(R, "bb_matrix.md"), "w").write("\n".join(L) + "\n")
    with open(os.path.join(R, "bb_matrix.csv"), "w", newline="") as f:
        csv.writer(f).writerows(rows)
    json.dump({"cells": {f"{k}|{s}": v for (k, s), v in cells.items()}, "tally": tally, "audit": ok,
               "checks": [[c, r, d] for c, r, d in checks]}, open(os.path.join(R, "bb_summary.json"), "w"), indent=1, default=str)
    print("\n".join(L)); print("\nwrote blackbox/results/bb_matrix.md, bb_matrix.csv, bb_summary.json")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
