# Experiment 2: Black-Box SVA Generation Provenance

## Experiment Information

**Project:** Evaluating LLM-Generated SystemVerilog Assertions Through Mutation-Based Design Verification

**Experiment:** 2 — Black-Box vs. White-Box Assertion Verification

**Generation date:** October 15, 2026

**Objective:** Evaluate independently generated, port-only SystemVerilog assertion checkers against a frozen APB programmable timer specification.

Both checkers were requested using the same generation prompt, specification, and module interface. They were not provided with the DUT implementation, mutation descriptions, reference model, or previous experimental results.

## 1. Model Generation Records

| Field | GPT | Claude |
|---|---|---|
| Generated source | `gen/sva_bb_gpt_1.sv` | `gen/sva_bb_claude_1.sv` |
| Model | GPT-6 | Claude Sonnet |
| Exact model version / setting | [CONFIRM] | [CONFIRM] |
| Generation date | 2026-10-15 | 2026-10-15 |
| Generation time (ET) | [CONFIRM] | [CONFIRM] |
| Fresh conversation | [CONFIRM] | [CONFIRM] |
| Memory disabled | [CONFIRM] | [CONFIRM] |
| Outside original DV project conversation | [CONFIRM] | [CONFIRM] |
| Generation attempts | 1 (confirm) | 1 (confirm) |
| Follow-up corrections | 0 (confirm) | 0 (confirm) |
| Raw response | `gen/raw_gpt_1.txt` | `gen/raw_claude_1.txt` |
| Extracted SystemVerilog | `gen/sva_bb_gpt_1.sv` | `gen/sva_bb_claude_1.sv` |

## 2. Frozen Generation Inputs

**Generation prompt:** `prompt/BB_PROMPT.txt`

SHA-256:

`41f49add1d1d7d4a004c2376fc5e38b1e4237b15cf379016ad9292d33705fa19`

**Specification:** `APBTMR_SPEC_v1.0.md`

SHA-256:

`1b14ffc0c2f1deda39e12818fab75b78bd4c709d48019254c4c85a701e6bd457`

Both models received the complete generation prompt followed by the complete frozen specification.

## 3. Checker Interface

Both models were instructed to generate the module:

`apb_timer_bb_sva`

The checker interface contains exactly 11 external DUT signals:

- `PCLK`
- `PRESETn`
- `PSEL`
- `PENABLE`
- `PWRITE`
- `PADDR`
- `PWDATA`
- `PRDATA`
- `PREADY`
- `PSLVERR`
- `irq`

Direct access to DUT internal registers, architectural state probes, reference-model signals, and hierarchical DUT signals was prohibited.

Checker-local history derived from observable interface signals was permitted. A procedural model of the timer's counting and next-state behavior was prohibited.

## 4. Original Artifact Preservation

The original model responses are preserved separately from the extracted SystemVerilog modules.

| Artifact | Filename |
|---|---|
| GPT original response | `gen/raw_gpt_1.txt` |
| Claude original response | `gen/raw_claude_1.txt` |
| GPT extracted checker | `gen/sva_bb_gpt_1.sv` |
| Claude extracted checker | `gen/sva_bb_claude_1.sv` |
| SHA-256 manifest | `gen/bb_sha256.txt` |

The extracted SystemVerilog files are first-pass generation artifacts. No source-level corrections should be applied to these originals.

Any subsequent compilation fixes or functional modifications must be preserved as separately named variants, with their changes explicitly documented.

## 5. SHA-256 Verification

The four original artifacts are tracked in:

`gen/bb_sha256.txt`

Verification command:

`sha256sum -c gen/bb_sha256.txt`

**Source file hashes:**

- GPT: [COPY HASH FROM MANIFEST]
- Claude: [COPY HASH FROM MANIFEST]

## 6. Experimental Independence

The intended generation procedure was:

1. Use separate conversations for GPT and Claude.
2. Provide identical frozen prompts and specifications.
3. Generate each checker only once.
4. Preserve the first response without functional revision.
5. Keep each model unaware of the other model's implementation.
6. Exclude all mutant implementations, detection results, and existing assertion checkers from the generation inputs.

**Actual session conditions must be confirmed in Section 1 before this record is finalized.**

## 7. Verification Status

**Generation date:** October 15, 2026

**Source files transferred to FASTX:** Complete

**Original raw responses preserved:** Complete

**SHA-256 manifest:** `gen/bb_sha256.txt`

**SHA-256 integrity verification:** PASS (4/4 artifacts)

Verified artifacts:

- `gen/sva_bb_gpt_1.sv` — PASS
- `gen/sva_bb_claude_1.sv` — PASS
- `gen/raw_gpt_1.txt` — PASS
- `gen/raw_claude_1.txt` — PASS

**Standalone compilation / interface isolation:** Not yet tested

**Synopsys VCS compilation:** Not yet tested

**Reference baseline validation:** Not yet tested

**Mutation testing:** Not yet performed

**Black-box versus white-box comparison:** Pending

### Artifact Integrity

All four original generation artifacts were verified using:

`sha256sum -c gen/bb_sha256.txt`

All four files returned `OK`. The original first-pass checker source files have been retained without modifications.

### Experimental Status

Generation and artifact preservation are complete. The next stage is standalone checker isolation, followed by Synopsys VCS compilation and reference validation.

No claims about black-box checker correctness, mutation detection rates, or comparative performance are made at this stage.
---

**Provenance policy:** Once the generation details have been confirmed and the hashes verified, this document and the original generated artifacts should be preserved unchanged. Any later corrections must be documented separately.
