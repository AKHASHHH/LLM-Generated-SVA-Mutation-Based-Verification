# Experiment 2: black-box (port-only) LLM assertion checkers

**Question.** How does limited observability affect the effectiveness of independently generated LLM assertion checkers? Each checker sees only the 11 external ports of `apb_timer`. It runs on the same frozen spec, the same reference, the same 10 mutants and the same 8,348-cycle vector stream as Experiment 1.

Experiment 1 (white-box) is closed. Its files and results (`results/`, `results_clkstart1ns/`, `results_validation/`) are only read here.

## 1. Feasibility (2–4 focused hours)

Realistic, provided the harness is reused rather than rebuilt:
* `tb_top.sv` is used **byte-identical** (SHA-256 `a4b464c8…`). The checker attaches through a `bind`.
* `scripts/common.sh` `build`/`run` are reused through `RES_DIR`/`BUILD_DIR`.
* Port observability comes from the **already-audited** activation runs. No mutant is rerun without SVA.

| Step | Who | Time |
|---|---|---|
| Generate 2 checkers (fresh sessions), save, hash, record provenance | you | 0.5 h |
| Runner + matrix script (about 200 lines, reusing `make_matrix.py` functions) | me | before your first VCS run |
| Isolation gate + first-pass compile + baseline on the reference (4 VCS compiles) | you | 0.5 h |
| Adjudicate baseline failures (time-boxed; see risk 5) | you + me | 0.5–1 h |
| Detection: 2 checkers × 10 mutants (20 compiles) + matrix | you | 0.5–0.75 h |
| README section | you | 0.5 h |
| **Total** | | **2.5–3.75 h** |

The one thing that can blow the budget is a checker with many false positives on the reference. Section 5, risk 5, caps that work.

## 2. Interface contract

* **Module and ports.** The module is `apb_timer_bb_sva` with exactly the 11 inputs in `interface/apb_timer_bb_sva_header.sv`. It is a different module name from Experiment 1's `apb_timer_sva`, so the two can never be confused.
* **Connection.** `tb/bb_bind.sv` binds it into `tb_top`, connected to the DUT boundary: the TB-driven inputs and the **DUT's** outputs. It never sees the reference instance's outputs, the `a_*` probes, or any DUT-internal signal.
* **Checker-local state is allowed** (prompt rule 2), but only if it is computed from those 11 inputs: for example, a value written over APB or read back on PRDATA. A procedural model of counting or next-state behavior is prohibited. This mirrors Experiment 1's rule ("Do not build a procedural model of the timer's next state"). It keeps the comparison about assertions rather than about who writes the better shadow model.
* **Enforcement (a gate, run before any simulation):**
  1. Each generated file must **elaborate standalone** with VCS as the only top (`-top apb_timer_bb_sva`). Any reference outside the module (`tb_top.dut.pend`, `$root…`) cannot resolve and fails.
     * This gate is necessary: inside the bind, an upward reference to `tb_top.dut.*` would resolve silently.
     * Verified with slang on two harness fixtures: a port-only fixture passes; a fixture reading `tb_top.dut.pend` is rejected.
  2. A text scan for `bind`, `$root`, `tb_top`, `dut`, `ref_i`, `force`, `$fopen`, `import "DPI` is reported. A hit is investigated, not auto-failed.
* **Review, then record.** Each checker is reviewed against rule 2: does it compute predicted COUNT, PCNT or expiry? The finding is recorded, never fixed.

## 3. Generation protocol (prompt: `prompt/BB_PROMPT.txt`, SHA-256 `41f49add…`)

1. **Session setup.** Fresh session per model, outside this Project, with memory off. Same model family as in Experiment 1 if available; record the exact model name and version string shown.
2. **Input.** Paste `BB_PROMPT.txt` verbatim, followed by the frozen spec `APBTMR_SPEC_v1.0.md` verbatim (`1b14ffc0…`). Nothing else: no white-box SVA, no results, no mention of mutants or of the other model.
3. **Save.** One generation per model, first pass, no regeneration and no follow-up messages. Save the raw response. Extract only the code block, unchanged, to:
   * `gen/sva_bb_gpt_1.sv`
   * `gen/sva_bb_claude_1.sv`
4. **Record.** `sha256sum gen/*.sv > gen/bb_sha256.txt`. Fill in `gen/GEN_PROVENANCE.md`: model, version string, date, prompt hash, spec hash, raw-response file name.
5. **If a checker does not compile.** Same policy as Experiment 1: record COMPILE_FAIL on the original. A syntax-only correction may live only in `sva_corrected/sva_bb_<m>_1_corrected.sv`, with a diff and a stated reason. Results on a corrected file are labeled as such.

## 4. Runs and classification

**Builds.** All builds use `+define+CLK_START_1NS`; `tb_top.sv` and the vectors are unchanged.
* 2 isolation compiles;
* 2 baseline runs, each checker on the reference;
* 20 detection runs, each checker × M01–M10.

Results go to `blackbox/results/` and `blackbox/build/` only. The runner refuses to start if `blackbox/results/` exists.

**Run integrity.** Every log is checked exactly as in Experiment 1: TBSUMMARY reached, 8,348 cycles, reference = spec on every cycle, `TBCONFIG clock_startup=CLK_START_1NS`.

**Port observability, per mutant.** Read from `results_clkstart1ns/activation/*.log` (`ref_diverge_port_cycles`) and the per-cycle `.div` files (column 3 = port). Each detection run also re-checks it.

**Per mutant × checker:**

| Class | Condition | In kill rate |
|---|---|---|
| NOT_OBSERVABLE | Activated, 0 port-diverging cycles under the vectors | No. Never counted as missed. |
| DETECTED | Observable, and the first new failure (label, time absent from that checker's baseline) is attributable (see below) | Yes |
| MISSED | Observable, and no new failure | Yes |
| SUSPECT | Any attribution rule violated, **or any new failure on a NOT_OBSERVABLE mutant** | Adjudicate before reporting |
| COMPILE_FAIL / RUN_ERROR | As in Experiment 1 | Column excluded |

**Checker false positives:** that checker's failures on the reference, split into t ≤ 1 ns and t > 1 ns, by label.

**Attribution rules (black-box version).**
* **Why a sealed checker cannot fail early.** It sees exactly the baseline run's inputs until the DUT's **outputs** first differ from the reference's. A sealed checker therefore cannot produce a new failure before that point.
* **(a) Hard rule.** The first new failure's cycle must be at or after the first **port** divergence cycle. An earlier failure is SUSPECT, either because the checker leaks or because the difference fell in a known scoreboard blind spot. The blind spots are the 79 reset-row half cycles and the 2 tail cycles (`docs/ATTRIBUTION_AUDIT.md`), and they are checked against that list.
* **(b) First detection.** The first new failure must fall in a port-diverging cycle or the cycle after one, or be adjudicated as a blind-spot failure through the existing mechanism.
* **(c) Divergence.** The run's divergence must be identical to the audited activation run.
* **Later failures** outside port divergence are listed for review, not auto-SUSPECT. A black-box checker can legitimately carry an earlier wrong read in its history and fail on it later. The rule rests on the first detection.

**Latency** is reported twice, in cycles:
* from the first **port** divergence (what a black-box checker can see at the earliest);
* from the first divergence of any kind (to compare with Experiment 1).

## 5. Report (`blackbox/results/bb_matrix.md`)

* Integrity table.
* Baseline false positives per checker.
* Port observability per mutant.
* Per-mutant table: port cycles, first port-divergence cycle, BB-GPT, BB-Claude, WB-GPT, WB-Claude (from `results_validation/clkstart1ns_adjudicated/summary.json`), first-detection label/cycle/latency.
* Kill rates over OBSERVABLE mutants only.
* The audit gate.

**Expectation from the audited data** (to be confirmed by the runs, not assumed):
* M04 has 0 port-visible cycles, so it should be NOT_OBSERVABLE.
* M02 (1 port cycle) and M06 (2 port cycles) are observable only through one or two PRDATA reads. A black-box checker can only catch them if it checks those exact reads.

## 6. Methodological risks

1. **Observability depends on the vectors and on sampling.** "NOT_OBSERVABLE" means not observable under these vectors at the scoreboard's sampling points. It does not mean unobservable in principle. M04's state difference might reach the ports with other stimulus. State this wording in the README.
2. **Different prompts.** Experiment 1 and Experiment 2 do not compare like with like on prompt text: the interface and the bookkeeping rule differ. The comparison is "same model, same spec, two observability contracts" with n = 1 per model. No statistical or model-ranking claims.
3. **The line between "transaction history" and "procedural model" is a judgement call.** A checker may cross it anyway. Do not edit it; record the review finding and report results with that annotation.
4. **Isolation leaks.** These are covered by the standalone-elaboration gate and attribution rule (a). Rule (a) doubles as a leak detector: a sealed checker cannot fail before the first port difference.
5. **Baseline false positives** are likely to be higher than in white-box. A port-only checker must infer state, and history that is not cleared on reset produces spurious failures. Detection stays net of the baseline (label, time), which is conservative. Adjudication is time-boxed: classify each **distinct failing label** once, at its first failure, against the spec text, then report the remaining counts. A checker with baseline failures has its detections reported with that caveat, not hidden.
6. **Start-up.** Same `CLK_START_1NS` as Experiment 1. A failure at about 1 ns gets the time-0 check first.
7. **Model drift.** If the exact Experiment 1 model versions are no longer available, disclose the version used.
8. **Single generation per model.** One sample. Results describe these two files, not the models.
