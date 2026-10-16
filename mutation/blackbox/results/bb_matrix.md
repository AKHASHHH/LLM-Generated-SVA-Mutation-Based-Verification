# Experiment 2: black-box (port-only) checker results

Checkers: blackbox/gen/sva_bb_gpt_1.sv, sva_bb_claude_1.sv (original first-pass files, hashes in docs/BB_FROZEN_SHA256.txt).
Same TB (unchanged), reference, 10 mutants and 8348-cycle vectors as Experiment 1; CLK_START_1NS. White-box comparison: `results_validation/clkstart1ns_adjudicated/summary.json`.

## 0. Run integrity (checked, not assumed)

| Run | Start-up | BBHOOK | Cycles | Spec mismatch | Ref vs spec | Divergence | Result |
|---|---|---|---|---|---|---|---|
| baseline/sva_bb_gpt.ref | CLK_START_1NS | yes | 8348 | 0 | 0 | 0 | OK |
| baseline/sva_bb_claude.ref | CLK_START_1NS | yes | 8348 | 0 | 0 | 0 | OK |
| detection/sva_bb_gpt/M01_PEND_CLEAR_BEATS_SET | CLK_START_1NS | yes | 8348 | 71 | 0 | 71 | OK |
| detection/sva_bb_gpt/M02_OVF_USES_POSTCLEAR_PEND | CLK_START_1NS | yes | 8348 | 76 | 0 | 76 | OK |
| detection/sva_bb_gpt/M03_RELOAD_USES_WRITTEN_LOAD | CLK_START_1NS | yes | 8348 | 618 | 0 | 618 | OK |
| detection/sva_bb_gpt/M04_SW_EN_BEATS_ONESHOT_COMPLETION | CLK_START_1NS | yes | 8348 | 15 | 0 | 15 | OK |
| detection/sva_bb_gpt/M05_LEVEL_SENSITIVE_START | CLK_START_1NS | yes | 8348 | 1196 | 0 | 1196 | OK |
| detection/sva_bb_gpt/M06_START_KEEPS_PRESCALER_PHASE | CLK_START_1NS | yes | 8348 | 115 | 0 | 115 | OK |
| detection/sva_bb_gpt/M07_PRESCALER_EQUALITY_COMPARE | CLK_START_1NS | yes | 8348 | 1187 | 0 | 1187 | OK |
| detection/sva_bb_gpt/M08_RESTART_REQUIRES_EN | CLK_START_1NS | yes | 8348 | 1158 | 0 | 1158 | OK |
| detection/sva_bb_gpt/M09_IE_GATES_PEND | CLK_START_1NS | yes | 8348 | 1481 | 0 | 1481 | OK |
| detection/sva_bb_gpt/M10_IRQ_REGISTERED | CLK_START_1NS | yes | 8348 | 159 | 0 | 159 | OK |
| detection/sva_bb_claude/M01_PEND_CLEAR_BEATS_SET | CLK_START_1NS | yes | 8348 | 71 | 0 | 71 | OK |
| detection/sva_bb_claude/M02_OVF_USES_POSTCLEAR_PEND | CLK_START_1NS | yes | 8348 | 76 | 0 | 76 | OK |
| detection/sva_bb_claude/M03_RELOAD_USES_WRITTEN_LOAD | CLK_START_1NS | yes | 8348 | 618 | 0 | 618 | OK |
| detection/sva_bb_claude/M04_SW_EN_BEATS_ONESHOT_COMPLETION | CLK_START_1NS | yes | 8348 | 15 | 0 | 15 | OK |
| detection/sva_bb_claude/M05_LEVEL_SENSITIVE_START | CLK_START_1NS | yes | 8348 | 1196 | 0 | 1196 | OK |
| detection/sva_bb_claude/M06_START_KEEPS_PRESCALER_PHASE | CLK_START_1NS | yes | 8348 | 115 | 0 | 115 | OK |
| detection/sva_bb_claude/M07_PRESCALER_EQUALITY_COMPARE | CLK_START_1NS | yes | 8348 | 1187 | 0 | 1187 | OK |
| detection/sva_bb_claude/M08_RESTART_REQUIRES_EN | CLK_START_1NS | yes | 8348 | 1158 | 0 | 1158 | OK |
| detection/sva_bb_claude/M09_IE_GATES_PEND | CLK_START_1NS | yes | 8348 | 1481 | 0 | 1481 | OK |
| detection/sva_bb_claude/M10_IRQ_REGISTERED | CLK_START_1NS | yes | 8348 | 159 | 0 | 159 | OK |

## 1. Isolation, compilation and baseline (checker false positives)

| Checker | Isolation | In-TB compile | Gate | Cycles | Spec mismatch | Ref vs spec | Failures | Failing labels | Unexplained | At start-up (<= 5 ns) | Integrity problems |
|---|---|---|---|---|---|---|---|---|---|---|---|
| sva_bb_gpt_1 | PASS | COMPILE_OK | **PASS** | 8348 | 0 | 0 | 0 | - | - | - | - |
| sva_bb_claude_1 | PASS | COMPILE_OK | **PASS** | 8348 | 0 | 0 | 0 | - | - | - | - |

**BASELINE GATE: PASS**

## 2. Port observability per mutant (audited white-box activation runs, scoreboard sampling points)

| Mutant | Diverging cycles | Port-diverging cycles | First divergence (any) | First port divergence | Class |
|---|---|---|---|---|---|
| M01_PEND_CLEAR_BEATS_SET | 71 | 28 | 84 | 84 | OBSERVABLE |
| M02_OVF_USES_POSTCLEAR_PEND | 76 | 1 | 84 | 6888 | OBSERVABLE |
| M03_RELOAD_USES_WRITTEN_LOAD | 618 | 14 | 128 | 1169 | OBSERVABLE |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | 15 | 0 | 213 | - | NOT_OBSERVABLE |
| M05_LEVEL_SENSITIVE_START | 1196 | 125 | 160 | 1171 | OBSERVABLE |
| M06_START_KEEPS_PRESCALER_PHASE | 115 | 2 | 150 | 1814 | OBSERVABLE |
| M07_PRESCALER_EQUALITY_COMPARE | 1187 | 373 | 161 | 1171 | OBSERVABLE |
| M08_RESTART_REQUIRES_EN | 1158 | 40 | 396 | 1608 | OBSERVABLE |
| M09_IE_GATES_PEND | 1481 | 146 | 53 | 56 | OBSERVABLE |
| M10_IRQ_REGISTERED | 159 | 159 | 18 | 18 | OBSERVABLE |

## 3. Per-mutant results: black-box vs white-box

| Mutant | Port cycles | BB GPT | BB Claude | WB GPT | WB Claude |
|---|---|---|---|---|---|
| M01_PEND_CLEAR_BEATS_SET | 28 | MISSED | MISSED | DETECTED: R_PRI_4_INT_1_2_5_PEND (cycle 84) | DETECTED: INT1_pend_set (cycle 84) |
| M02_OVF_USES_POSTCLEAR_PEND | 1 | MISSED | MISSED | DETECTED: R_PRI_5_INT_3_4_5_OVF (cycle 84) | DETECTED: INT3_ovf_set (cycle 84) |
| M03_RELOAD_USES_WRITTEN_LOAD | 14 | MISSED | MISSED | DETECTED: R_PRI_3_7_PERIODIC_LOAD_COLLISION (cycle 128) | DETECTED: PRI3_periodic_exp_load_write (cycle 128) |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | 0 | NOT_OBSERVABLE | NOT_OBSERVABLE | DETECTED: R_PRI_2_ONESHOT_CTRL_COLLISION (cycle 213) | DETECTED: PRI2_oneshot_exp_ctrl_en1 (cycle 213) |
| M05_LEVEL_SENSITIVE_START | 125 | MISSED | MISSED | DETECTED: R_PRI_3_TMR_1_2_7_9_13_PCNT (cycle 160) | DETECTED: TMR10_ctrl_en_no_start (cycle 160) |
| M06_START_KEEPS_PRESCALER_PHASE | 2 | MISSED | MISSED | DETECTED: R_PRI_3_TMR_1_2_7_9_13_PCNT (cycle 150) | DETECTED: TMR7_TMR9_reload_transfer (cycle 150) |
| M07_PRESCALER_EQUALITY_COMPARE | 373 | MISSED | MISSED | DETECTED: R_PRI_3_TMR_1_2_7_9_13_PCNT (cycle 161) | DETECTED: TMR13_psc_gt_forces_tick (cycle 161) |
| M08_RESTART_REQUIRES_EN | 40 | MISSED | DETECTED: R_TMR_9_COUNT (cycle 4924) | DETECTED: R_PRI_3_TMR_2_3_4_5_7_9_ACTIVE (cycle 396) | DETECTED: PRI3_restart_while_stopped (cycle 396) |
| M09_IE_GATES_PEND | 146 | MISSED | MISSED | DETECTED: R_PRI_4_INT_1_2_5_PEND (cycle 53) | DETECTED: APB2_nonacc_flags (cycle 53) |
| M10_IRQ_REGISTERED | 159 | DETECTED: R_INT_6 (cycle 5766) | DETECTED: R_INT_2_FALL (cycle 70) | DETECTED: R_INT_6_IRQ (cycle 18) | DETECTED: INT6_irq (cycle 18) |

## 4. Kill rate over port-observable mutants

| Checker | Detected | of which SUSPECT | Missed | Not observable | of which with new failures (SUSPECT) | Kill rate (observable) | White-box kill rate |
|---|---|---|---|---|---|---|---|
| sva_bb_gpt_1 | 1 | 0 | 8 | 1 | 0 | 1/9 | 10/10 |
| sva_bb_claude_1 | 2 | 0 | 7 | 1 | 0 | 2/9 | 10/10 |

## 5. Detection attribution

Cycle c = [10c+5, 10c+15) ns = vector row c. Latency in cycles from the first port divergence and from the first divergence of any kind.

| Mutant | Checker | First new failure | Time | Fail cycle | First port div | First any div | Latency (port) | Latency (any) | New failures | Later, outside port div (+1) | Divergence = audited | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| M08_RESTART_REQUIRES_EN | sva_bb_claude_1 | R_TMR_9_COUNT | 49255 ns | 4924 | 1608 | 396 | 3316 | 4528 | 2 | 0 | yes | VALID |
| M10_IRQ_REGISTERED | sva_bb_gpt_1 | R_INT_6 | 57675 ns | 5766 | 18 | 18 | 5748 | 5748 | 1 | 0 | yes | VALID |
| M10_IRQ_REGISTERED | sva_bb_claude_1 | R_INT_2_FALL | 715 ns | 70 | 18 | 18 | 52 | 52 | 101 | 0 | yes | VALID |

## 6. Audit gate

| Check | Result | Detail |
|---|---|---|
| Isolation PASS for both checkers | PASS | gpt: PASS, claude: PASS |
| Both checkers compiled in the TB | PASS | gpt: COMPILE_OK, claude: COMPILE_OK |
| Baseline gate passed (zero or explained failures) | PASS | gpt: PASS (0 failures), claude: PASS (0 failures) |
| Every run complete and consistent (22 logs) | PASS | 0 failing |
| Audited activation data present for all 10 mutants | PASS |  |
| No RUN_ERROR cells | PASS | 0 |
| No SUSPECT cells | PASS | 0 SUSPECT |

Not observable under the existing vectors (not counted as missed): M04_SW_EN_BEATS_ONESHOT_COMPLETION.
MISSED cells requiring adjudication: M01_PEND_CLEAR_BEATS_SET x sva_bb_gpt_1, M01_PEND_CLEAR_BEATS_SET x sva_bb_claude_1, M02_OVF_USES_POSTCLEAR_PEND x sva_bb_gpt_1, M02_OVF_USES_POSTCLEAR_PEND x sva_bb_claude_1, M03_RELOAD_USES_WRITTEN_LOAD x sva_bb_gpt_1, M03_RELOAD_USES_WRITTEN_LOAD x sva_bb_claude_1, M05_LEVEL_SENSITIVE_START x sva_bb_gpt_1, M05_LEVEL_SENSITIVE_START x sva_bb_claude_1, M06_START_KEEPS_PRESCALER_PHASE x sva_bb_gpt_1, M06_START_KEEPS_PRESCALER_PHASE x sva_bb_claude_1, M07_PRESCALER_EQUALITY_COMPARE x sva_bb_gpt_1, M07_PRESCALER_EQUALITY_COMPARE x sva_bb_claude_1, M08_RESTART_REQUIRES_EN x sva_bb_gpt_1, M09_IE_GATES_PEND x sva_bb_gpt_1, M09_IE_GATES_PEND x sva_bb_claude_1.

**AUDIT: PASS**
