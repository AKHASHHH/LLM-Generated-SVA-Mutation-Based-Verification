# Experiment 2 root-cause study: why both black-box checkers missed M07 and M09

## Evidence base

* **Real VCS (Experiment 2):**
  * audited activation counts, as port-diverging cycles and first divergence: M07 373 / 1171, M09 146 / 56;
  * zero checker failures on both mutants;
  * detection sets GPT {M10}, Claude {M08, M10}.
* **Analysis transcription** (`blackbox/analysis/bb_emulator.py`).
  * **What it contains:**
    * the frozen spec model with each mutant's one-line edit;
    * both frozen checkers, line by line, sampled as at each rising edge.
  * **Validated against VCS:** it reproduces the audited port-divergence count of all 10 mutants (28, 1, 14, 0, 125, 2, 373, 40, 146, 159), zero reference failures, and exactly the VCS detection sets.
  * **Limits:** values below marked "model" come from it. The VCS commands at the end confirm them in the waveform.
* **Sources.** Frozen spec `APBTMR_SPEC_v1.0.md`, `mutants/mutants.diff`, `vectors/all.vec`, `tests.idx`, `blackbox/gen/sva_bb_*_1.sv`.

**Central finding.** Both defects are *port-consistent*: `irq == PEND & IE` still holds at the DUT's ports, because PEND itself is wrong. Every black-box assertion exercised inside the divergence windows is a consistency check between two outputs of the same DUT, so none can fail. Catching either defect from the ports needs a value-range invariant (M07) or history-based inference (M09). Neither checker has one.

## Case 1: M07_PRESCALER_EQUALITY_COMPARE

**1. Requirement violated.**
* **R-TMR-13.** If PCNT > PSC after a PSC change, the next enabled cycle is a tick.
* **Section 8.1.** A tick is PCNT ≥ PSC.
* **Consequences:** R-TMR-1 and R-TMR-3 (PCNT and COUNT progress), R-INT-1 (PEND set at expiration) and R-INT-6 (irq).
* **The edit:** `tick = en & (pcnt == psc)` instead of `>=`.

**2. First port-divergent cycle: 1171, test RND00** (model; consistent with the audited first port divergence).

| Cycle | Event | Reference | DUT (M07) |
|---|---|---|---|
| 1161 | CTRL write 0x105 (EN=1, IE=1, PSC=1) while running, PCNT=1. Not a start (R-TMR-10). | | |
| 1162 | PCNT=2 > PSC=1 | Tick (≥), PCNT → 0 | No tick (≠). PCNT counts 3, 4, … (wraps at 255); COUNT frozen at 4 |
| 1170 | | COUNT=0 tick: expiration, PEND → 1 | No expiration |
| **1171** | no APB access | **irq=1**, PRDATA=0, PSLVERR=0, PREADY=1 | **irq=0**, PRDATA=0, PSLVERR=0, PREADY=1 |
| 1182 | first divergent **readback**: PSCNT read | PRDATA=0x1 | PRDATA=**0x16** (PCNT=22 while PSC=1 and running) |

**3. Visibility.**
* **irq** in 310 of the 373 port-diverging cycles: 296 non-access, plus irq-only cycles during accesses that show no PRDATA difference.
* **PRDATA** on reads in the remaining cycles:
  * 18 of PSCNT;
  * 15 of COUNT;
  * 10 of STATUS;
  * 6 of ACTIVE;
  * 1 of CTRL.
* PSLVERR and PREADY are never affected.

**4–6. Relevant assertions, exercise and why they passed.** Attempts = antecedent true and not disabled, in the M07 run.

| Checker | Assertion | Attempts (in port-diverging cycles) | Why no failure |
|---|---|---|---|
| GPT | `R_INT_6` (STATUS read ⇒ irq == PRDATA[0] & IE) | 128 (10) | The DUT is self-consistent: PEND=0 and irq=0 |
| GPT | `R_INT_6_KNOWN` (known-stopped ⇒ irq == observed PEND & IE) | 1691 (1) | Off while running; that is where M07 acts |
| GPT | `R_APB_6_PSCNT`, `R_APB_6_COUNT` | 140 (18), 119 (19) | Reserved bits only |
| GPT | anything relating PCNT, COUNT or PSC | **none exists** | Property gap |
| Claude | `R_TMR_1` (back-to-back PSCNT reads: hold, clear, or +1 only below PSC) | **1 (0)** in the whole 8,348 cycles | **Would fail, but its antecedent needs PSCNT reads in consecutive cycles.** The vectors contain that pattern once, outside the window |
| Claude | `R_TMR_2_PSCNT`, `R_TMR_2_COUNT` (hold while stopped) | 14 (0), 18 (0) | Off while running |
| Claude | `R_TMR_3` (back-to-back COUNT reads) | **0** | Never exercised in the whole run |
| Claude | `R_INT_6_READ`, `R_INT_6_IE`, `R_INT_1` | 128 (10), 1926 (9), 1926 (9) | Self-consistent DUT, or the antecedent `irq` is 0 |

The 1182 PSCNT read (0x16 with PSC=1) was seen by both checkers. GPT checks only bits [31:8]. Claude checks the value only when stopped or after a PSCNT read in the previous cycle.

**7. Classification.**
* **GPT:** inadequate property strength. No property constrains PCNT against PSC, or COUNT progress.
* **Claude:** the right relation, written with an **over-narrow antecedent** (two reads in consecutive cycles). Under these vectors it is effectively vacuous: 1 attempt in 8,348 cycles. It is property strength and stimulus together: a single-read invariant needs no special stimulus.
* **irq channel (both):** catching the missing irq needs knowledge of when the expiration should occur. That is a counting model, which the experiment's rule 2 prohibits.

**8. What a DV engineer would change** (outside the frozen artifacts).
* Add a single-read invariant: *a PSCNT read while the last written EN is 1, and not in the cycle right after a CTRL write, returns PCNT ≤ PSC* (R-TMR-13).
  * Transcribed (H1), it has **0 false positives on the reference** (112 attempts).
  * It fails on M07 at **cycle 1182**, 11 cycles after the first port divergence, with the existing vectors.
* Add stimulus that reads PSCNT/COUNT in consecutive cycles (R-APB-1 allows back-to-back access cycles). That brings `R_TMR_1` and `R_TMR_3` out of vacuity.

## Case 2: M09_IE_GATES_PEND

**1. Requirement violated.**
* **R-INT-1.** PEND becomes 1 at every expiration, regardless of IE.
* **R-INT-7.** IE affects only irq.
* **The edit:** `pend_n = (expire & ie) ? 1 : …`.

**2. First port-divergent cycle: 56, test EX05** (spec Example 5; model; consistent with the audited first port divergence).

| Cycle | Event | Reference | DUT (M09) |
|---|---|---|---|
| 49, 51 | LOAD=0, then CTRL=0x3 (start: EN=1, MODE=1 one-shot, IE=0) | | |
| 52 | first enabled cycle, PSC=0, COUNT=0: tick and expiration (one-shot completes, EN → 0) | PEND → 1 at the edge | **PEND stays 0** (IE=0) |
| 55 | CTRL write 0x6 (EN=0, MODE=1, IE=1) | | |
| **56–57** | no APB access | **irq=1** (PEND & IE), PRDATA=0 | **irq=0**, PRDATA=0 |
| 58 | reset (next test) | | |

**3. Visibility.**
* **irq** in 124 port-diverging cycles: 111 non-access, plus irq-only differences during accesses.
* **PRDATA** in 22 STATUS reads, PEND bit: reference 1, DUT 0.
* No other output.
* In EX05 there is **no read at all** between the divergence and the reset. The only evidence is 2 cycles of irq.

**4–6. Relevant assertions, exercise and why they passed.**

| Checker | Assertion | Attempts (in port-diverging cycles) | Why no failure |
|---|---|---|---|
| GPT | `R_INT_6` | 128 (22) | Self-consistent: PEND reads 0 and irq=0 |
| GPT | `R_INT_6_KNOWN` | 1691 (**0**) | After any enabled interval, STATUS is "unknown" until read. Every M09 divergence follows an enabled interval |
| GPT | `R_INT_2` (stopped and known ⇒ PEND == observed) | 23 (0) | Same reason |
| GPT | `R_PRI_2` (known-stopped ⇒ EN reads 0) | 38 (0) | Checks EN only; "EN is intentionally NOT modeled" (comment in the file) |
| Claude | `R_INT_6_READ` | 128 (22) | Self-consistent |
| Claude | `R_INT_6_IE`, `R_INT_1` (irq ⇒ IE, irq ⇒ PEND not provably 0) | 2139 (4) | Antecedent `irq` is 0 exactly where the DUT is wrong |
| Claude | `R_INT_2` (PEND read 1 stays 1 until cleared) | 23 (0) | Needs PEND first seen as 1; the DUT never shows it |
| Claude | `R_APB_6_CTRL` | 111 (1) | Accepts EN=0 after EN was written 1 (one-shot completion) but records nothing about what that implies |

**7. Classification.**
* **Both: insufficient temporal history (inference), not missing syntax.** A port-only checker can know an expiration happened only from observed evidence. Examples: a CTRL read showing EN=0 after EN was written 1 in one-shot mode, or a COUNT readback that jumps up without a start or restart. Neither checker keeps that evidence.
* **Stimulus/observability limit at the first divergence (EX05):** no read precedes the reset. A rule-2-compliant checker could only know that cycle 52 was an expiration by modelling the counter (SHADOW=0, PSC=0 ⇒ the first enabled cycle expires). That is outside this experiment's contract.

**8. What a DV engineer would change.**
* Add history-based inference: *once a port observation proves an expiration occurred, with no PEND W1C since, a STATUS read returns PEND=1* (R-INT-1).
  * Evidence: a one-shot completion seen as an EN=0 readback, or a periodic reload seen as a COUNT readback increase.
  * Transcribed (H2): **0 false positives on the reference** (8 attempts).
  * It fails on M09 at **cycle 4140** (RND16): CTRL read at 4124 = 0x2 (EN=0 after EN=1 one-shot), then the STATUS read at 4140 returns PEND=0 instead of 1.
  * It detects late; the earlier 21 STATUS-read divergences had no preceding port evidence of an expiration.
* Add directed stimulus that reads STATUS or CTRL after an IE=0 expiration, and before re-enabling IE. EX05 exercises exactly the masked expiration but never reads it back.
* An equally valid industrial choice is a **scoreboard or reference model at the ports.** That is a different verification method from assertions, and rule 2 intentionally excludes it here.

## Summary for the write-up

| Mutant | Port channel | GPT miss cause | Claude miss cause | Smallest fix (outside the frozen artifacts) |
|---|---|---|---|---|
| M07 | irq (dominant), PSCNT/COUNT/STATUS readback | Property gap: no PCNT/PSC or COUNT-progress property | Correct relation, over-narrow antecedent; vacuous under these vectors (1 attempt, 0 in the window) | Single-read invariant PCNT ≤ PSC while running (caught at cycle 1182), plus back-to-back read stimulus |
| M09 | irq (dominant), STATUS.PEND readback | No inference of expirations; deliberately treats STATUS as unknown after any enabled interval | Consistency checks only; EN=0 readback after EN=1 not used as evidence | History-based "expiration observed ⇒ PEND=1" (caught at cycle 4140), plus a STATUS read after a masked expiration |

Both misses illustrate the experiment's main result. Port-consistent defects defeat consistency-style black-box assertions. Black-box detection then depends on value invariants and on evidence-carrying history, and on stimulus that makes the evidence observable.
