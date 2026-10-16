#!/bin/bash
# Decisive time-0 experiment (reference DUT, no mutants). Writes only to results_validation/time0_v2/ and
# build_validation/time0_v2/. Never touches results/, earlier validation results, or the generated originals.
#   E1  logic PCLK = 1'b0      (first-run harness)
#   E2  bit   PCLK = 1'b0      (phase-A "fix" that did not work)
#   E3  PCLK = X until 1 ns    (+define+CLK_START_1NS: no time-0 edge on ANY net carrying PCLK)
# Every build adds +define+DIAG_PORTCLK: a TB cover on @(posedge u_sva.PCLK or negedge u_sva.PCLK), i.e. the
# SVA instance's OWN port net and the same clocking event as sva_claude_1's OCLK checks, printing the values
# those checks sample. Claude builds also print the SVA-internal nets acc/err/rd_acc/mapped.
# Usage: ./scripts/run_time0_experiment.sh
here=$(cd "$(dirname "$0")" && pwd); root=$(cd "$here/.." && pwd)
export RES_DIR="$root/results_validation/time0_v2" BUILD_DIR="$root/build_validation/time0_v2" TB_DEFINES=""
[ -e "$RES_DIR/time0_v2_summary.txt" ] && { echo "time-0 evidence exists in results_validation/time0_v2/; kept, not rerun"; exit 0; }
source "$here/common.sh"
verify_gen
for cfg in "E1_logic_pclk:" "E2_bit_pclk:+define+CLK2STATE" "E3_clk_start_1ns:+define+CLK_START_1NS"; do
  n=${cfg%%:*}; d=${cfg#*:}
  for s in claude gpt; do
    extra="+define+DIAG_PORTCLK"; [ $s = claude ] && extra="$extra +define+DIAG_SVA_INTERNALS"
    if build "${s}_$n" "+define+WITH_SVA $SVA_OPTS $extra $d" "$TB" "$REF" "$REFDUT" "$GEN_DIR/sva_${s}_1.sv"; then
      run "${s}_$n" "$RES/${s}_$n.log"
    else
      echo "COMPILE_FAIL" > "$RES/${s}_$n.log"; echo "${s}_$n: COMPILE_FAIL (see $BUILD/${s}_$n/compile.log)"
    fi
  done
done
{
  echo "TIME-0 EXPERIMENT v2 (reference DUT; identical vectors; only the PCLK start-up differs)"
  for n in E1_logic_pclk E2_bit_pclk E3_clk_start_1ns; do
    echo; echo "== $n"
    for s in claude gpt; do
      f="$RES/${s}_$n.log"
      all=$(grep 'u_sva\.' "$f" | grep -iE 'failed|error' | grep -v TBDIAG)
      t0=$(echo "$all" | grep -cE '(failed at|at time) 0 ?(ps|ns)\b')
      tot=$(echo "$all" | grep -c 'u_sva')
      echo "  sva_$s: SVA failure lines at t=0: $t0   all SVA failure lines: $tot   | $(grep -h TBSUMMARY "$f" | grep -oE 'cycles=[0-9]+ spec_mismatch_cycles=[0-9]+')"
      echo "$all" | grep -E '(failed at|at time) 0 ?(ps|ns)\b' | head -4 | sed 's/^/      /'
      grep -h "TBDIAG2" "$f" | sed 's/^/      /'
    done
  done
} | tee "$RES/time0_v2_summary.txt"
