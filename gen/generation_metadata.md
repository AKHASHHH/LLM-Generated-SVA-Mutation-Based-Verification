# Project 4 LLM Generation Metadata

Generation date: October 13, 2026

## GPT
Model: GPT-6.1 Sol
Effort: Medium

Generated artifacts:
- rtl_gpt_1.sv
- rtl_gpt_2.sv
- sva_gpt_1.sv

## Claude
Model: Claude Sonnet 5.5
Effort: Medium

Generated artifacts:
- rtl_claude_1.sv
- rtl_claude_2.sv
- sva_claude_1.sv

## Experimental controls
- Each artifact was generated in a separate fresh conversation.
- All models received the same frozen timer specification.
- RTL generators were not shown the human oracle.
- Checkers were not shown DUT RTL.
- Generated files were preserved as first-generation outputs.
- Frozen generated artifacts are preserved in gen/ and verified against GEN_MANIFEST.sha256. Raw black-box responses are preserved separately in mutation/blackbox/gen/.

Integration normalization: generated artifacts did not include a `timescale directive. Working copies were prefixed with `timescale 1ns/1ps to match the oracle/testbench. No functional logic was modified.
