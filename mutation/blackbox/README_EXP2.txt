Experiment 2 (black-box checkers). Lives entirely in mutation/blackbox/. Changes no existing file.
  prompt/     BB_PROMPT.txt (+ .sha256)            frozen generation prompt
  interface/  apb_timer_bb_sva_header.sv           the 11-port contract
  gen/        your frozen checkers, raw responses, bb_sha256.txt, GEN_PROVENANCE.md (never written by scripts)
  tb/         bb_bind.sv (default hook), bb_bind_unit.sv (single-top fallback)   bind into the unchanged tb_top
  fixtures/   harness self-tests only, never reported
  scripts/    run_bb.sh (iso, base, det, matrix), bb_matrix.py (gate + audited matrix)
  docs/       EXPERIMENT2_PLAN.md, BB_CHECKER_REVIEW.md, RUNNER.md, BB_FROZEN_SHA256.txt, BB_BASELINE_ADJUDICATION.tsv
  results/, build/  created by run_bb.sh
