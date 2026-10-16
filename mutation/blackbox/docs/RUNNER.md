# Experiment 2 runner

Everything runs from `mutation/` and writes only to:
* `blackbox/results/`: logs, `.div` files, gate, matrix;
* `blackbox/build/`: VCS builds.

The white-box TB, reference, mutants, vectors and every Experiment 1 result are only read.

## Phases (`./blackbox/scripts/run_bb.sh [iso|base|det|matrix]`, default all four)

Every phase first verifies two sets of hashes:
* the six white-box originals;
* the four Experiment 2 files (`docs/BB_FROZEN_SHA256.txt`, plus your `gen/bb_sha256.txt`).

Each phase refuses to overwrite its own results folder.

| Phase | What it does | Output |
|---|---|---|
| `iso` | Per checker: (1) comment-stripped scan for dotted (hierarchical) names, `$root`, `tb_top`, `dut`, `ref_i`, bind, force/release, file I/O, DPI, `` `include ``; (2) VCS elaboration with the checker as the **only** top. PASS needs both. | `results/isolation/status.tsv`, `*.scan.txt`, `*.standalone_compile.log` |
| `base` | In-TB compile with the reference DUT. A checker that compiles in the TB but not standalone is marked ISOLATION_FAIL (its references resolve only through the hierarchy). Then the baseline run. Then the **baseline gate**: every log complete (8,348 cycles, 0 spec mismatches, reference = spec, `CLK_START_1NS`, BBHOOK present), and zero checker failures, or every failing label explained in `docs/BB_BASELINE_ADJUDICATION.tsv`. **On FAIL the script stops; no mutation run happens.** | `results/compile/`, `results/baseline/*.log`, `gate.md`, `gate.tsv` |
| `det` | Re-checks the gate, then runs each PASS checker × the 10 mutants (20 builds) | `results/detection/sva_bb_<m>/*.log` + `.div` |
| `matrix` | Audited matrix (see below) | `results/bb_matrix.md`, `.csv`, `bb_summary.json` |

## Matrix sections

* **0. Run integrity.** Every log: start-up, BBHOOK, cycles, spec mismatches, reference vs spec, divergence.
* **1. Isolation, compile and baseline.** Includes checker false positives by label, and those at start-up (≤ 5 ns).
* **2. Port observability per mutant.** Taken from the **audited** white-box activation runs (`results_clkstart1ns/activation/`). A mutant with 0 port-diverging cycles at the scoreboard's sampling points is NOT_OBSERVABLE (M04 in the audited data).
* **3. Per mutant.** Black-box GPT and Claude next to the white-box GPT and Claude results. The white-box source is `results_validation/clkstart1ns_adjudicated/summary.json`, falling back to `results_clkstart1ns/summary.json`.
* **4. Kill rate over port-observable mutants only,** next to the white-box kill rate.
* **5. Attribution for each first detection.** Columns: label, time, fail cycle, first port divergence, first divergence of any kind, latency in cycles from both, and whether the divergence is identical to the audited run. Later failures outside port-diverging cycles are listed for review.
* **6. Audit gate.** Checks:
  * isolation;
  * compile;
  * baseline gate;
  * integrity;
  * audited activation data present;
  * no RUN_ERROR;
  * no SUSPECT (including any new failure on a NOT_OBSERVABLE mutant).

**SUSPECT rules for a first detection:**
* **(a)** It comes before the first port divergence. A sealed port-only checker sees exactly the baseline inputs until the DUT's outputs differ.
* **(b)** It falls outside a port-diverging cycle or the cycle after one.
* **(c)** The run's divergence differs from the audited activation run.

Blind-spot cycles (reset half cycles, tail) are tagged in the verdict, never excused automatically.

**M04 and any other NOT_OBSERVABLE mutant.** Never counted as missed. A new failure on one makes the cell SUSPECT until actual port-level evidence is shown. A Verdi or TBTRACE window at the failing time would be enough.

## If VCS rejects the second top module

The default hook compiles `-top tb_top -top bb_bind`. If your VCS refuses a second `-top`, use the equivalent single-top hook (`tb/bb_bind_unit.sv`, with the bind at compilation-unit scope):

```
setenv BB_BIND_MODE unit
```

Then move `blackbox/results` aside and rerun.

## If a log clearly shows checker failures but the matrix reports 0

The parser keys on the instance path `u_bb` plus `failed` or `Error`. Send two of those lines.
