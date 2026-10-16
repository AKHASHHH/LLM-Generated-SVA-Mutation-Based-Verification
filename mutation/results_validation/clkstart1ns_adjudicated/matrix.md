# Project 4 v2 - SVA mutation-detection results

Source logs: `results_clkstart1ns/`. Mutants are CONTROLLED, intentional defects.

## 0. Run integrity (checked, not assumed)

Expected per run: cycles = 8348; reference instance = spec model on every cycle; clock start-up = CLK_START_1NS.

| Run | Start-up | Cycles | Spec mismatch | Ref vs spec | Divergence | Result |
|---|---|---|---|---|---|---|
| ref_check/ref | CLK_START_1NS | 8348 | 0 | 0 | 0 | OK |
| fp/sva_gpt.ref | CLK_START_1NS | 8348 | 0 | 0 | 0 | OK |
| fp/sva_claude.ref | CLK_START_1NS | 8348 | 0 | 0 | 0 | OK |
| activation/M01_PEND_CLEAR_BEATS_SET | CLK_START_1NS | 8348 | 71 | 0 | 71 | OK |
| detection/sva_gpt/M01_PEND_CLEAR_BEATS_SET | CLK_START_1NS | 8348 | 71 | 0 | 71 | OK |
| detection/sva_claude/M01_PEND_CLEAR_BEATS_SET | CLK_START_1NS | 8348 | 71 | 0 | 71 | OK |
| activation/M02_OVF_USES_POSTCLEAR_PEND | CLK_START_1NS | 8348 | 76 | 0 | 76 | OK |
| detection/sva_gpt/M02_OVF_USES_POSTCLEAR_PEND | CLK_START_1NS | 8348 | 76 | 0 | 76 | OK |
| detection/sva_claude/M02_OVF_USES_POSTCLEAR_PEND | CLK_START_1NS | 8348 | 76 | 0 | 76 | OK |
| activation/M03_RELOAD_USES_WRITTEN_LOAD | CLK_START_1NS | 8348 | 618 | 0 | 618 | OK |
| detection/sva_gpt/M03_RELOAD_USES_WRITTEN_LOAD | CLK_START_1NS | 8348 | 618 | 0 | 618 | OK |
| detection/sva_claude/M03_RELOAD_USES_WRITTEN_LOAD | CLK_START_1NS | 8348 | 618 | 0 | 618 | OK |
| activation/M04_SW_EN_BEATS_ONESHOT_COMPLETION | CLK_START_1NS | 8348 | 15 | 0 | 15 | OK |
| detection/sva_gpt/M04_SW_EN_BEATS_ONESHOT_COMPLETION | CLK_START_1NS | 8348 | 15 | 0 | 15 | OK |
| detection/sva_claude/M04_SW_EN_BEATS_ONESHOT_COMPLETION | CLK_START_1NS | 8348 | 15 | 0 | 15 | OK |
| activation/M05_LEVEL_SENSITIVE_START | CLK_START_1NS | 8348 | 1196 | 0 | 1196 | OK |
| detection/sva_gpt/M05_LEVEL_SENSITIVE_START | CLK_START_1NS | 8348 | 1196 | 0 | 1196 | OK |
| detection/sva_claude/M05_LEVEL_SENSITIVE_START | CLK_START_1NS | 8348 | 1196 | 0 | 1196 | OK |
| activation/M06_START_KEEPS_PRESCALER_PHASE | CLK_START_1NS | 8348 | 115 | 0 | 115 | OK |
| detection/sva_gpt/M06_START_KEEPS_PRESCALER_PHASE | CLK_START_1NS | 8348 | 115 | 0 | 115 | OK |
| detection/sva_claude/M06_START_KEEPS_PRESCALER_PHASE | CLK_START_1NS | 8348 | 115 | 0 | 115 | OK |
| activation/M07_PRESCALER_EQUALITY_COMPARE | CLK_START_1NS | 8348 | 1187 | 0 | 1187 | OK |
| detection/sva_gpt/M07_PRESCALER_EQUALITY_COMPARE | CLK_START_1NS | 8348 | 1187 | 0 | 1187 | OK |
| detection/sva_claude/M07_PRESCALER_EQUALITY_COMPARE | CLK_START_1NS | 8348 | 1187 | 0 | 1187 | OK |
| activation/M08_RESTART_REQUIRES_EN | CLK_START_1NS | 8348 | 1158 | 0 | 1158 | OK |
| detection/sva_gpt/M08_RESTART_REQUIRES_EN | CLK_START_1NS | 8348 | 1158 | 0 | 1158 | OK |
| detection/sva_claude/M08_RESTART_REQUIRES_EN | CLK_START_1NS | 8348 | 1158 | 0 | 1158 | OK |
| activation/M09_IE_GATES_PEND | CLK_START_1NS | 8348 | 1481 | 0 | 1481 | OK |
| detection/sva_gpt/M09_IE_GATES_PEND | CLK_START_1NS | 8348 | 1481 | 0 | 1481 | OK |
| detection/sva_claude/M09_IE_GATES_PEND | CLK_START_1NS | 8348 | 1481 | 0 | 1481 | OK |
| activation/M10_IRQ_REGISTERED | CLK_START_1NS | 8348 | 159 | 0 | 159 | OK |
| detection/sva_gpt/M10_IRQ_REGISTERED | CLK_START_1NS | 8348 | 159 | 0 | 159 | OK |
| detection/sva_claude/M10_IRQ_REGISTERED | CLK_START_1NS | 8348 | 159 | 0 | 159 | OK |

## 1. SVA compilation and false positives on the reference

| SVA set | Variant | First-pass compile | Ref run finished | Spec mismatches | FP failures at t=0 | FP failures at t>0 | Labels at t>0 |
|---|---|---|---|---|---|---|---|
| sva_gpt_1 | original | COMPILE_OK | yes | 0 | 0 | 0 | - |
| sva_claude_1 | original | COMPILE_OK | yes | 0 | 0 | 0 | - |

## 2. Mutant activation (no SVA, differential vs reference)

| Mutant | Violates | Activated | Diverging cycles | Port-visible cycles | First divergence (test, cycle) |
|---|---|---|---|---|---|
| M01_PEND_CLEAR_BEATS_SET | R-PRI-4, R-INT-2 | YES | 71 | 28 | EX07, cyc 84 |
| M02_OVF_USES_POSTCLEAR_PEND | R-INT-3 | YES | 76 | 1 | EX07, cyc 84 |
| M03_RELOAD_USES_WRITTEN_LOAD | R-TMR-11 | YES | 618 | 14 | EX10, cyc 128 |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | R-PRI-2 | YES | 15 | 0 | EX16, cyc 213 |
| M05_LEVEL_SENSITIVE_START | R-TMR-10, R-TMR-7 | YES | 1196 | 125 | EX12, cyc 160 |
| M06_START_KEEPS_PRESCALER_PHASE | R-TMR-7 | YES | 115 | 2 | EX11, cyc 150 |
| M07_PRESCALER_EQUALITY_COMPARE | R-TMR-13, R-TMR-1 | YES | 1187 | 373 | EX12, cyc 161 |
| M08_RESTART_REQUIRES_EN | R-TMR-9 | YES | 1158 | 40 | D06_RESTART_WHILE_STOPPED, cyc 396 |
| M09_IE_GATES_PEND | R-INT-7, R-INT-1 | YES | 1481 | 146 | EX05, cyc 53 |
| M10_IRQ_REGISTERED | R-INT-6 | YES | 159 | 159 | EX02, cyc 18 |

## 3. Detection matrix

| Mutant | sva_gpt_1 | sva_claude_1 |
|---|---|---|
| M01_PEND_CLEAR_BEATS_SET | DETECTED: R_PRI_4_INT_1_2_5_PEND (cycle 84, EX07) | DETECTED: INT1_pend_set (cycle 84, EX07) |
| M02_OVF_USES_POSTCLEAR_PEND | DETECTED: R_PRI_5_INT_3_4_5_OVF (cycle 84, EX07) | DETECTED: INT3_ovf_set (cycle 84, EX07) |
| M03_RELOAD_USES_WRITTEN_LOAD | DETECTED: R_PRI_3_7_PERIODIC_LOAD_COLLISION (cycle 128, EX10) | DETECTED: PRI3_periodic_exp_load_write (cycle 128, EX10) |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | DETECTED: R_PRI_2_ONESHOT_CTRL_COLLISION (cycle 213, EX16) | DETECTED: PRI2_oneshot_exp_ctrl_en1 (cycle 213, EX16) |
| M05_LEVEL_SENSITIVE_START | DETECTED: R_PRI_3_TMR_1_2_7_9_13_PCNT (cycle 160, EX12) | DETECTED: TMR10_ctrl_en_no_start (cycle 160, EX12) |
| M06_START_KEEPS_PRESCALER_PHASE | DETECTED: R_PRI_3_TMR_1_2_7_9_13_PCNT (cycle 150, EX11) | DETECTED: TMR7_TMR9_reload_transfer (cycle 150, EX11) |
| M07_PRESCALER_EQUALITY_COMPARE | DETECTED: R_PRI_3_TMR_1_2_7_9_13_PCNT (cycle 161, EX12) | DETECTED: TMR13_psc_gt_forces_tick (cycle 161, EX12) |
| M08_RESTART_REQUIRES_EN | DETECTED: R_PRI_3_TMR_2_3_4_5_7_9_ACTIVE (cycle 396, D06_RESTART_WHILE_STOPPED) | DETECTED: PRI3_restart_while_stopped (cycle 396, D06_RESTART_WHILE_STOPPED) |
| M09_IE_GATES_PEND | DETECTED: R_PRI_4_INT_1_2_5_PEND (cycle 53, EX05) | DETECTED: APB2_nonacc_flags (cycle 53, EX05) |
| M10_IRQ_REGISTERED | DETECTED: R_INT_6_IRQ (cycle 18, EX02) | DETECTED: INT6_irq (cycle 18, EX02) |

## 4. Kill rate (activated mutants only)

| SVA set | Detected | of which SUSPECT | Missed | Kill rate |
|---|---|---|---|---|
| sva_gpt_1 | 10 | 0 | 0 | 10/10 |
| sva_claude_1 | 10 | 0 | 0 | 10/10 |

## 5. Detection validation

Cycle c = [10c+5, 10c+15) ns = vector row c. Fail cycle = the cycle whose values the first new failure judged.

| Mutant | SVA | First new failure | Kind | Fail time | Fail cycle | First divergence cycle | Latency (cycles) | New failures | Outside diverging cycles (+1), not adjudicated | Divergence identical to activation run | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| M01_PEND_CLEAR_BEATS_SET | sva_gpt_1 | R_PRI_4_INT_1_2_5_PEND | concurrent | 855 ns | 84 | 84 | 0 | 26 | 0 | yes | VALID |
| M01_PEND_CLEAR_BEATS_SET | sva_claude_1 | INT1_pend_set | concurrent | 855 ns | 84 | 84 | 0 | 42 | 0 | yes | VALID |
| M02_OVF_USES_POSTCLEAR_PEND | sva_gpt_1 | R_PRI_5_INT_3_4_5_OVF | concurrent | 855 ns | 84 | 84 | 0 | 18 | 0 | yes | VALID |
| M02_OVF_USES_POSTCLEAR_PEND | sva_claude_1 | INT3_ovf_set | concurrent | 855 ns | 84 | 84 | 0 | 33 | 0 | yes | VALID |
| M03_RELOAD_USES_WRITTEN_LOAD | sva_gpt_1 | R_PRI_3_7_PERIODIC_LOAD_COLLISION | concurrent | 1295 ns | 128 | 128 | 0 | 72 | 0 | yes | VALID |
| M03_RELOAD_USES_WRITTEN_LOAD | sva_claude_1 | PRI3_periodic_exp_load_write | concurrent | 1295 ns | 128 | 128 | 0 | 48 | 0 | yes | VALID |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | sva_gpt_1 | R_PRI_2_ONESHOT_CTRL_COLLISION | concurrent | 2145 ns | 213 | 213 | 0 | 8 | 0 | yes | VALID |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | sva_claude_1 | PRI2_oneshot_exp_ctrl_en1 | concurrent | 2145 ns | 213 | 213 | 0 | 9 | 0 | yes | VALID |
| M05_LEVEL_SENSITIVE_START | sva_gpt_1 | R_PRI_3_TMR_1_2_7_9_13_PCNT | concurrent | 1615 ns | 160 | 160 | 0 | 116 | 0 | yes | VALID |
| M05_LEVEL_SENSITIVE_START | sva_claude_1 | TMR10_ctrl_en_no_start | concurrent | 1615 ns | 160 | 160 | 0 | 206 | 0 | yes | VALID |
| M06_START_KEEPS_PRESCALER_PHASE | sva_gpt_1 | R_PRI_3_TMR_1_2_7_9_13_PCNT | concurrent | 1515 ns | 150 | 150 | 0 | 8 | 0 | yes | VALID |
| M06_START_KEEPS_PRESCALER_PHASE | sva_claude_1 | TMR7_TMR9_reload_transfer | concurrent | 1515 ns | 150 | 150 | 0 | 8 | 0 | yes | VALID |
| M07_PRESCALER_EQUALITY_COMPARE | sva_gpt_1 | R_PRI_3_TMR_1_2_7_9_13_PCNT | concurrent | 1625 ns | 161 | 161 | 0 | 1619 | 0 | yes | VALID |
| M07_PRESCALER_EQUALITY_COMPARE | sva_claude_1 | TMR13_psc_gt_forces_tick | concurrent | 1625 ns | 161 | 161 | 0 | 2716 | 0 | yes | VALID |
| M08_RESTART_REQUIRES_EN | sva_gpt_1 | R_PRI_3_TMR_2_3_4_5_7_9_ACTIVE | concurrent | 3975 ns | 396 | 396 | 0 | 67 | 0 | yes | VALID (6 adjudicated blind-spot failures) |
| M08_RESTART_REQUIRES_EN | sva_claude_1 | PRI3_restart_while_stopped | concurrent | 3975 ns | 396 | 396 | 0 | 80 | 0 | yes | VALID (4 adjudicated blind-spot failures) |
| M09_IE_GATES_PEND | sva_gpt_1 | R_PRI_4_INT_1_2_5_PEND | concurrent | 545 ns | 53 | 53 | 0 | 216 | 0 | yes | VALID |
| M09_IE_GATES_PEND | sva_claude_1 | APB2_nonacc_flags | concurrent | 545 ns | 53 | 53 | 0 | 653 | 0 | yes | VALID |
| M10_IRQ_REGISTERED | sva_gpt_1 | R_INT_6_IRQ | immediate/deferred | 185 ns | 18 | 18 | 0 | 184 | 0 | yes | VALID (5 adjudicated blind-spot failures) |
| M10_IRQ_REGISTERED | sva_claude_1 | INT6_irq | concurrent | 190 ns | 18 | 18 | 0 | 390 | 0 | yes | VALID (5 adjudicated blind-spot failures) |

Every MISSED or SUSPECT cell must be adjudicated before it is reported.

## 6. Audit gate

| Check | Result | Detail |
|---|---|---|
| Both original SVA sets compiled | PASS |  |
| Every run complete and consistent (33 logs) | PASS | 0 failing |
| All 10 mutants activated | PASS | 10/10 |
| Zero baseline SVA failures on the reference | PASS | sva_gpt_1: 0, sva_claude_1: 0 |
| No RUN_ERROR cells | PASS | 0 |
| Every detection causally attributable (no SUSPECT) | PASS | 0 SUSPECT |

**AUDIT: PASS**
