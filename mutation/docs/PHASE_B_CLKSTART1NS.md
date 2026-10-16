# Phase B: corrected-start-up mutation campaign (CLK_START_1NS)

## Why this start-up

The time-0 experiment (`docs/TIME0_EXPERIMENT.md`, evidence in `results_validation/time0_v2/`) showed:
* the two sva_claude_1 failures at 0 ps come from an edge on the SVA's own `PCLK` input port at 0 ps;
* that edge is present with both `logic` and `bit` TB clocks;
* holding `PCLK` at X until 1 ns removes it, with zero failures for both SVA sets, 8,348 cycles and zero spec mismatches.

Phase B therefore uses `+define+CLK_START_1NS` for every build: reference check, SVA compile, baseline, activation and detection. The clock period (10 ns), rising edges (5, 15, 25 ... ns) and vector timing (rows applied at falling edges from 10 ns, checked 2 ns later) are unchanged. `CLK2STATE` is not used.

## What the audited matrix checks (`results_clkstart1ns/matrix.md`)

| Section | Checks |
|---|---|
| 0. Run integrity | For each of the 33 logs (ref check, 2 baselines, 10 activation, 20 detection), checked rather than assumed: TBSUMMARY reached; cycles = 8,348; reference instance = spec model on every cycle; start-up = CLK_START_1NS. Reference-as-DUT runs must have 0 spec mismatches and 0 divergence; mutant runs must have spec mismatches = divergence. |
| 1. Baseline | SVA failures on the reference, at t=0 and t>0. Must both be 0. |
| 2. Activation | Each mutant diverges from the reference with no SVA present. |
| 3, 4. Detection, kill rate | A mutant counts as detected only on an SVA failure (label, time) that is absent from the baseline. |
| 5. Detection validation | Fail cycle (the cycle whose values the assertion judged), first divergence cycle, **latency in cycles**. (a) No failure before divergence; (b) every new failure falls in a diverging cycle or the cycle after one (per-cycle `.div` file); (c) divergence is identical to the no-SVA activation run. Any violation gives SUSPECT. |
| 6. Audit gate | PASS only if: both SVA sets compile; all runs pass section 0; 10/10 activated; zero baseline failures; no RUN_ERROR; no SUSPECT. MISSED cells are listed for adjudication. The script exits 1 on FAIL. |

`results_validation/first_vs_corrected.md` compares the first run (re-analysed read-only from `results/`) with this run: baseline, activation, and every detection cell (outcome, first label, fail cycle, latency, verdict).

**Expected difference:** only the 2 Claude baseline failures at t=0 disappear. Detection outcomes should not change, because the first run already subtracted those failures. Explain any other change before reporting.

## Preservation

* `results/` and `build/` are only read.
* `results_validation/time0_experiment.txt` (phase A) and `results_validation/time0_v2/` (time-0 experiment) are kept. Phase A and `run_time0_experiment.sh` refuse to rerun when their results exist.
* Phase B refuses to start if `results_clkstart1ns/` already exists.
* The six originals are SHA-256 checked before every SVA run.
