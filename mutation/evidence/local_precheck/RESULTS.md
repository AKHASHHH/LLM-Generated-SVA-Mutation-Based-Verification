# Local pre-check results (CXXRTL, Yosys 0.70) - PRELIMINARY; VCS runs are authoritative

Harness: evidence/local_precheck/cxxrtl_tb.cpp (inputs applied with clock low, outputs and the 10 state registers compared each cycle to vectors/all.vec).

| DUT | Cycles | Cycles != spec-model expected (outputs or state) | Port-visible | First divergence | Tests with divergence |
|---|---|---|---|---|---|
| reference (apb_timer_refdut) | 8348 | 0 | 0 | - | 0 |
| M01_PEND_CLEAR_BEATS_SET | 8348 | 71 | 28 | EX07 (global cyc 84) | 10 |
| M02_OVF_USES_POSTCLEAR_PEND | 8348 | 76 | 1 | EX07 (global cyc 84) | 8 |
| M03_RELOAD_USES_WRITTEN_LOAD | 8348 | 618 | 14 | EX10 (global cyc 128) | 19 |
| M04_SW_EN_BEATS_ONESHOT_COMPLETION | 8348 | 15 | 0 | EX16 (global cyc 213) | 4 |
| M05_LEVEL_SENSITIVE_START | 8348 | 1196 | 125 | EX12 (global cyc 160) | 35 |
| M06_START_KEEPS_PRESCALER_PHASE | 8348 | 115 | 2 | EX11 (global cyc 150) | 5 |
| M07_PRESCALER_EQUALITY_COMPARE | 8348 | 1187 | 373 | EX12 (global cyc 161) | 23 |
| M08_RESTART_REQUIRES_EN | 8348 | 1158 | 40 | D06_RESTART_WHILE_STOPPED (global cyc 396) | 21 |
| M09_IE_GATES_PEND | 8348 | 1481 | 146 | EX05 (global cyc 53) | 32 |
| M10_IRQ_REGISTERED | 8348 | 159 | 159 | EX02 (global cyc 18) | 52 |

Reading: the reference matches every cycle; every mutant diverges (i.e. is activated) under the vector set.
Port-visible = cycles where PRDATA/PSLVERR/PREADY/irq differ; the rest are architectural-state-only divergences,
which the white-box SVA hookup can observe but a port-only checker could not without a register read.
