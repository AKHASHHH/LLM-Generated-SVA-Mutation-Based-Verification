# Methodology review (done before delivery)

Each risk is listed with the mitigation built into the package and the residual risk that remains.

## 1. Common-mode reference bugs

**Risk.** The reference RTL (`ref/apb_timer_ref.sv`), the spec model behind the expected values (`scripts/specmodel.py`) and the specification were all written by Claude Opus. One shared misreading would make all three agree while all being wrong.

**Mitigations.**
* The reference is **formally proven equivalent** to all four independently generated RTLs (GPT ×2, Sonnet ×2):
  * Yosys k-induction over all 4 outputs and all 10 state elements;
  * unconstrained inputs;
  * both `async2sync` and true asynchronous reset (`clk2fflogic`).

  See `evidence/ref_equivalence/`. A shared misreading would therefore have to be shared by five implementations from three model families.
* The 23 example tables were re-checked row by row by a separately written checker before the spec was frozen.
* The two SVA sets were written independently of all of the above. An SVA failure on the reference is **adjudicated against the spec text**, never dismissed as an SVA error by default (see 5).

**Residual risk.** A misreading shared by the spec author and all four generated RTLs would only show up as an SVA "false positive". That is why every false positive gets a spec-text adjudication.

## 2. Vacuous passes

* **sva_gpt_1 cannot pass vacuously on the state checks.**
  * Its 10 per-field properties use antecedent `1'b1`, so they are attempted every cycle.
  * Its output checks are deferred immediate assertions, evaluated whenever their inputs change.
* **sva_claude_1 has conditional antecedents**, so an assertion can pass without ever firing. Vacuity only matters for a **MISS**. For every MISSED cell, check that the assertions expected to catch the mutant actually had a true antecedent in the divergence window (README, "Adjudicating a miss"). Two ways:
  * use Verdi;
  * use VCS assertion coverage (optional; see README).
* The directed tests (`D01`–`D18`) were built to make coincidence antecedents true. Each one was checked against the spec model to confirm it hits its intended condition: an expiration in the same cycle as the write, a given PEND value, and so on.

## 3. Simulator sampling races

* **Inputs change only at falling clock edges, and checks run 2 ns later.** The testbench never changes an input at a rising edge.
* **Concurrent assertions sample in the preponed region at the rising edge.** At that point the inputs have been stable for half a cycle.
* **Claude's output checks also sample at the falling edge (preponed).** They see the pre-change inputs together with the current state and outputs, a consistent snapshot. The correct design satisfies those combinational identities at every instant.
* **GPT's `assert final` checks run in the postponed region**, after combinational settling, so they cannot see glitches.
* **The reference instance and the DUT get identical inputs**, so differential checks have no ordering dependency.

## 4. Reset timing

* **Time 0.** `PRESETn` goes X→0 at time 0 after `#0`, so every `@(negedge PRESETn)` process sees the edge in time step 0. That covers the DUT, the reference, and Claude's asynchronous check. There is no clock event at time 0.
* **Every reset spans a clock edge, as R-RST-3 requires.** Each test begins with a reset cycle: `PRESETn` asserts at a falling edge, stays low through the next rising edge, and releases at the following falling edge.
* **Reset during an access cycle** is exercised by `D12_RESET_DURING_ACCESS`, with `irq` = 1 beforehand.
* **Sub-cycle reset pulses are not generated.** They are excluded by spec R-RST-3.

## 5. False-positive classification

**Rule.** A failure of an SVA assertion in the reference run is a candidate false positive.

1. **Check the harness first:** binding, time-0 behaviour, timescale. If the harness caused it, fix the harness, rerun, and document the cause. The SVA file is never changed for this.
2. **Otherwise, adjudicate against the spec text.** The reference matches the spec model on all 8,348 cycles and is equivalent to four independent RTLs, so the default expectation is an SVA defect. A failing assertion that contradicts a cited R-ID is a **natural defect in the generated SVA**, which is a reportable finding. If the spec text supports the assertion instead, it is a reference-side problem: stop and escalate.
3. **Detection is measured net of false positives.** A mutant counts as DETECTED only if its run contains a failure (label, time) that does not occur in the reference run with the identical vectors. A noisy assertion therefore cannot manufacture a detection.

## 6. Activation versus detection

* **Activated:** at least one cycle in which the mutant's outputs or architectural state differ from the reference instance (`REF_DIVERGE`). The no-SVA activation runs measure this, so it does not depend on whether the SVA compiles.
* **Port-visible divergence** is reported separately. The SVA hookup is white-box, so state-only divergence is observable to it, but not to a port-only checker.
* **NOT_ACTIVATED mutants are excluded** from the kill rate and never counted as misses.

## 7. Limitations (state them in the write-up)

* **Mutant selection.** Opus chose and wrote the 10 mutants. They represent one engineer's model of realistic misconceptions, not a statistically sampled fault space.
* **Sample size.** One SVA file per model and one stimulus suite of 8,348 cycles. The results describe these two files, not the models in general.
* **Prompt dependence.** Assertion style depends on the generation prompt. The per-field "next-state as properties" structure of sva_gpt_1 is a declarative full model; record the exact prompt used.
* **Simulation, not proof.** Concurrent SVA is not formally proven here: open-source Yosys lacks full concurrent-SVA support. A MISS means "no failure under these vectors".
