#!/usr/bin/env python3
"""STEP 6: build (and validate) the mutation-detection matrix from the VCS logs.

Outcome classes (kept strictly separate):
  COMPILE_FAIL    the SVA set did not compile (whole column)
  NOT_ACTIVATED   the mutant never diverged from the reference under the vectors (excluded from kill rate)
  RUN_ERROR       a detection log is missing or the simulation did not finish
  DETECTED        activated, and the SVA run on the mutant has >=1 failure (label, time) that does NOT
                  occur in the SVA run on the reference with the identical vectors
  MISSED          activated, and no such new failure

Detection validation (section 5 of the output). Each new failure is mapped to the CYCLE whose values it
judged, using one time base shared with the scoreboard:
  cycle c = the interval [10c+5, 10c+15) ns between rising edges; it equals vector row c, and the
            scoreboard checks row c at 10(c+1)+2 ns.
  concurrent assertion failing at time T  -> judged sampled (preponed) values  -> cycle containing T-epsilon
  immediate / deferred assertion at T     -> judged values after updates at T  -> cycle containing T
The kind of each assertion is read from the SVA source named in <RES>/compile/status.tsv.
A detection is VALID only if (a) the first new failure's cycle >= the first divergence cycle, (b) when the
per-cycle divergence file exists, every new failure lies in a diverging cycle or the cycle after one, and
(c) the SVA run diverged exactly as the no-SVA activation run did.
Run integrity (section 0) is CHECKED, not assumed: every log must reach TBSUMMARY with all vector rows
(cycles = number of lines in the vector file), the reference instance must match the spec model on every
cycle (ref_spec_mismatch_cycles=0), runs with the reference as DUT must have 0 spec mismatches and 0
divergence, and mutant runs must have spec mismatches == divergence (both measure the same DUT difference
when the reference equals the spec). With --expect-startup NAME every log must also report
TBCONFIG clock_startup=NAME. Section 6 is the audit gate; with --expect-startup the script exits 1 on FAIL.
Usage: python3 make_matrix.py [--fp-only] [--out DIR] [--expect-startup NAME]   (reads $RES_DIR)
"""
import csv, json, math, os, re, sys
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RES = os.environ.get("RES_DIR") or os.path.join(ROOT, "results")
OUT = sys.argv[sys.argv.index("--out") + 1] if "--out" in sys.argv else RES
UNIT = {"fs": 1e-6, "ps": 1e-3, "ns": 1.0, "us": 1e3, "ms": 1e6, "s": 1e9}
FAIL_HINT = re.compile(r"failed|Error|Assertion", re.I)
PATH_RE = re.compile(r"u_sva((?:\.[A-Za-z_][\w$]*)+)")
TIME_RE = re.compile(r"(?:failed at|at time|time)\s*[:=]?\s*(\d+(?:\.\d+)?)\s*(fs|ps|ns|us|ms|s)\b")
SUM_RE = re.compile(r"TBSUMMARY (.*)")
TEST_RE = re.compile(r"TBTEST tid=(\d+) time=(\d+(?:\.\d+)?)\s*(fs|ps|ns|us|ms|s)?")
CONF_RE = re.compile(r"TBCONFIG clock_startup=(\w+)")
EXPECT = sys.argv[sys.argv.index("--expect-startup") + 1] if "--expect-startup" in sys.argv else None
VECF = os.environ.get("VEC") or os.path.join(ROOT, "vectors", "all.vec")
NCYC = sum(1 for l in open(VECF) if l.strip())
IMMEDIATE_RE = re.compile(r"(\w+)\s*:\s*assert\s*(?:final\b|#\s*0|\()")

def load_tests():
    t = {}
    for l in open(os.path.join(ROOT, "vectors", "tests.idx")):
        if not l.startswith("#"):
            p = l.split(None, 3); t[int(p[0])] = p[1]
    return t
TESTS = load_tests()

def cycle_of(t_ns, concurrent):
    """vector row / clock cycle whose values an assertion failing at t_ns judged"""
    if t_ns is None:
        return None
    tt = t_ns - 1e-6 if concurrent else t_ns
    return math.floor((tt - 5.0) / 10.0)

def parse_log(path):
    out = {"summary": None, "fails": set(), "raw": [], "test_starts": [], "exists": os.path.exists(path), "diag": [],
           "config": None}
    if not out["exists"]:
        return out
    for line in open(path, errors="replace"):
        m = SUM_RE.search(line)
        if m:
            out["summary"] = dict(kv.split("=", 1) for kv in m.group(1).split() if "=" in kv); continue
        m = CONF_RE.search(line)
        if m:
            out["config"] = m.group(1); continue
        m = TEST_RE.search(line)
        if m:
            out["test_starts"].append((float(m.group(2)) * UNIT.get(m.group(3) or "ns", 1.0), int(m.group(1)))); continue
        if "TBDIAG" in line:
            out["diag"].append(line.rstrip()); continue
        if "u_sva" in line and FAIL_HINT.search(line) and "TBMSG" not in line:
            pm, tm = PATH_RE.search(line), TIME_RE.search(line)
            if pm:
                t = round(float(tm.group(1)) * UNIT[tm.group(2)], 3) if tm else None
                out["fails"].add((pm.group(1).split(".")[-1], t)); out["raw"].append(line.rstrip())
    timed = {l for (l, t) in out["fails"] if t is not None}
    out["fails"] = {(l, t) for (l, t) in out["fails"] if t is not None or l not in timed}
    return out

def integrity(lg, ref_dut):
    """problems with one run log; [] = complete and consistent"""
    if not lg["exists"]:
        return ["log missing"]
    sm = lg["summary"]
    if not sm:
        return ["no TBSUMMARY (did not finish)"]
    p = []
    if int(sm.get("cycles", -1)) != NCYC:
        p.append(f"cycles={sm.get('cycles')} (expected {NCYC})")
    rs = sm.get("ref_spec_mismatch_cycles")
    if rs is None:
        if EXPECT:
            p.append("ref_spec_mismatch_cycles not reported")
    elif rs != "0":
        p.append(f"reference != spec on {rs} cycles")
    if EXPECT and lg["config"] != EXPECT:
        p.append(f"clock_startup={lg['config']} (expected {EXPECT})")
    if ref_dut:
        if sm.get("spec_mismatch_cycles") != "0" or sm.get("ref_diverge_cycles") != "0":
            p.append("reference-as-DUT run has spec mismatches or divergence")
    elif sm.get("spec_mismatch_cycles") != sm.get("ref_diverge_cycles"):
        p.append(f"spec_mismatch_cycles={sm.get('spec_mismatch_cycles')} != ref_diverge_cycles={sm.get('ref_diverge_cycles')}")
    return p

def load_div(path):
    if not os.path.exists(path):
        return None
    return {int(l.split()[0]) for l in open(path) if l.strip()}

def test_at(log, t_ns):
    tid = None
    for (ts, i) in log["test_starts"]:
        if t_ns is not None and ts <= t_ns:
            tid = i
    return TESTS.get(tid, "?") if tid is not None else "before first vector"

def compile_status():
    st = {}
    p = os.path.join(RES, "compile", "status.tsv")
    if os.path.exists(p):
        for l in open(p):
            s, variant, status, rc, f = l.rstrip("\n").split("\t")
            st[s] = (variant, status, f)
    return st

def immediate_labels(sva_path):
    try:
        return set(IMMEDIATE_RE.findall(open(sva_path).read()))
    except OSError:
        return None

def mutants():
    rows = list(csv.DictReader(open(os.path.join(ROOT, "mutants", "mutants.tsv")), delimiter="\t"))
    return [(r["id"], r["name"], r["requirement"]) for r in rows]

def main():
    fp_only = "--fp-only" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    st = compile_status()
    kinds = {s: (immediate_labels(st[s][2]) if s in st else None) for s in ("gpt", "claude")}
    L = ["# Project 4 v2 - SVA mutation-detection results", "",
         f"Source logs: `{os.path.relpath(RES, ROOT)}/`. Mutants are CONTROLLED, intentional defects.", ""]
    # ---------------- 1. compile + false positives ----------------
    L += ["## 1. SVA compilation and false positives on the reference", "",
          "| SVA set | Variant | First-pass compile | Ref run finished | Spec mismatches | FP failures at t=0 | FP failures at t>0 | Labels at t>0 |",
          "|---|---|---|---|---|---|---|---|"]
    fp = {}
    J = {"res": os.path.relpath(RES, ROOT), "expect_startup": EXPECT, "fp": {}, "activation": {}, "cells": {}, "integrity": {}}
    for s in ("gpt", "claude"):
        variant, status, _ = st.get(s, ("?", "NOT_RUN", ""))
        lg = parse_log(os.path.join(RES, "fp", f"sva_{s}.ref.log")); fp[s] = lg
        fin = "yes" if lg["summary"] else ("no log" if not lg["exists"] else "NO")
        t0 = sorted(l for l, t in lg["fails"] if t == 0)
        late = [(l, t) for l, t in lg["fails"] if t not in (0, None)]
        J["fp"][s] = {"compile": status, "t0": t0, "late": sorted(late, key=lambda x: (x[1], x[0]))}
        L.append(f"| sva_{s}_1 | {variant} | {status} | {fin} | {lg['summary']['spec_mismatch_cycles'] if lg['summary'] else '-'} | "
                 f"{len(t0)}{(' (' + ', '.join(t0) + ')') if t0 else ''} | {len(late)} | {', '.join(sorted({l for l, _ in late})[:8]) or '-'} |")
        for d in lg["diag"]:
            print(f"[diag] sva_{s}: {d}")
        for r in lg["raw"][:3]:
            print(f"[parser] sva_{s} reference-run raw line: {r[:200]}")
    for t in ("rtl_gpt_1", "rtl_gpt_2", "rtl_claude_1", "rtl_claude_2"):
        for s in ("gpt", "claude"):
            p = os.path.join(RES, "fp", f"sva_{s}.{t}.log")
            if os.path.exists(p):
                lg = parse_log(p)
                L.append(f"| sva_{s}_1 on {t} | - | - | {'yes' if lg['summary'] else 'NO'} | "
                         f"{lg['summary']['spec_mismatch_cycles'] if lg['summary'] else '-'} | "
                         f"{len([1 for l, tt in lg['fails'] if tt == 0])} | {len([1 for l, tt in lg['fails'] if tt not in (0, None)])} | "
                         f"{', '.join(sorted({l for l, _ in lg['fails']})[:8]) or '-'} |")
    L.append("")
    if fp_only:
        open(os.path.join(OUT, "fp_summary.md"), "w").write("\n".join(L) + "\n"); print("\n".join(L)); return
    # ---------------- 2. activation ----------------
    L += ["## 2. Mutant activation (no SVA, differential vs reference)", "",
          "| Mutant | Violates | Activated | Diverging cycles | Port-visible cycles | First divergence (test, cycle) |",
          "|---|---|---|---|---|---|"]
    act = {}
    for mid, name, req in mutants():
        key = f"{mid}_{name}"
        sm = parse_log(os.path.join(RES, "activation", f"{key}.log"))["summary"]
        if not sm:
            act[key] = None; L.append(f"| {key} | {req} | RUN_ERROR | - | - | - |"); continue
        n = int(sm["ref_diverge_cycles"]); act[key] = (n > 0, sm)
        J["activation"][key] = {"diverge": n, "port": int(sm["ref_diverge_port_cycles"]), "first_cyc": int(sm["first_diverge_cyc"])}
        first = f"{TESTS.get(int(sm['first_diverge_tid']), '?')}, cyc {sm['first_diverge_cyc']}" if n else "-"
        L.append(f"| {key} | {req} | {'YES' if n else 'NO (NOT_ACTIVATED)'} | {n} | {sm['ref_diverge_port_cycles']} | {first} |")
    L.append("")
    # ---------------- 3 + 5. detection and its validation ----------------
    L3 = ["## 3. Detection matrix", "", "| Mutant | sva_gpt_1 | sva_claude_1 |", "|---|---|---|"]
    L5 = ["## 5. Detection validation", "",
          "Cycle c = [10c+5, 10c+15) ns = vector row c. Fail cycle = the cycle whose values the first new failure judged.", "",
          "| Mutant | SVA | First new failure | Kind | Fail time | Fail cycle | First divergence cycle | Latency (cycles) | New failures | Outside diverging cycles (+1) | Divergence identical to activation run | Verdict |",
          "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    rows = [["mutant", "requirement", "activated", "sva", "outcome", "first_new_failure", "kind", "fail_ns", "fail_cycle",
             "first_div_cycle", "latency_cycles", "new_failures", "outside_div", "verdict"]]
    tally = {s: {"DETECTED": 0, "MISSED": 0, "SUSPECT": 0} for s in ("gpt", "claude")}
    for mid, name, req in mutants():
        key = f"{mid}_{name}"; cells = []
        for s in ("gpt", "claude"):
            variant, status, _ = st.get(s, ("?", "NOT_RUN", ""))
            if status != "COMPILE_OK":
                cells.append(status); rows.append([key, req, "", s, status] + [""] * 9); continue
            if act.get(key) is None:
                cells.append("RUN_ERROR (activation)"); rows.append([key, req, "?", s, "RUN_ERROR"] + [""] * 9); continue
            activated, asum = act[key]
            if not activated:
                cells.append("NOT_ACTIVATED"); rows.append([key, req, "no", s, "NOT_ACTIVATED"] + [""] * 9); continue
            logp = os.path.join(RES, "detection", f"sva_{s}", f"{key}.log")
            lg = parse_log(logp)
            if not lg["summary"]:
                cells.append("RUN_ERROR"); rows.append([key, req, "yes", s, "RUN_ERROR"] + [""] * 9); continue
            new = sorted(((t if t is not None else 1e18), l) for (l, t) in (lg["fails"] - fp[s]["fails"]))
            if not new:
                cells.append("MISSED"); tally[s]["MISSED"] += 1
                rows.append([key, req, "yes", s, "MISSED", "", "", "", "", asum["first_diverge_cyc"], "", 0, "", "MISSED"]); continue
            imm = kinds[s]
            def cyc(l, t):
                if t is None or t >= 1e17:
                    return None
                return cycle_of(t, concurrent=(imm is not None and l not in imm))
            t0, l0 = new[0]
            kind = "?" if imm is None else ("immediate/deferred" if l0 in imm else "concurrent")
            c0 = cyc(l0, t0)
            fdc = int(lg["summary"]["first_diverge_cyc"])
            same = (lg["summary"].get("ref_diverge_cycles") == asum["ref_diverge_cycles"] and
                    lg["summary"].get("first_diverge_cyc") == asum["first_diverge_cyc"])
            div = load_div(logp[:-4] + ".div")
            if div is None:
                outside = "n/a (no .div)"
            else:
                outside = str(sum(1 for (t, l) in new if cyc(l, t) is not None
                                  and cyc(l, t) not in div and (cyc(l, t) - 1) not in div))
            lat = (c0 - fdc) if c0 is not None else None
            problems = []
            if lat is None or lat < 0:
                problems.append("fails before divergence")
            if outside not in ("0", "n/a (no .div)"):
                problems.append(f"{outside} failures outside divergence")
            if not same:
                problems.append("divergence differs from activation run")
            verdict = "VALID" if not problems else "SUSPECT: " + "; ".join(problems)
            tally[s]["DETECTED"] += 1
            if problems:
                tally[s]["SUSPECT"] += 1
            cells.append(f"DETECTED: {l0} (cycle {c0}, {test_at(lg, t0)})")
            L5.append(f"| {key} | sva_{s}_1 | {l0} | {kind} | {t0:g} ns | {c0} | {fdc} | {lat} | {len(new)} | {outside} | "
                      f"{'yes' if same else 'NO'} | {verdict} |")
            rows.append([key, req, "yes", s, "DETECTED", l0, kind, t0, c0, fdc, lat, len(new), outside, verdict])
        L3.append(f"| {key} | {cells[0]} | {cells[1]} |")
    L4 = ["", "## 4. Kill rate (activated mutants only)", "",
          "| SVA set | Detected | of which SUSPECT | Missed | Kill rate |", "|---|---|---|---|---|"]
    for s in ("gpt", "claude"):
        d, m, x = tally[s]["DETECTED"], tally[s]["MISSED"], tally[s]["SUSPECT"]
        L4.append(f"| sva_{s}_1 | {d} | {x} | {m} | {('%d/%d' % (d, d + m)) if d + m else '-'} |")
    L += L3 + L4 + [""] + L5 + ["", "Every MISSED or SUSPECT cell must be adjudicated before it is reported."]
    # ---------------- 0. run integrity (checked for every log) ----------------
    runs = [("ref_check/ref", os.path.join(RES, "ref_check", "ref.log"), True)]
    runs += [(f"fp/sva_{s}.ref", os.path.join(RES, "fp", f"sva_{s}.ref.log"), True)
             for s in ("gpt", "claude") if st.get(s, ("", "", ""))[1] == "COMPILE_OK"]
    for mid, name, req in mutants():
        key = f"{mid}_{name}"
        runs.append((f"activation/{key}", os.path.join(RES, "activation", f"{key}.log"), False))
        runs += [(f"detection/sva_{s}/{key}", os.path.join(RES, "detection", f"sva_{s}", f"{key}.log"), False)
                 for s in ("gpt", "claude") if st.get(s, ("", "", ""))[1] == "COMPILE_OK"]
    L0 = ["## 0. Run integrity (checked, not assumed)", "",
          f"Expected per run: cycles = {NCYC}; reference instance = spec model on every cycle; "
          f"clock start-up = {EXPECT or 'not enforced (first-run logs predate TBCONFIG)'}.", "",
          "| Run | Start-up | Cycles | Spec mismatch | Ref vs spec | Divergence | Result |", "|---|---|---|---|---|---|---|"]
    bad_runs = 0
    for nm, path, refdut in runs:
        lg = parse_log(path); pr = integrity(lg, refdut); sm = lg["summary"] or {}
        bad_runs += bool(pr); J["integrity"][nm] = pr
        L0.append(f"| {nm} | {lg['config'] or 'n/r'} | {sm.get('cycles', '-')} | {sm.get('spec_mismatch_cycles', '-')} | "
                  f"{sm.get('ref_spec_mismatch_cycles', 'n/r')} | {sm.get('ref_diverge_cycles', '-')} | {'OK' if not pr else 'FAIL: ' + '; '.join(pr)} |")
    L = L[:4] + L0 + [""] + L[4:]
    # ---------------- 6. audit gate ----------------
    n_act = sum(1 for v in act.values() if v and v[0])
    base = {s: len(fp[s]["fails"]) for s in ("gpt", "claude")}
    cols_ok = all(st.get(s, ("", "", ""))[1] == "COMPILE_OK" for s in ("gpt", "claude"))
    runerr = sum(1 for r in rows[1:] if r[4] == "RUN_ERROR")
    susp = sum(tally[s]["SUSPECT"] for s in ("gpt", "claude"))
    missed = [f"{r[0]} x sva_{r[3]}_1" for r in rows[1:] if r[4] == "MISSED"]
    checks = [("Both original SVA sets compiled", cols_ok, ""),
              (f"Every run complete and consistent ({len(runs)} logs)", bad_runs == 0, f"{bad_runs} failing"),
              (f"All {len(act)} mutants activated", n_act == len(act) and len(act) == 10, f"{n_act}/{len(act)}"),
              ("Zero baseline SVA failures on the reference", all(v == 0 for v in base.values()),
               ", ".join(f"sva_{s}_1: {base[s]}" for s in base)),
              ("No RUN_ERROR cells", runerr == 0, f"{runerr}"),
              ("Every detection causally attributable (no SUSPECT)", susp == 0, f"{susp} SUSPECT")]
    ok = all(c[1] for c in checks)
    L += ["", "## 6. Audit gate", "", "| Check | Result | Detail |", "|---|---|---|"]
    L += [f"| {c} | {'PASS' if r else 'FAIL'} | {d} |" for c, r, d in checks]
    L += ["", f"**AUDIT: {'PASS' if ok else 'FAIL'}**" + (f"  (MISSED cells needing adjudication: {', '.join(missed)})" if missed else "")]
    J["cells"] = {f"{r[0]}|{r[3]}": dict(zip(rows[0], r)) for r in rows[1:]}
    J["audit"] = {"pass": ok, "checks": [[c, r, d] for c, r, d in checks], "missed": missed}
    json.dump(J, open(os.path.join(OUT, "summary.json"), "w"), indent=1, default=str)
    open(os.path.join(OUT, "matrix.md"), "w").write("\n".join(L) + "\n")
    with open(os.path.join(OUT, "matrix.csv"), "w", newline="") as f:
        csv.writer(f).writerows(rows)
    print("\n".join(L)); print(f"\nwrote {os.path.relpath(OUT, ROOT)}/matrix.md, matrix.csv, summary.json")
    if EXPECT and not ok:
        sys.exit(1)

if __name__ == "__main__":
    main()
