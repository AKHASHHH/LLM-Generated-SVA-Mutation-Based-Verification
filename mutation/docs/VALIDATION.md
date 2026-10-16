# Final validation of the Project 4 v2 results

Everything here is testbench- or script-side. The six generated files and the first-run `results/` are never written.

## 1. Claude SVA failures at time 0 (`APB3_pready`, `APB8_pslverr_nonacc`)

**Hypothesis.**
1. The first-run TB declares `logic PCLK = 1'b0;`. VCS evidently treats this 4-state declaration initializer as a time-0 assignment, so `PCLK` makes an X→0 transition at 0 ps.
2. An X→0 transition is a `negedge`, and that `negedge` is a clocking event for sva_claude_1's output checks, which are clocked by `` `OCLK = @(posedge PCLK or negedge PCLK) disable iff (1'b0) ``.
3. Those checks are deliberately not reset-gated, so they evaluate at 0 ps on values sampled before time-0 initialization had settled. `PREADY` and `PSLVERR` were not yet driven at that instant.
4. sva_gpt_1 is unaffected: its output checks are deferred (`assert final`, evaluated after settling), and its concurrent properties use `posedge PCLK` with `disable iff (!PRESETn)`.

The original TB comment ("no clock event at time 0") assumed the declaration initializer produces no event. For VCS that assumption was wrong.

**Experiment (phase A).** The two variants differ only in the `PCLK` declaration. TB, vectors, DUT (reference) and SVA files are all identical.

| Variant | `PCLK` declaration | Expectation if the hypothesis holds |
|---|---|---|
| A0 `t0_logic` | `logic PCLK = 1'b0;` (first run) | the 2 failures at 0 ps reappear; `TBDIAG clock event at time 0 …` is printed with the sampled values |
| A1 `t0_bit` | `bit PCLK = 1'b0;` (`+define+CLK2STATE`) | 0 failures at 0 ps; no `TBDIAG clock event` line |

`+define+DIAG_T0` adds a TB `cover property` on exactly the same clocking event as Claude's output checks. Its action block prints the `$sampled()` values of `PREADY`, `PSLVERR`, `PSEL`, `PENABLE`, `PRDATA`, `PRESETn` and `irq` whenever that event occurs in the first 1 ns. This shows directly what the two assertions saw.

**Interpretation.**
* **A0 reproduces the failures and A1 removes them:** the cause is the testbench clock initialization, not the reference and not a spec violation. The spec defines behavior per cycle, and no cycle exists before the first rising edge. Report it as "2 time-0 failures, root-caused to TB clock initialization; 0 after the TB-only fix".
* **Design observation, worth stating in the write-up:** Claude's ungated both-edge output checks are what make the SVA sensitive to this. It is not a spec violation, but it is a robustness weakness.
* **If A1 still fails at 0 ps:** the hypothesis is wrong. Send me `results_validation/time0_experiment.txt`.

## 2. M10 timestamp: GPT failure at 185 ns vs scoreboard at 192 ns

**Time base** (10 ns clock):
* Rising edges at 5, 15, 25 … ns.
* Vector row *k* is applied at the falling edge 10(k+1) ns.
* The scoreboard checks row *k* at 10(k+1)+2 ns.
* Row *k*'s state is held over the cycle [10k+5, 10k+15) ns.

**EX02 window** (spec-model values):

| Row | State held | Event |
|---|---|---|
| 17 | 175–185 ns | COUNT=0, tick → **expiration**, consumed at the 185 ns rising edge |
| 18 | 185–195 ns | PEND=1, IE=1. Spec: `irq = PEND & IE = 1` from 185 ns |

**What happens:**
* **185 ns, rising edge.** The reference sets PEND=1 and its combinational `irq` rises immediately. M10's registered `irq_q` samples the old `PEND & IE = 0` at that same edge, so it stays 0 until 195 ns. The DUT/reference divergence therefore exists from 185 ns.
* **185 ns, end of time step.** `R_INT_6_IRQ` is an `assert final` inside `always_comb`. It re-evaluates after PEND changes, in the postponed region of the 185 ns time step, sees `irq=0 ≠ PEND&IE=1`, and fails at **185 ns**.
* **192 ns.** The scoreboard samples once per cycle, at falling edge + 2 ns, and reports row 18 there.

Both refer to **cycle 18**. The 7 ns gap is sampling phase within the same cycle, not early detection.

For comparison: a concurrent check of irq clocked on both edges, like Claude's `INT6_irq`, samples in the preponed region and would fail at 190 ns. That is still cycle 18.

**Fix to the metric.** The first-run matrix computed latency as a raw ns difference ÷ 10, which gives −0.7 here. The validating `make_matrix.py` instead converts every failure to the cycle whose values it judged:
* concurrent assertion at time T → cycle containing T−ε;
* immediate/deferred assertion at T → cycle containing T.

It then compares that with the scoreboard's first diverging cycle. Here, 18 − 18 = latency 0.

Phase D prints a `TBTRACE` log of `irq`, `pend`, `ovf` and `count` for DUT and reference between 170 and 215 ns. This is text evidence of the sequence above.

## 3. Are all 20 detections genuine?

A cell is DETECTED only if the mutant run contains an SVA failure (label, time) that is absent from the reference run with identical vectors. This already removes Claude's time-0 failures.

Phase B/C adds, for every detection:
* **(a) Timing.** The cycle of the first new failure must be ≥ the first divergence cycle.
* **(b) Location.** Every new failure must lie in a diverging cycle or the cycle after one. This uses the per-cycle divergence file (`.div`) written by the scoreboard. Phase B only, because first-run logs have no `.div`.
* **(c) Consistency.** The SVA run's divergence (count and first cycle) must equal the no-SVA activation run's.

**Verdict:** VALID or SUSPECT (with reasons), in `matrix.md` §5.

**Manual sanity check** (one line per cell, for the write-up): the first failing label should concern the state element or output each mutant corrupts.

| Mutant | First corrupted |
|---|---|
| M01 | PEND, irq |
| M02 | OVF |
| M03 | COUNT, ACTIVE |
| M04 | EN |
| M05 | COUNT, ACTIVE, PCNT |
| M06 | PCNT |
| M07 | PCNT, COUNT |
| M08 | COUNT, ACTIVE, PCNT |
| M09 | PEND, irq |
| M10 | irq |

## 4. Two Verdi captures

Use the phase-B builds (2-state clock). The first failing label for each build is in `results_clk2state/matrix.md`.

**Capture 1: simultaneous-event priority violation (M01_PEND_CLEAR_BEATS_SET, spec Example 7, R-PRI-4).**
* Window **825–870 ns**; cursor at **845 ns**.
* **Setup:** row 82 (830–840 ns) is the STATUS-write setup. In row 83 (state 835–845 ns: COUNT=0 expiring, PEND=1), `PSEL=PENABLE=PWRITE=1`, `PADDR=0x0C`, `PWDATA=1` from 840 ns.
* **At the 845 ns edge:**
  * Reference: PEND stays 1 (hardware set beats software clear), OVF→1, irq stays 1.
  * M01: PEND→0, OVF→1, irq→0.
* **Signals:** `PCLK PSEL PENABLE PWRITE PADDR PWDATA`, `ref_i.count ref_i.pend ref_i.ovf r_irq`, `d_count d_pend d_ovf irq`, and the failing `u_sva` assertion.
* Scoreboard first divergence: row 84 (852 ns).

**Capture 2: registered-interrupt timing violation (M10_IRQ_REGISTERED, spec Example 2, R-INT-6).**
* Window **170–205 ns**; cursor at **185 ns**.
* **At the 185 ns edge:** PEND→1, IE=1. The reference `irq` rises at 185 ns; M10's `irq` rises at 195 ns, one cycle late.
* GPT `R_INT_6_IRQ` fails at 185 ns; the scoreboard reports at 192 ns. Same cycle 18.
* **Signals:** `PCLK`, `d_pend d_ie irq`, `ref_i.pend r_irq`, `dut.irq_q`, and the `u_sva` assertion.

## 5. Files changed (default behavior unchanged)

| File | Change |
|---|---|
| `tb/tb_top.sv` | `+define+CLK2STATE` (2-state PCLK), `+define+DIAG_T0` (time-0 clock-event report), plusargs `+DIVFILE=` (per-cycle divergence list) and `+TRACE_FROM= +TRACE_TO=` (interrupt-path trace). With no defines or plusargs, the behavior is identical to the first run. |
| `scripts/common.sh` | `RES_DIR`, `BUILD_DIR`, `TB_DEFINES` overrides; every run writes `<log>.div` |
| `scripts/run_*.sh`, `waves.sh` | `$ROOT/build` → `$BUILD` (the default is unchanged) |
| `scripts/make_matrix.py` | cycle attribution, latency in cycles, detection validation (§5 of the output), `--out`, t=0 vs t>0 FP split |
| `scripts/run_validation.sh` | new: phases A–D |
