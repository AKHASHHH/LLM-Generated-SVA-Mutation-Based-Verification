# Attribution audit of the four SUSPECT cells (corrected run, CLK_START_1NS)

Inputs:
* the real VCS detection logs and `.div` files for M08 and M10 × both SVA sets;
* the original SVA files (SHA-256 verified: `66234d6a…`, `1056af85…`);
* `tb_top.sv` (`a4b464c8…`) and `make_matrix.py` (`af1f0d9d…`).

No simulation was rerun. The spec-model replay is `evidence/attribution/replay_blind_spots.py`, with its output in `replay_blind_spots.txt`.

## 1. Where the scoreboard cannot see

The scoreboard compares the DUT with the reference **once per vector row**, 2 ns after the falling edge. Assertions sample at clock edges, so they can fail in windows the scoreboard never samples. There are two such windows.

* **Reset-row half cycle.** Each test starts with a row that has `rst=0`. That row's `PRESETn=0` is applied at the falling edge, 5 ns after the rising edge that consumed the previous test's last row. The state produced by that edge exists for 5 ns and is reset before the scoreboard samples. The vectors contain 79 such rows.
  * The spec model reproduces all 8,347 row-to-row transitions except exactly these 79.
* **Post-vector tail.** After row 8347, the TB stops reading but keeps the last inputs driven until `$finish` 20 ns later. The rising edges at 83485 and 83495 ns consume row 8347 twice. The results are sampled by the assertions at 83495 and 83505 ns (cycles 8348 and 8349) and never by the scoreboard, because there is no row 8348.

The reference (baseline) runs for both SVA sets go through the same windows with **zero** failures. Stimulus and TB are identical between the baseline and mutant runs, so every extra failure in a mutant run is caused by the mutant file. The question is only whether the checker is **right** there.

## 2. The four SUSPECT cells

| Cell | Failures outside divergence | Window | Property / sampled condition | Spec-model replay (reference vs mutant) | Classification |
|---|---|---|---|---|---|
| M08 × GPT | 6: `R_PRI_3_TMR_2_3_4_5_7_9_COUNT`, `…_ACTIVE`, `R_PRI_3_TMR_1_2_7_9_13_PCNT` at 83495 and 83505 ns | Tail cycles 8348, 8349 | Next-state properties `a_count / a_active / a_pcnt == f($past(...))`. The past cycle holds a CMD write with START=1 while EN=0 (the last row, test RND39). The spec requires a reload (R-TMR-9). | Reference: ACT=CNT=PCNT=0 (reload from SHADOW=0). M08: ACT=CNT=5, PCNT=0x18 (restart ignored because EN=0). This is exactly the injected edit. | Genuine mutation-induced failure in an unscored window. Checker correct. |
| M08 × Claude | 4: `PRI3_restart_while_stopped`, `TMR7_TMR9_reload_transfer` at 83495 and 83505 ns | Tail cycles 8348, 8349 | `restart while stopped` ⇒ ACTIVE = COUNT = past SHADOW, PCNT = 0 | Same as above | Genuine. Checker correct; the label names the injected bug. |
| M10 × GPT | 5: `R_INT_6_IRQ` at 13975, 35465, 61495, 62825, 73095 ns | Reset-row half cycles 1397, 3546, 6149, 6282, 7309 | Deferred `irq == (a_pend && a_ie)`, evaluated at the rising edge after PEND or IE changes | At each edge PEND&IE changes (expiry, STATUS W1C, CTRL write of IE). Reference `irq` follows at once; M10's registered `irq_q` holds the old value until the reset 5 ns later. The replay predicts **exactly these 5 cycles** and no others among the 79 reset rows. | Genuine (the same one-cycle-late irq defect as the first detection). Checker correct. |
| M10 × Claude | 5: `INT6_irq` at 13980, 35470, 61500, 62830, 73100 ns | Same 5 cycles | Both-edge `irq === (a_pend && a_ie)`. At the falling edge it samples the preponed values, i.e. the 5 ns window before the reset lands. | Same | Genuine. Checker correct. The 5 ns offset from GPT is sampling phase: deferred at the rising edge vs preponed at the falling edge, same cycle. |

None of the 20 failures is a sampling artifact or a checker error. They are real DUT-vs-reference differences that the per-row scoreboard does not observe.

The M08 tail stimulus (an APB access phase held for consecutive cycles) is outside the generated vector suite. The spec model still defines it (R-APB-1: every cycle with PSEL&&PENABLE is an access).

## 3. First detections

| Cell | First failure | Fail cycle | First divergence | Evidence | Verdict |
|---|---|---|---|---|---|
| M08 × GPT | `R_PRI_3_TMR_2_3_4_5_7_9_ACTIVE`, started 3965 ns, failed 3975 ns | 396 | 396 (D06_RESTART_WHILE_STOPPED, state-only) | Offending `a_active == ($past(reload_event) ? $past(a_shadow) : $past(a_active))`. Scoreboard at 3972 ns: DUT ACTIVE/COUNT = 0, reference = 8. The directed test was built for this condition. | VALID |
| M08 × Claude | `PRI3_restart_while_stopped` / `TMR7_TMR9_reload_transfer`, failed 3975 ns | 396 | 396 | Offending `a_active == $past(a_shadow) && a_count == $past(a_shadow) && a_pcnt == 0`; same scoreboard evidence | VALID |
| M10 × GPT | `R_INT_6_IRQ`, failed 185 ns | 18 | 18 (EX02, port-visible) | Offending `irq == (a_pend && a_ie)`. Scoreboard at 192 ns: DUT irq=0, reference irq=1, identical state. | VALID |
| M10 × Claude | `INT6_irq`, failed 190 ns | 18 | 18 | Offending `irq === (a_pend && a_ie)`; same | VALID |

All four first detections:
* have latency 0;
* have the same label and cycle as in the first run;
* match a divergence identical to the no-SVA activation run.

## 4. Is the audit rule too strict?

Yes, in one specific way.

* **The flaw.** Rule (b) assumes the scoreboard sees every instant at which the DUT differs from the reference, and it does not. Rule (b) itself remains right: a failure the scoreboard cannot explain must not be waved through.
* **The correction.** It is narrow, not a relaxation. A failure outside divergence counts as ADJUDICATED only if **both** hold:
  1. it lies in a blind spot computed from the vector file (a row with `rst=0`, or a cycle ≥ 8348);
  2. it is listed, label and time exactly, with its evidence, in `docs/ADJUDICATED_FAILURES.tsv`.
* **Anything else stays SUSPECT.** Tested: removing one list entry turns its cell SUSPECT again, and listing a failure that is not in a blind spot does not excuse it.
* **Nothing is hidden.** Verdicts show the adjudicated count, e.g. `VALID (5 adjudicated blind-spot failures)`.

## 5. Disclose in the README

1. The scoreboard samples once per row. It does not observe the 5 ns between a rising edge and a reset applied at the next falling edge (79 rows), nor the 2 post-vector tail cycles. 20 SVA failures (M08, M10) fall in those windows. Each was adjudicated against the spec model and found genuine, but none is confirmed by the scoreboard.
2. The TB keeps the last APB access driven after the vectors end, so 2 unscored tail cycles exist. Harmless to the results (baseline zero failures), but not intended stimulus.
3. The adjudication used the spec model plus the injected edit, not a waveform. An optional direct VCS trace is in the command list.
4. These windows contain no first detection. The 20/20 result does not depend on them.
