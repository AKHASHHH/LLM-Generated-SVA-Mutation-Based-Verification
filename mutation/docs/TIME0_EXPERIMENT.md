# Time-0 failures of sva_claude_1 (APB3_pready, APB8_pslverr_nonacc): decisive experiment

Supersedes the hypothesis in `VALIDATION.md` §1 and the "no clock edge at time 0" row in `SVA_INTEGRATION_REVIEW.md` §3. Both of those documents are left unchanged as the record of what was believed at the time.

## 1. What phase A showed

| Run | TB `PCLK` | TBDIAG (cover on the **TB** `PCLK`) | Claude failures at 0 ps | GPT |
|---|---|---|---|---|
| A0 | `logic PCLK = 1'b0` | event at 0 | APB3_pready, APB8_pslverr_nonacc | 0 |
| A1 | `bit PCLK = 1'b0` | **no** event at 0 | **the same two** | 0 |

A1 falsifies the earlier hypothesis. The TB variable's initializer is not what clocks the assertions.

## 2. Why `bit PCLK` could not have fixed it

TBDIAG watched the wrong signal. sva_claude_1 clocks on its **own** input port, not on the TB variable:

```
module apb_timer_sva ( input logic PCLK, ... );
`define OCLK @(posedge PCLK or negedge PCLK) disable iff (1'b0)
```

* `input logic PCLK` with no net type is an implicit `wire logic` net (IEEE 1800-2017 §23.2.2.3). The port connection is a continuous assignment from `tb_top.PCLK` onto that net.
* A 4-state net starts at its default value `z`. In time slot 0 the port assignment drives it to `0`. Per §9.4.2 (Table 9-2), **z→0 is a negedge**.
* That transition happens whether the source is `logic` or `bit`. Making the TB variable 2-state removes the TB variable's own X→0 event, but not the z→0 event on the SVA-side net.
* The DUT and reference also receive `PCLK` through input ports, but they only use `posedge PCLK`. z→0 is not a posedge, so they are unaffected.

**Hypothesis H2:** the time-0 failures come from a z→0 negedge on `u_sva.PCLK` at 0 ps. The ungated both-edge `OCLK` checks evaluate on that event, using values sampled in the preponed region of time slot 0, before `PREADY` and `PSLVERR` have been driven by the DUT's continuous assignments and combinational blocks.

This is a hypothesis until E1 and E2 confirm it. Port collapsing in VCS could, in principle, merge the port net with the TB variable. The experiment observes the port net directly instead of assuming.

**Why GPT is unaffected:** its output checks are `assert final` (evaluated in the postponed region, after settling), and its concurrent properties use `posedge PCLK` with `disable iff (!PRESETn)`.

**One open detail E1 also resolves.** `APB8_pslverr` (`PSLVERR === err`) did **not** fail at 0 ps, but `APB8_pslverr_nonacc` (`!acc |-> !PSLVERR`) did. That is only consistent if the sampled `err` and `PSLVERR` are both unknown while `acc` is sampled 0. `+define+DIAG_SVA_INTERNALS` prints the sampled `acc`, `err`, `rd_acc`, `mapped` and `PRDATA` at the same event, so this is measured rather than inferred.

## 3. The experiment

Same TB, same vectors, reference DUT, unmodified `sva_claude_1.sv` and `sva_gpt_1.sv`. Only the clock start-up differs.

| Run | Define | `PCLK` at 0 ps | Expected under H2 |
|---|---|---|---|
| E1 | none (first-run harness) | `logic`, = 0 | TBDIAG2 event on `u_sva.PCLK` at 0 ps; Claude fails the 2 checks at 0 ps |
| E2 | `CLK2STATE` | `bit`, = 0 | **TBDIAG2 event on `u_sva.PCLK` at 0 ps** although the TB variable has none; same 2 failures |
| E3 | `CLK_START_1NS` | `logic`, X until 1 ns, then 0 | no event at 0 ps (port net z→x is not an edge); first `u_sva.PCLK` event at 1 ns with settled sampled values; **0 failures** |

All three runs must report `spec_mismatch_cycles=0` and the same cycle count (8,348). In E3 the clock still rises at 5, 15, 25 … ns and vectors still start at 10 ns: the stimulus thread skips the 1 ns X→0 edge with one `@(posedge PCLK)`.

`+define+DIAG_PORTCLK` adds a TB `cover property` on `@(posedge u_sva.PCLK or negedge u_sva.PCLK)`, the exact clocking event of Claude's `OCLK` checks on the exact net they use. It prints, during the first 2 ns, `u_sva.PCLK`, the TB `PCLK`, and the `$sampled()` values at the SVA ports. It observes only; nothing in either SVA file is disabled, gated or changed.

GPT runs in all three configurations as the regression control.

## 4. Decision rules

| Observation | Conclusion | What to report |
|---|---|---|
| E1 and E2 show a `u_sva.PCLK` event at 0 ps with unknown sampled `PREADY`/`PSLVERR`; E3 has 0 failures | **Testbench initialization artifact (H2 confirmed).** No spec-defined cycle exists before the first rising edge, so these are not spec violations and not checker defects. | "2 time-0 failures on the reference, root-caused to the z→0 port-net edge on the SVA clock at 0 ps; 0 false positives on spec-defined cycles." Separately, as a design observation: Claude's both-edge checks with `disable iff (1'b0)` are not robust to start-up, unlike GPT's settled/reset-gated checks. |
| E2 shows **no** `u_sva.PCLK` event at 0 ps but the failures remain, and E3 has 0 failures | VCS evaluates the both-edge clock at time 0 without a visible net edge (tool behavior). Still a start-up artifact, not a spec violation. | As above, but cite VCS start-up evaluation instead of the port net. Send me the E2 log. |
| E3 still fails at 0 ps | H2 is wrong; something other than a PCLK edge triggers time-0 evaluation. | Stop. Send me all three logs. Do not use a TB fix. |
| E3 fails at ≥ 1 ns, or E3 has new failures not in E1 | The checks fail on settled values: a **genuine checker issue** (or an E3 harness problem). | Adjudicate the failing time against the spec text (README §5). |
| Any run has `spec_mismatch_cycles` ≠ 0 or a different cycle count | The harness change altered the stimulus. E3 is invalid. | Send me the log. |

## 5. Consequence for phase B (only after this is settled)

If row 1 or 2 holds, phase B (the clean rerun) uses `+define+CLK_START_1NS`, not `CLK2STATE`, because only the 1 ns start removes the event on the SVA's own clock net. Phase A's `CLK2STATE` result stays on record as the falsified attempt.

## 6. Files

| File | Change |
|---|---|
| `tb/tb_top.sv` | `+define+CLK_START_1NS`, `+define+DIAG_PORTCLK`, `+define+DIAG_SVA_INTERNALS`. With none of them defined, the TB behaves exactly as before. |
| `scripts/run_time0_experiment.sh` | new; writes only to `results_validation/time0_v2/` and `build_validation/time0_v2/` |
| `docs/TIME0_EXPERIMENT.md` | this file |
