# SVA integration review (before any VCS run)

Files reviewed (unmodified originals; SHA-256 in `docs/gen_sha256.txt`):

| File | SHA-256 (first 16) | Lines | Assertion style |
|---|---|---|---|
| `sva_gpt_1.sv` | `1056af85740d0d55` | 182 | 25 assertions: 6 deferred immediate (`assert final`; 4 output checks + 2 reset checks); 19 concurrent = 10 per-field next-state properties (`1'b1 \|=> field == f($past(...))`), one for every architectural state element, + 8 coincidence properties + 1 reset-edge property. No covers. |
| `sva_claude_1.sv` | `66234d6abc767bea` | 449 | 105 assertions: 83 rule-local concurrent assertions via the `CHK` macro (each tagged with R-IDs) + 21 explicit concurrent assertions (reset and output checks, the latter clocked on both clock edges) + 1 procedural immediate async-reset check; 11 `cover property` |

## 1. Static compile result

Both files were elaborated with **slang 12.0** (a strict IEEE 1800-2017 front end):
* standalone;
* bound into `tb/tb_top.sv` with the reference DUT;
* with each of the 10 mutants;
* with each of the 4 generated RTLs.

Every configuration reported **0 errors, 0 warnings**. This does not prove VCS will accept them. The VCS first-pass result is recorded separately by `scripts/run_sva_compile.sh` and is the authoritative one.

## 2. Constructs that carry VCS-specific risk (original-source)

Neither file was changed. If VCS rejects one of these, classify it as an *original-source / tool-compatibility* problem.

| ID | File | Construct | Note |
|---|---|---|---|
| G1 | sva_gpt_1 | `assert final (...)` (deferred final immediate assertions, IEEE 1800-2012) inside `always_comb`, some under `if (!PRESETn)` | The most likely VCS compile risk in either file. The minimal correction, if needed, is `assert final` → `assert #0`, which is also a deferred, glitch-free check. Make it in `sva_corrected/` only. |
| C1 | sva_claude_1 | Macro stringification `` `"LBL`" `` inside the multi-line `` `define CHK `` | SV-2009 feature; standard. |
| C2 | sva_claude_1 | `` `define OCLK @(posedge PCLK or negedge PCLK) disable iff (1'b0) `` used inside `assert property(...)` | Legal multi-edge clocking event. |
| C3 | sva_claude_1 | `always @(negedge PRESETn) begin #1; ... assert ...` | Needs a time unit. The file has no `` `timescale ``; the harness supplies `-timescale=1ns/1ps` (see 3). |
| C4 | sva_claude_1 | `default clocking` + `default disable iff (!PRESETn)` inside the module, with explicit overrides on some properties | Legal. |

## 3. Harness and binding requirements (handled in the testbench; NOT source problems)

| Requirement | Why | How the harness meets it |
|---|---|---|
| Both files declare `module apb_timer_sva` | They cannot be compiled into the same simulation. | One build per SVA set. No source rename. |
| `a_*` architectural-state inputs | Not ports of `apb_timer`. | Connected by hierarchical reference to the DUT's state registers (`dut.en` … `dut.ovf`; `+define+STATE_Q` selects `*_q` names for rtl_claude_1/2). The mutants share the reference's names. |
| Timescale | C3 uses `#1`; the TB has a `` `timescale ``. | `-timescale=1ns/1ps` on every VCS build. |
| Defined state before the first assertion evaluation | GPT's deferred assertions evaluate at time 0. An X state there would raise a spurious failure. | TB drives `PRESETn` X→0 at time 0 (after `#0`), so every async reset fires in time step 0. |
| No clock edge at time 0 | Claude's both-edge output checks would sample X at a time-0 X→0 "negedge". | `PCLK` gets a declaration initializer, so there is no event at 0. |
| `-assert svaext` | Some VCS versions need it for extended SVA. | Added only to builds that include an SVA file. |

## 4. Observations (structure only — not detection claims)

* **sva_gpt_1 checks everything the testbench checks.** It constrains every one of the 10 architectural state elements cycle-to-cycle and all 4 outputs combinationally. If those properties are correct, any mutant that changes architectural state or outputs under the vectors should violate at least one of them. The measured result is what tests this.
* **sva_claude_1 is rule-local**: one assertion per rule or coincidence case, with conditional antecedents. Whether its coverage of all state changes is complete is an empirical question for the matrix.
* **Weak property noticed during review:** `PRI5_exp_pend0_status_ovf_clear`. Its consequent `(a_pend && !a_ovf == !$past(a_ovf) || a_pend)` reduces, by operator precedence, to `a_pend`. It never checks the OVF-clear behavior its label names. It compiles and cannot raise a false positive, but it is weaker than labeled.
* `APB5_reserved_ignored` repeats part of `PRI6_ctrl_write`. This is redundant, not wrong.

No corrected copies exist. `sva_corrected/` stays empty unless VCS rejects an original file (see `sva_corrected/README.md`).
