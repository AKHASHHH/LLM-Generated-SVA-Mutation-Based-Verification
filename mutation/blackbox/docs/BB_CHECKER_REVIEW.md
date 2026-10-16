# Experiment 2: pre-run review of the two generated black-box checkers

Both files are frozen first-pass artifacts. Nothing below was changed in them. Findings are recorded for the write-up; none is a claim about simulation behaviour. The VCS baseline run on the reference is the authority on false positives.

## 1. Provenance and integrity

| File | SHA-256 | Relation to raw response |
|---|---|---|
| `gen/sva_bb_gpt_1.sv` | `b4b620a8b1124661f19b5ceb33532889ff29ba39039f874c067618bb868a3dce` | Byte-identical to `raw_gpt_1.txt` (the response was bare code) |
| `gen/sva_bb_claude_1.sv` | `ce9b51788eb755071f52db5e298d166a2fd00fe4a72fec121166e17f097c2d47` | Exactly `raw_claude_1.txt` (`262a598d…`) minus its opening and closing code-fence lines; nothing else removed |

The runner refuses to run if any of the four files differs from `docs/BB_FROZEN_SHA256.txt`. It also checks your `gen/bb_sha256.txt`.

## 2. Interface compliance and isolation

| Check | sva_bb_gpt_1 | sva_bb_claude_1 |
|---|---|---|
| Module name and 11-port list identical to the contract | yes | yes |
| Single module, no outputs | yes | yes |
| Hierarchical references, `$root`, bind, force/release, file I/O, DPI, `` `include `` (comment-stripped scan) | none | none |
| Elaborates standalone as the only top (slang 12.0) | 0 errors, 0 warnings | 0 errors, 0 warnings |
| Elaborates bound into the unchanged `tb_top` with the reference and with each of the 10 mutants (slang, `CLK_START_1NS`) | 11/11 | 11/11 |
| Clocking | `posedge PCLK` only | `posedge PCLK` only |

Neither checker is sensitive to a falling clock edge. The time-0 mechanism that affected the white-box Claude checker therefore cannot arise here. `CLK_START_1NS` is still used, so both experiments share one harness.

**Compile risk under VCS: low.** Both use only standard constructs: `assert property`, `|->`, `|=>`, `$past`, `disable iff`, `localparam logic`, `always_ff` with asynchronous reset. VCS is still the authority; the first-pass compile log is preserved.

## 3. Rule 2 compliance (bookkeeping only, no procedural model)

* **GPT.** Compliant. It keeps:
  * SHADOW and {PSC, IE, MODE} from successful writes;
  * a "known stopped" flag (set by a CTRL write with EN=0);
  * readback-derived STATUS, updated by W1C only while known stopped.

  It never predicts COUNT, ACTIVE or PCNT.
* **Claude.** Compliant in my judgement. It keeps:
  * written configuration;
  * values read back while the last written EN was 0;
  * sticky-flag and "provably zero" flags.

  It also asserts the legal **one-step** change between reads in back-to-back cycles: COUNT holds or decrements by 1; PCNT holds, clears, or increments by 1 only below PSC; ACTIVE holds or takes SHADOW. That is a transition relation over observed values, not a model that predicts values over time. Record it as a judgement call (plan, risk 3).

## 4. Spec review findings

I checked every assertion against R-APB-1…10, R-RST-1…4, R-TMR-1…13, R-INT-1…7, R-PRI-1…7 and the register map. I found no assertion that contradicts the spec. Each of the following points looked like it could misfire, but is consistent with the spec on inspection:

* **GPT output checks during reset.** `R_APB_3`, `R_APB_7`, `R_APB_8` and `R_APB_6_*` have no `disable iff`, so they are evaluated during reset. This is correct: R-RST-4 applies the output rules during reset.
* **GPT write decode.** GPT gates its write decode on the DUT's own `PSLVERR`. If a design raised PSLVERR wrongly, GPT would also skip its bookkeeping update. `R_APB_8` checks PSLVERR independently, so nothing is lost. Recorded as a design observation.
* **Claude's start detection.** `start_ev` uses "last written EN = 0" as proof that EN = 0. This is sound because only a CTRL write can set EN to 1 (R-PRI-2).
* **Claude's PEND/OVF zero tracking.** The "provably zero" logic (`pend_z`) is set only by a W1C while the last written EN is 0, when no expiration is possible. It is cleared by any CTRL write with EN = 1. This is consistent with R-INT-2, R-INT-5 and R-PRI-4.
* **Claude's irq-fall check.** `R_INT_2_FALL` allows irq to fall only through a PEND W1C or an IE-clearing CTRL write. Reset falls are disabled by `dis_rst`, which includes an asynchronous `~PRESETn` and a one-cycle post-reset guard. This is consistent with R-INT-2, R-INT-6 and R-INT-7.
* **Sampling alignment of both checkers' `$past` usage.** I checked it against the TB schedule: inputs change at falling edges, and the checks sample at rising edges. The sampled history lines up with the transition each property describes.

**Structural observations** (coverage facts, not results):

* **GPT has no assertion on COUNT, ACTIVE or PSCNT values beyond their reserved bits.** `restart_write` is declared but unused, so no property refers to R-TMR-9. Timer-behaviour defects reach GPT only through STATUS, irq or CTRL readback.
* **Claude checks COUNT, ACTIVE and PCNT only in three situations:**
  1. while stopped (hold);
  2. in the cycle **immediately** after a start or restart;
  3. on read accesses in **consecutive** cycles.

  Situations 2 and 3 fire only if the vectors contain those exact patterns. Treat any miss involving them as a possible vacuity or stimulus limitation, and check antecedents before calling it a checker weakness.

## 5. Integration requirements met by the harness

* **Bind target.** `tb/bb_bind.sv` binds `apb_timer_bb_sva u_bb` into the unchanged `tb_top` (SHA-256 `a4b464c8…`), compiled without `WITH_SVA`. The checker sees the TB-driven inputs and the DUT's outputs, never the reference instance.
* **BBHOOK.** It prints from harness code, never from the checker. It references `tb_top.u_bb.PCLK`, so an unbound checker is a compile error, not a silent "0 failures". Every log must contain it.
* **Parser.** Failures are parsed from `u_bb` paths. The white-box parser keys on `u_sva`; reusing it unchanged would have reported 0 failures everywhere, turning every mutant into a false MISSED.
* **End of simulation.** Assertion attempts still pending at `$finish` (for example a `|=>` started in the last cycle) are not failures under default VCS reporting, so they are not counted.
