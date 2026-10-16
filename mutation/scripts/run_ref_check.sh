#!/bin/bash
# STEP 1: establish reference correctness against the spec examples, directed and seeded-random vectors.
# PASS requires 0 SPEC_MISMATCH cycles (outputs + architectural state vs. spec-model expected values).
# Optional:  ./scripts/run_ref_check.sh all   also checks the four ORIGINAL generated RTLs (read-only).
source "$(dirname "$0")/common.sh"
verify_gen
mkdir -p "$RES/ref_check"
targets="ref"
[ "${1:-}" = "all" ] && targets="ref rtl_gpt_1 rtl_gpt_2 rtl_claude_1 rtl_claude_2"
for t in $targets; do
  case $t in
    ref)          files="$REFDUT"; defs="" ;;
    rtl_claude_*) files="$GEN_DIR/$t.sv"; defs="+define+STATE_Q" ;;
    *)            files="$GEN_DIR/$t.sv"; defs="" ;;
  esac
  if build "chk_$t" "$defs" "$TB" "$REF" $files; then
    run "chk_$t" "$RES/ref_check/$t.log"
    s=$(summary "$RES/ref_check/$t.log")
    if echo "$s" | grep -q "spec_mismatch_cycles=0 "; then v=PASS; else v=FAIL; fi
    echo "$t: $v   $s"
  else
    echo "$t: COMPILE_FAIL (build/chk_$t/compile.log)"
  fi
done | tee "$RES/ref_check/summary.txt"
